defmodule UptimeMonitor.Monitoring.RetentionTest do
  use UptimeMonitor.DataCase, async: true

  alias UptimeMonitor.Monitoring
  alias UptimeMonitor.Monitoring.{Check, CheckRollup, Incident, Retention}
  alias UptimeMonitor.Monitoring.Workers.Cleanup

  test "deletes checks older than 30 days and incidents resolved more than 90 days ago" do
    now = DateTime.utc_now()
    day = 86_400
    service = service_fixture()

    for days <- [1, 29, 31, 45] do
      {:ok, _} =
        Monitoring.record_check(service.id, result(:up, DateTime.add(now, -days * day, :second)))
    end

    kept_recent =
      incident_fixture(
        service,
        DateTime.add(now, -100 * day, :second),
        DateTime.add(now, -89 * day, :second)
      )

    _expired =
      incident_fixture(
        service,
        DateTime.add(now, -100 * day, :second),
        DateTime.add(now, -91 * day, :second)
      )

    open_old = incident_fixture(service, DateTime.add(now, -120 * day, :second))

    assert %{checks: 2, incidents: 1, rollups: 2} = Retention.cleanup(now)

    ages =
      Repo.all(from c in Check, select: c.checked_at)
      |> Enum.map(&div(DateTime.diff(now, &1), day))
      |> Enum.sort()

    assert ages == [1, 29]
    assert Repo.aggregate(CheckRollup, :count) == 2

    assert Enum.sort(Repo.all(from i in Incident, select: i.id)) ==
             Enum.sort([kept_recent.id, open_old.id])
  end

  test "the cleanup worker runs the retention" do
    service = service_fixture()
    old = DateTime.add(DateTime.utc_now(), -31 * 86_400, :second)
    check_fixture(service, :up, old)
    assert :ok = perform_job(Cleanup, %{})
    assert Repo.aggregate(Check, :count) == 0
  end

  test "cleanup is scheduled with Oban cron" do
    crontab =
      Application.fetch_env!(:uptime_monitor, Oban)[:plugins]
      |> Enum.find_value(fn
        {Oban.Plugins.Cron, opts} -> opts[:crontab]
        _ -> nil
      end)

    assert {"17 * * * *", Cleanup} in crontab
    assert {"* * * * *", UptimeMonitor.Monitoring.Workers.Scheduler} in crontab
  end
end
