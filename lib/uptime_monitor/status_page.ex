defmodule UptimeMonitor.StatusPage do
  @moduledoc """
  Data for the public status page (no authentication). Only services flagged
  as public are included, through the `PublicView` projections (no URLs or
  raw error details). Live updates: `Monitoring.Events.subscribe_public/0`.
  """
  alias UptimeMonitor.Monitoring
  alias UptimeMonitor.Monitoring.{PublicView, Stats}

  @doc """
  Returns the overall status, public services with their statistics for the
  period (uptime, average response time, incident count and availability
  buckets) and incidents of public services overlapping the period.
  """
  def overview(period \\ :month, now \\ DateTime.utc_now(), opts \\ []) do
    services = Monitoring.list_public_services()

    entries =
      for service <- services do
        stats = Stats.service_stats(service.id, period, now, opts)

        service
        |> PublicView.service()
        |> Map.merge(%{
          uptime_pct: stats.uptime_pct,
          avg_response_ms: stats.avg_response_ms,
          incident_count: stats.incident_count,
          buckets: stats.buckets
        })
      end

    since = DateTime.add(now, -period_seconds(period), :second)

    incidents =
      [since: since, public_only: true, limit: 50]
      |> Monitoring.list_incidents()
      |> Enum.map(&Map.put(PublicView.incident(&1), :service_name, &1.service.name))

    %{
      period: period,
      generated_at: now,
      overall_status: overall_status(services),
      services: entries,
      incidents: incidents
    }
  end

  @doc "Statistics of a single public service, or `{:error, :not_found}` for private/missing ones."
  def service_stats(service_id, period, now \\ DateTime.utc_now()) do
    case Monitoring.get_public_service(service_id) do
      nil ->
        {:error, :not_found}

      service ->
        {:ok,
         %{
           service: PublicView.service(service),
           stats: Stats.service_stats(service.id, period, now)
         }}
    end
  end

  @doc """
  Overall status of the public services. Services without checks yet
  (`:pending`) do not affect it.

    * `:major_outage` — every checked service is down;
    * `:partial_outage` — at least one checked service is down;
    * `:degraded` — none down, at least one degraded;
    * `:operational` — every checked service is up;
    * `:no_data` — public services exist but none has been checked yet;
    * `:no_services` — no public services.
  """
  def overall_status([]), do: :no_services

  def overall_status(services) do
    statuses = services |> Enum.map(& &1.status) |> Enum.reject(&(&1 == :pending))

    cond do
      statuses == [] -> :no_data
      Enum.all?(statuses, &(&1 == :down)) -> :major_outage
      :down in statuses -> :partial_outage
      :degraded in statuses -> :degraded
      true -> :operational
    end
  end

  defp period_seconds(:day), do: 86_400
  defp period_seconds(:week), do: 7 * 86_400
  defp period_seconds(:month), do: 30 * 86_400
end
