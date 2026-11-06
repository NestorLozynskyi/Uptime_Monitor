# Puts the e2e database into a named state for screenshots, running real
# checks against the demo target. Runs in a separate VM (`mix run --no-start`),
# so the app's LiveViews see the result after a reload.
#
#   mix run --no-start e2e/scripts/scenario.exs public:<partial|major|degraded|operational>
#   mix run --no-start e2e/scripts/scenario.exs pending      # adds a never-checked service
#   mix run --no-start e2e/scripts/scenario.exs empty        # deletes every service
#   mix run --no-start e2e/scripts/scenario.exs reset        # only the demo services again
import Ecto.Query

for app <- [:postgrex, :ecto_sql, :req, :phoenix_pubsub], do: {:ok, _} = Application.ensure_all_started(app)
{:ok, _} = UptimeMonitor.Repo.start_link()
{:ok, _} = Phoenix.PubSub.Supervisor.start_link(name: UptimeMonitor.PubSub)
{:ok, _} = Task.Supervisor.start_link(name: UptimeMonitor.TaskSupervisor)
Logger.configure(level: :warning)

alias UptimeMonitor.{Monitoring, Repo}
alias UptimeMonitor.Monitoring.Service

target = System.fetch_env!("DEMO_TARGET_URL")

ensure = fn name, path ->
  url = target <> path

  case Repo.get_by(Service, name: name) do
    nil ->
      {:ok, s} = Monitoring.create_service(%{name: name, url: url, interval_minutes: 60, public: true})
      s

    s ->
      {:ok, s} = Monitoring.update_service(s, %{url: url, public: true, interval_minutes: 60})
      s
  end
end

case System.argv() do
  ["public:" <> state] ->
    paths =
      %{
        "operational" => ["/ok", "/ok", "/ok", "/ok"],
        "degraded" => ["/ok", "/ok", "/delay/3500", "/ok"],
        "partial" => ["/ok", "/ok", "/delay/3500", "/status/503"],
        "major" => ["/status/503", "/status/503", "/status/503", "/status/503"]
      }
      |> Map.fetch!(state)

    names = ["Website", "Public API", "Docs", "Billing API"]
    Repo.update_all(from(s in Service, where: s.name not in ^names), set: [public: false])

    names
    |> Enum.zip(paths)
    |> Enum.map(fn {name, path} -> ensure.(name, path) end)
    |> Enum.each(fn s -> {:ok, _} = Monitoring.check_now(s.id) end)

  ["pending"] ->
    {:ok, s} =
      Monitoring.create_service(%{name: "Staging", url: target <> "/ok", interval_minutes: 5})

    later = DateTime.add(DateTime.utc_now(), 3600, :second)
    Repo.update_all(from(x in Service, where: x.id == ^s.id), set: [next_check_at: later])

  ["empty"] ->
    Repo.delete_all(Service)

  ["reset"] ->
    Repo.delete_all(Service)
    :ok = UptimeMonitor.Demo.Seeder.run(target)
end
