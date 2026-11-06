defmodule UptimeMonitor.Monitoring.PublicView do
  @moduledoc """
  Projections of monitoring data that are safe to expose on the public status
  page. They never include the monitored URL or raw error details.
  """
  alias UptimeMonitor.Monitoring.{Check, Incident, Service}

  def service(%Service{} = s) do
    %{
      id: s.id,
      name: s.name,
      status: s.status,
      interval_minutes: s.interval_minutes,
      last_checked_at: s.last_checked_at,
      last_response_time_ms: s.last_response_time_ms
    }
  end

  def check(%Check{} = c) do
    %{
      service_id: c.service_id,
      checked_at: c.checked_at,
      result: c.result,
      response_time_ms: c.response_time_ms
    }
  end

  def incident(%Incident{} = i) do
    %{
      id: i.id,
      service_id: i.service_id,
      started_at: i.started_at,
      ended_at: i.ended_at,
      reason: public_reason(i.reason)
    }
  end

  @doc "Reduces an internal failure reason to a generic public description."
  def public_reason("HTTP " <> _ = reason), do: reason
  def public_reason("Timed out" <> _), do: "Timeout"
  def public_reason("DNS" <> _), do: "DNS failure"
  def public_reason("Blocked" <> _), do: "Unavailable"
  def public_reason("Redirect blocked" <> _), do: "Unavailable"
  def public_reason(_), do: "Connection failure"
end
