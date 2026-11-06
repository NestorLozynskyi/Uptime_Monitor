defmodule UptimeMonitor.Demo.SeederTest do
  use UptimeMonitor.DataCase, async: true

  alias UptimeMonitor.{Monitoring, StatusPage}
  alias UptimeMonitor.Demo.Seeder
  alias UptimeMonitor.Monitoring.Stats

  @tag timeout: 120_000
  test "seeds services with 30 days of history in different states" do
    assert :ok = Seeder.run("http://demo.target.test:4100")
    services = Monitoring.list_services()
    assert length(services) == 8

    statuses = services |> Enum.map(& &1.status) |> MapSet.new()
    assert MapSet.subset?(MapSet.new([:up, :degraded, :down]), statuses)
    assert Enum.any?(services, & &1.public) and Enum.any?(services, &(not &1.public))

    for s <- services, period <- Stats.periods() do
      stats = Stats.service_stats(s.id, period)
      assert stats.total_checks > 0, "#{s.name} has no #{period} data"
    end

    assert Monitoring.list_incidents() != []
    assert Enum.any?(services, &Monitoring.get_open_incident(&1.id))
    assert StatusPage.overview(:month).services != []

    # Idempotent: a second run does nothing.
    assert :skipped = Seeder.run("http://demo.target.test:4100")
  end
end
