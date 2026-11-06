defmodule UptimeMonitor.Monitoring do
  @moduledoc """
  Services, checks and incidents.

  Scheduled checks run as Oban jobs (`Workers.Scheduler` enqueues due services
  every minute, `Workers.CheckService` performs them); `check_now/1` performs
  an unscheduled check synchronously.
  """
  import Ecto.Query

  alias Ecto.Multi
  alias UptimeMonitor.Repo

  alias UptimeMonitor.Monitoring.{
    Check,
    CheckRollup,
    Events,
    HttpCheck,
    Incident,
    IncidentTracker,
    Service
  }

  ## Services

  @doc "Lists all services ordered by name."
  def list_services do
    Repo.all(from s in Service, order_by: [asc: fragment("lower(?)", s.name), asc: s.id])
  end

  @doc "Lists services flagged as public, ordered by name."
  def list_public_services do
    Repo.all(
      from s in Service,
        where: s.public,
        order_by: [asc: fragment("lower(?)", s.name), asc: s.id]
    )
  end

  def get_service!(id), do: Repo.get!(Service, id)
  def get_service(id), do: Repo.get(Service, id)

  @doc "Returns a public service by id, or nil if it does not exist or is private."
  def get_public_service(id) do
    Repo.one(from s in Service, where: s.id == ^id and s.public)
  end

  def change_service(%Service{} = service, attrs \\ %{}), do: Service.changeset(service, attrs)

  @doc "Creates a service. The first check is scheduled immediately."
  def create_service(attrs, opts \\ []) do
    %Service{next_check_at: DateTime.utc_now()}
    |> Service.changeset(attrs, opts)
    |> Repo.insert()
    |> tap_ok(&Events.service_changed(:service_created, &1))
  end

  @doc """
  Updates a service. When the interval is shortened the next check is pulled
  forward so the new interval applies immediately.
  """
  def update_service(%Service{} = service, attrs, opts \\ []) do
    changeset = Service.changeset(service, attrs, opts)

    changeset =
      case Ecto.Changeset.fetch_change(changeset, :interval_minutes) do
        {:ok, minutes} ->
          latest = DateTime.add(DateTime.utc_now(), minutes, :minute)

          if DateTime.compare(service.next_check_at, latest) == :gt,
            do: Ecto.Changeset.put_change(changeset, :next_check_at, latest),
            else: changeset

        :error ->
          changeset
      end

    changeset
    |> Repo.update()
    |> tap_ok(&Events.service_changed(:service_updated, &1, service))
  end

  @doc "Deletes a service with its checks, statistics and incidents."
  def delete_service(%Service{} = service) do
    service
    |> Repo.delete()
    |> tap_ok(&Events.service_changed(:service_deleted, &1, service))
  end

  ## Checks

  @doc """
  Check Now: performs an unscheduled check of the service synchronously,
  records it like any other check (it counts toward incident series) and
  broadcasts the usual events. The regular schedule is not changed.

  Returns `{:ok, %{service: service, check: check}}` or `{:error, :not_found}`.
  """
  def check_now(%Service{id: id}), do: check_now(id)

  def check_now(id) do
    case get_service(id) do
      nil -> {:error, :not_found}
      service -> service |> run_check() |> then(&record_check(service.id, &1, manual: true))
    end
  end

  @doc "Performs a scheduled check (called by the Oban worker)."
  def perform_scheduled_check(service_id) do
    case get_service(service_id) do
      nil -> {:error, :not_found}
      service -> service |> run_check() |> then(&record_check(service.id, &1))
    end
  end

  defp run_check(%Service{url: url}), do: HttpCheck.run(url)

  @doc """
  Stores a check result for a service, updates its rollup, status and
  incident state atomically (the service row is locked), then broadcasts events.
  """
  def record_check(service_id, %HttpCheck.Result{} = result, opts \\ []) do
    Multi.new()
    |> Multi.run(:service, fn repo, _ ->
      case repo.one(from s in Service, where: s.id == ^service_id, lock: "FOR UPDATE") do
        nil -> {:error, :not_found}
        service -> {:ok, service}
      end
    end)
    |> Multi.insert(:check, fn _ ->
      %Check{
        service_id: service_id,
        checked_at: result.checked_at,
        result: result.result,
        status_code: result.status_code,
        response_time_ms: result.response_time_ms,
        error: result.error,
        manual: Keyword.get(opts, :manual, false)
      }
    end)
    |> Multi.run(:rollup, fn repo, %{check: check} -> upsert_rollup(repo, check) end)
    |> Multi.run(:open_incident, fn repo, _ ->
      {:ok,
       repo.one(from i in Incident, where: i.service_id == ^service_id and is_nil(i.ended_at))}
    end)
    |> Multi.run(:transition, fn repo, %{service: service, open_incident: open} ->
      apply_result(repo, service, open, result)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{service: before, check: check, transition: {service, incident_event}}} ->
        Events.check_completed(service, check)

        if before.status != service.status,
          do: Events.status_changed(service, before.status, service.status)

        case incident_event do
          {event, incident} -> Events.incident(event, service, incident)
          nil -> :ok
        end

        {:ok, %{service: service, check: check}}

      {:error, :service, :not_found, _} ->
        {:error, :not_found}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  defp upsert_rollup(repo, %Check{} = check) do
    bucket = %{DateTime.truncate(check.checked_at, :second) | minute: 0, second: 0}
    success? = check.result in [:up, :degraded]
    timed = success? and is_integer(check.response_time_ms)

    row = %{
      service_id: check.service_id,
      bucket_start: bucket,
      total_count: 1,
      up_count: if(check.result == :up, do: 1, else: 0),
      degraded_count: if(check.result == :degraded, do: 1, else: 0),
      down_count: if(check.result == :down, do: 1, else: 0),
      response_time_sum_ms: if(timed, do: check.response_time_ms, else: 0),
      response_time_count: if(timed, do: 1, else: 0)
    }

    inc = row |> Map.drop([:service_id, :bucket_start]) |> Enum.to_list()

    repo.insert_all(CheckRollup, [row],
      on_conflict: [inc: inc],
      conflict_target: [:service_id, :bucket_start]
    )

    {:ok, row}
  end

  defp apply_result(repo, service, open_incident, result) do
    tracker = %IncidentTracker{
      consecutive_failures: service.consecutive_failures,
      consecutive_successes: service.consecutive_successes,
      streak_started_at: service.streak_started_at,
      open_incident?: open_incident != nil
    }

    {tracker, action} =
      IncidentTracker.step(tracker, result.result, result.checked_at, result.error)

    incident_result =
      case action do
        :none ->
          {:ok, nil}

        {:open, started_at, reason} ->
          %Incident{service_id: service.id, started_at: started_at, reason: reason}
          |> repo.insert()
          |> map_ok(&{:incident_opened, &1})

        {:close, ended_at} ->
          open_incident
          |> Ecto.Changeset.change(ended_at: ended_at)
          |> repo.update()
          |> map_ok(&{:incident_resolved, &1})
      end

    with {:ok, incident_event} <- incident_result,
         {:ok, service} <-
           service
           |> Ecto.Changeset.change(
             status: result.result,
             consecutive_failures: tracker.consecutive_failures,
             consecutive_successes: tracker.consecutive_successes,
             streak_started_at: tracker.streak_started_at,
             last_checked_at: result.checked_at,
             last_response_time_ms: result.response_time_ms,
             last_status_code: result.status_code,
             last_error: result.error
           )
           |> repo.update() do
      {:ok, {service, incident_event}}
    end
  end

  @doc "Most recent checks of a service, newest first."
  def list_recent_checks(service_id, limit \\ 50) do
    Repo.all(
      from c in Check,
        where: c.service_id == ^service_id,
        order_by: [desc: c.checked_at, desc: c.id],
        limit: ^limit
    )
  end

  ## Incidents

  @doc "Returns the open incident of a service, if any."
  def get_open_incident(service_id) do
    Repo.one(from i in Incident, where: i.service_id == ^service_id and is_nil(i.ended_at))
  end

  @doc """
  Lists incidents, newest first. Options: `:service_id`, `:since` (incidents
  overlapping the time after it), `:public_only`, `:limit`.
  """
  def list_incidents(opts \\ []) do
    query =
      from i in Incident,
        join: s in assoc(i, :service),
        order_by: [desc: i.started_at, desc: i.id],
        preload: [service: s]

    query =
      Enum.reduce(opts, query, fn
        {:service_id, id}, q -> where(q, [i], i.service_id == ^id)
        {:since, since}, q -> where(q, [i], is_nil(i.ended_at) or i.ended_at >= ^since)
        {:public_only, true}, q -> where(q, [_i, s], s.public)
        {:limit, limit}, q -> limit(q, ^limit)
        _, q -> q
      end)

    Repo.all(query)
  end

  defp tap_ok({:ok, value} = ok, fun) do
    fun.(value)
    ok
  end

  defp tap_ok(error, _fun), do: error

  defp map_ok({:ok, value}, fun), do: {:ok, fun.(value)}
  defp map_ok(error, _fun), do: error
end
