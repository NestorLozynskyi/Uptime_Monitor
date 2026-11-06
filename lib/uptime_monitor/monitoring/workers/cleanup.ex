defmodule UptimeMonitor.Monitoring.Workers.Cleanup do
  @moduledoc "Hourly retention cleanup (Oban cron), see `UptimeMonitor.Monitoring.Retention`."
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    counts = UptimeMonitor.Monitoring.Retention.cleanup()
    Logger.info("Retention cleanup: #{inspect(counts)}")
    :ok
  end
end
