defmodule UptimeMonitor.Monitoring.StatsTest do
  use UptimeMonitor.DataCase, async: true

  alias UptimeMonitor.Monitoring
  alias UptimeMonitor.Monitoring.Stats

  @now ~U[2026-11-05 12:30:00.000000Z]

  defp ago(seconds), do: DateTime.add(@now, -seconds, :second)

  # Records checks through the regular path so rollups are maintained.
  defp record(service, result, at, attrs \\ []) do
    {:ok, _} = Monitoring.record_check(service.id, result(result, at, attrs))
  end

  setup do
    service = service_fixture()

    # Last 24 h: 3 up (100, 200, 300 ms), 1 degraded (3 600 ms), 1 down.
    record(service, :up, ago(60), response_time_ms: 100)
    record(service, :up, ago(3_600), response_time_ms: 200)
    record(service, :up, ago(5 * 3_600), response_time_ms: 300)
    record(service, :degraded, ago(10 * 3_600), response_time_ms: 3_600)
    record(service, :down, ago(20 * 3_600), response_time_ms: 9_999)

    # 2–6 days ago: 4 up (1 000 ms), 1 down.
    for d <- 2..5, do: record(service, :up, ago(d * 86_400), response_time_ms: 1_000)

    record(service, :down, ago(6 * 86_400),
      status_code: nil,
      response_time_ms: nil,
      error: "Timed out after 10 s"
    )

    # 8–29 days ago: 9 up (500 ms), 1 down.
    for d <- 8..16, do: record(service, :up, ago(d * 86_400), response_time_ms: 500)
    record(service, :down, ago(29 * 86_400))

    # Older than 30 days: ignored by every period.
    record(service, :down, ago(31 * 86_400))

    # Incidents: one in the last day (open), one 3 days ago, one 20 days ago,
    # one that ended 40 days ago (outside every window).
    incident_fixture(service, ago(2 * 3_600))
    incident_fixture(service, ago(3 * 86_400), ago(3 * 86_400 - 600))
    incident_fixture(service, ago(20 * 86_400), ago(20 * 86_400 - 600))
    incident_fixture(service, ago(41 * 86_400), ago(40 * 86_400))

    %{service: service}
  end

  test "24 h statistics from raw checks", %{service: service} do
    stats = Stats.service_stats(service.id, :day, @now)
    assert stats.total_checks == 5
    assert stats.up_checks == 3 and stats.degraded_checks == 1 and stats.down_checks == 1
    assert stats.uptime_pct == 80.0
    # Mean of successful checks only: (100 + 200 + 300 + 3600) / 4.
    assert stats.avg_response_ms == 1_050
    assert stats.incident_count == 1
    # 48 slots of 30 minutes; the last one contains `now`.
    assert length(stats.buckets) == 48
    assert Enum.all?(stats.buckets, &(&1.start.minute in [0, 30] and &1.start.second == 0))
    last = List.last(stats.buckets)
    assert DateTime.compare(last.start, @now) != :gt
    assert DateTime.diff(@now, last.start) < 1_800
    assert Enum.sum(Enum.map(stats.buckets, & &1.total)) == 5
    # A failed check alone (no incident) does not mark the slot as down.
    failed = Enum.find(stats.buckets, &(&1.down == 1))
    assert failed.status == :up and failed.down_seconds == 0
    # Slots with an average successful response above 3 s are degraded.
    assert Enum.find(stats.buckets, &(&1.status == :degraded)).avg_response_ms == 3_600
    # The incident opened 2 h ago marks the slots since then as down.
    down = Enum.filter(stats.buckets, &(&1.status == :down))
    assert length(down) in 4..5
    assert Enum.sum(Enum.map(down, & &1.down_seconds)) == 2 * 3_600
    assert Enum.count(stats.buckets, &(&1.status == :no_data)) > 30
  end

  test "slots are aligned to the viewer's time zone", %{service: service} do
    # UTC+2: daily slots start at local midnight (22:00 UTC).
    stats = Stats.service_stats(service.id, :month, @now, tz_offset: 7_200)
    assert length(stats.buckets) == 30
    assert Enum.all?(stats.buckets, &(&1.start.hour == 22 and &1.start.minute == 0))
    assert List.last(stats.buckets).start == ~U[2026-11-04 22:00:00Z]

    # UTC-5, 4-hour slots: local 08:00 = 13:00 UTC.
    stats = Stats.service_stats(service.id, :week, @now, tz_offset: -18_000)
    assert length(stats.buckets) == 42
    assert List.last(stats.buckets).start == ~U[2026-11-05 09:00:00Z]
  end

  test "7 d statistics from hourly rollups", %{service: service} do
    stats = Stats.service_stats(service.id, :week, @now)
    assert stats.total_checks == 10
    assert stats.down_checks == 2
    assert stats.uptime_pct == 80.0
    # (100 + 200 + 300 + 3600 + 4 * 1000) / 8
    assert stats.avg_response_ms == 1_025
    assert stats.incident_count == 2
    # 42 slots of 4 hours.
    assert length(stats.buckets) == 42
    assert Enum.all?(stats.buckets, &(rem(&1.start.hour, 4) == 0))
    assert Enum.sum(Enum.map(stats.buckets, & &1.total)) == 10
    assert Enum.count(stats.buckets, &(&1.status == :down)) >= 2
  end

  test "30 d statistics from hourly rollups", %{service: service} do
    stats = Stats.service_stats(service.id, :month, @now)
    assert stats.total_checks == 20
    assert stats.down_checks == 3
    assert stats.uptime_pct == 85.0
    # (4200 + 4000 + 9 * 500) / 17
    assert stats.avg_response_ms == round(12_700 / 17)
    assert stats.incident_count == 3
    # 30 daily slots; the 2nd–5th days' checks (1 000 ms) are in their own slots.
    assert length(stats.buckets) == 30
    assert List.last(stats.buckets).start == ~U[2026-11-05 00:00:00Z]
    assert Enum.sum(Enum.map(stats.buckets, & &1.total)) == 20
  end

  test "periods without data return nil metrics" do
    empty = service_fixture()
    stats = Stats.service_stats(empty.id, :day, @now)
    assert stats.total_checks == 0
    assert stats.uptime_pct == nil
    assert stats.avg_response_ms == nil
    assert Enum.all?(stats.buckets, &(&1.status == :no_data))
  end

  test "summaries for several services in one call", %{service: service} do
    other = service_fixture()
    record(other, :up, ago(120), response_time_ms: 50)

    for period <- Stats.periods() do
      summaries = Stats.summaries([service.id, other.id], period, @now)

      assert summaries[other.id] == %{
               uptime_pct: 100.0,
               avg_response_ms: 50,
               total_checks: 1,
               incident_count: 0
             }

      assert summaries[service.id].uptime_pct ==
               Stats.service_stats(service.id, period, @now).uptime_pct
    end
  end

  test "rebuild_rollups/1 reproduces incrementally maintained rollups", %{service: service} do
    before = Stats.service_stats(service.id, :month, @now)
    {:ok, _} = Stats.rebuild_rollups(service.id)
    assert Stats.service_stats(service.id, :month, @now) == before
  end
end
