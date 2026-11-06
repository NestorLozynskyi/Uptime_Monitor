defmodule UptimeMonitor.Monitoring.CheckRollup do
  @moduledoc """
  Hourly per-service aggregate of checks, maintained incrementally on every
  check insert. Used by the 7 d / 30 d statistics.
  """
  use Ecto.Schema

  @primary_key false
  schema "check_rollups" do
    field :service_id, :id, primary_key: true
    field :bucket_start, :utc_datetime, primary_key: true
    field :total_count, :integer, default: 0
    field :up_count, :integer, default: 0
    field :degraded_count, :integer, default: 0
    field :down_count, :integer, default: 0
    field :response_time_sum_ms, :integer, default: 0
    field :response_time_count, :integer, default: 0
  end
end
