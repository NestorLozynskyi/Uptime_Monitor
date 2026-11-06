defmodule UptimeMonitor.Monitoring.Check do
  @moduledoc "The stored result of one check (kept for 30 days)."
  use Ecto.Schema

  schema "checks" do
    belongs_to :service, UptimeMonitor.Monitoring.Service
    field :checked_at, :utc_datetime_usec
    field :result, Ecto.Enum, values: [:up, :degraded, :down]
    field :status_code, :integer
    field :response_time_ms, :integer
    field :error, :string
    field :manual, :boolean, default: false
  end
end
