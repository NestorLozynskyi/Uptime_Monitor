defmodule UptimeMonitor.Monitoring.Workers.CheckService do
  @moduledoc """
  Performs one scheduled check. Jobs are unique per service while incomplete,
  so a service never has two pending/running scheduled checks.
  """
  use Oban.Worker,
    queue: :checks,
    max_attempts: 3,
    unique: [keys: [:service_id], states: :incomplete, period: :infinity]

  alias UptimeMonitor.Monitoring

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"service_id" => service_id}}) do
    case Monitoring.perform_scheduled_check(service_id) do
      {:ok, _} -> :ok
      {:error, :not_found} -> {:cancel, :service_deleted}
      {:error, reason} -> {:error, reason}
    end
  end

  # Check timeout is 10 s; leave room for DB work.
  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(60)
end
