defmodule Mix.Tasks.Uptime.DemoTarget do
  @shortdoc "Runs the demo target HTTP service (port DEMO_TARGET_PORT, default 4100)"
  @moduledoc "Runs `UptimeMonitor.Demo.Target` standalone for local development."
  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("compile")
    UptimeMonitor.Demo.Target.serve()
  end
end
