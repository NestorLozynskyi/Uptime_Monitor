defmodule UptimeMonitor.Monitoring.Workers.Scheduler do
  @moduledoc """
  Runs every minute (Oban cron, leader node only). Enqueues a `CheckService`
  job for each service whose `next_check_at` is due and advances
  `next_check_at` by the service interval, in one transaction.

  State lives in the database, so nothing is lost on restart: services that
  became due while the app was down are checked on the first tick after
  start (once, without a catch-up burst). Duplicates are prevented by
  row locks (`FOR UPDATE SKIP LOCKED`) and job uniqueness per service.
  """
  use Oban.Worker, queue: :scheduler, max_attempts: 1

  import Ecto.Query

  alias UptimeMonitor.Repo
  alias UptimeMonitor.Monitoring.Service
  alias UptimeMonitor.Monitoring.Workers.CheckService

  @impl Oban.Worker
  def perform(_job) do
    {:ok, _} = schedule_due(DateTime.utc_now())
    :ok
  end

  @doc "Enqueues checks for services due at `now`. Returns `{:ok, enqueued_service_ids}`."
  def schedule_due(now) do
    # Align to the minute so a 1-minute service is due again on the next tick.
    tick = %{DateTime.truncate(now, :second) | second: 0} |> DateTime.add(0, :second)

    Repo.transaction(fn ->
      services =
        Repo.all(
          from s in Service,
            where: s.next_check_at <= ^now,
            order_by: s.next_check_at,
            lock: "FOR UPDATE SKIP LOCKED"
        )

      for service <- services do
        {:ok, _job} = Oban.insert(CheckService.new(%{service_id: service.id}))
        next = DateTime.add(tick, service.interval_minutes, :minute)

        service
        |> Ecto.Changeset.change(next_check_at: next |> to_usec())
        |> Repo.update!()

        service.id
      end
    end)
  end

  defp to_usec(%DateTime{microsecond: {us, _}} = dt), do: %{dt | microsecond: {us, 6}}
end
