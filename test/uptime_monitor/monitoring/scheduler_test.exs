defmodule UptimeMonitor.Monitoring.SchedulerTest do
  use UptimeMonitor.DataCase, async: true

  alias UptimeMonitor.Monitoring.{Check, Service}
  alias UptimeMonitor.Monitoring.Workers.{CheckService, Scheduler}
  alias UptimeMonitor.TargetServer

  test "enqueues due services once and advances next_check_at by the interval" do
    now = ~U[2026-11-05 12:00:03.000000Z]
    due = service_fixture(interval_minutes: 5, next_check_at: ~U[2026-11-05 11:59:00.000000Z])
    not_due = service_fixture(interval_minutes: 1, next_check_at: ~U[2026-11-05 12:01:00.000000Z])

    assert {:ok, [id]} = Scheduler.schedule_due(now)
    assert id == due.id
    assert_enqueued(worker: CheckService, args: %{service_id: due.id})
    refute_enqueued(worker: CheckService, args: %{service_id: not_due.id})

    assert Repo.get!(Service, due.id).next_check_at == ~U[2026-11-05 12:05:00.000000Z]

    # A second tick in the same minute does nothing.
    assert {:ok, []} = Scheduler.schedule_due(now)
    assert length(all_enqueued(worker: CheckService)) == 1
  end

  test "does not duplicate a check job that is still pending" do
    service = service_fixture(next_check_at: ~U[2026-11-05 12:00:00.000000Z])
    {:ok, [_]} = Scheduler.schedule_due(~U[2026-11-05 12:00:05.000000Z])
    # The job has not run yet; the service is due again on the next tick.
    {:ok, [_]} = Scheduler.schedule_due(~U[2026-11-05 12:01:05.000000Z])
    assert [_] = all_enqueued(worker: CheckService, args: %{service_id: service.id})
  end

  test "a 1-minute service is due on every tick" do
    service = service_fixture(interval_minutes: 1, next_check_at: ~U[2026-11-05 12:00:00.000000Z])

    for minute <- 0..3 do
      tick = DateTime.add(~U[2026-11-05 12:00:02.000000Z], minute, :minute)
      assert {:ok, [_]} = Scheduler.schedule_due(tick)
      Repo.delete_all(Oban.Job)
    end

    assert Repo.get!(Service, service.id).next_check_at == ~U[2026-11-05 12:04:00.000000Z]
  end

  test "services overdue after downtime are checked once, not in a burst" do
    service = service_fixture(interval_minutes: 1, next_check_at: ~U[2026-11-05 08:00:00.000000Z])
    assert {:ok, [_]} = Scheduler.schedule_due(~U[2026-11-05 12:00:01.000000Z])
    assert [_] = all_enqueued(worker: CheckService, args: %{service_id: service.id})
    assert Repo.get!(Service, service.id).next_check_at == ~U[2026-11-05 12:01:00.000000Z]
  end

  test "the scheduler worker runs from cron" do
    service_fixture(next_check_at: DateTime.add(DateTime.utc_now(), -60, :second))
    assert :ok = perform_job(Scheduler, %{})
    assert [_] = all_enqueued(worker: CheckService)
  end

  test "check jobs are unique per service while incomplete" do
    assert CheckService.__opts__()[:unique][:states] == :incomplete
    assert CheckService.__opts__()[:unique][:keys] == [:service_id]
  end

  test "the check worker performs and records a check" do
    service = service_fixture(url: TargetServer.url("/ok"))
    assert :ok = perform_job(CheckService, %{service_id: service.id})
    assert [%Check{result: :up, manual: false}] = Repo.all(Check)
    assert Repo.get!(Service, service.id).status == :up
  end

  test "the check worker cancels jobs for deleted services" do
    assert {:cancel, :service_deleted} = perform_job(CheckService, %{service_id: -1})
  end
end
