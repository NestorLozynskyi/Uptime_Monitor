defmodule UptimeMonitor.Monitoring.Incident do
  @moduledoc """
  A period of confirmed downtime: opened after 3 consecutive failed checks and
  resolved after 2 consecutive successful ones. `started_at` is the time of the
  first failed check of the series, `ended_at` the time of the first successful
  check of the recovering series. Kept for 90 days after resolution.
  """
  use Ecto.Schema

  schema "incidents" do
    belongs_to :service, UptimeMonitor.Monitoring.Service
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec
    field :reason, :string

    timestamps(type: :utc_datetime_usec)
  end

  def open?(%__MODULE__{ended_at: nil}), do: true
  def open?(%__MODULE__{}), do: false
end
