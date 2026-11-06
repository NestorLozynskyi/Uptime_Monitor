defmodule UptimeMonitor.Monitoring.Service do
  @moduledoc "A monitored HTTP(S) endpoint and its current state."
  use Ecto.Schema
  import Ecto.Changeset

  alias UptimeMonitor.Monitoring.UrlGuard

  @intervals [1, 5, 15, 30, 60]
  @statuses [:pending, :up, :degraded, :down]

  schema "services" do
    field :name, :string
    field :url, :string
    field :interval_minutes, :integer, default: 5
    field :public, :boolean, default: false
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :consecutive_failures, :integer, default: 0
    field :consecutive_successes, :integer, default: 0
    field :streak_started_at, :utc_datetime_usec
    field :last_checked_at, :utc_datetime_usec
    field :last_response_time_ms, :integer
    field :last_status_code, :integer
    field :last_error, :string
    field :next_check_at, :utc_datetime_usec

    has_many :checks, UptimeMonitor.Monitoring.Check
    has_many :incidents, UptimeMonitor.Monitoring.Incident

    timestamps(type: :utc_datetime_usec)
  end

  def intervals, do: @intervals
  def statuses, do: @statuses

  @doc """
  Changeset for admin-editable fields. The URL is validated against the SSRF
  rules (including DNS resolution) whenever it changes.
  """
  def changeset(service, attrs, opts \\ []) do
    service
    |> cast(attrs, [:name, :url, :interval_minutes, :public])
    |> update_change(:name, &String.trim/1)
    |> update_change(:url, &String.trim/1)
    |> validate_required([:name, :url, :interval_minutes])
    |> validate_length(:name, max: 100)
    |> validate_length(:url, max: 2048)
    |> validate_inclusion(:interval_minutes, @intervals,
      message: "must be one of 1, 5, 15, 30 or 60 minutes"
    )
    |> validate_url(opts)
    |> check_constraint(:interval_minutes, name: :interval_minutes_allowed)
  end

  defp validate_url(changeset, opts) do
    validate_change(changeset, :url, fn :url, url ->
      case UrlGuard.resolve(url, opts) do
        {:ok, _target} -> []
        {:error, {kind, message}} -> [url: {message, kind: kind}]
      end
    end)
  end
end
