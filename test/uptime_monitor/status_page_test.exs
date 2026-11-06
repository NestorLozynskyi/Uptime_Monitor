defmodule UptimeMonitor.StatusPageTest do
  use UptimeMonitor.DataCase, async: true

  alias UptimeMonitor.{Monitoring, StatusPage}

  test "overview contains only public services, without URLs or raw errors" do
    public = service_fixture(public: true, name: "Website")
    private = service_fixture(public: false, name: "Internal DB")

    for s <- [public, private] do
      for _ <- 1..3,
          do:
            Monitoring.record_check(
              s.id,
              result(:down, DateTime.utc_now(), error: "Connection refused")
            )
    end

    overview = StatusPage.overview()
    assert [%{id: id, name: "Website", status: :down} = entry] = overview.services
    assert id == public.id
    refute Map.has_key?(entry, :url)
    assert entry.uptime_pct == 0.0
    # 30 daily slots, the last one (today) is down: an incident is open.
    assert length(entry.buckets) == 30
    assert List.last(entry.buckets).status == :down

    assert [%{service_id: ^id, service_name: "Website", reason: "Connection failure"}] =
             overview.incidents

    assert overview.overall_status == :major_outage

    assert {:ok, %{service: %{id: ^id}}} = StatusPage.service_stats(public.id, :week)
    assert {:error, :not_found} = StatusPage.service_stats(private.id, :week)
  end

  test "overall status" do
    s = fn status -> %{status: status} end
    assert StatusPage.overall_status([]) == :no_services
    assert StatusPage.overall_status([s.(:up), s.(:pending)]) == :operational
    assert StatusPage.overall_status([s.(:up), s.(:degraded)]) == :degraded
    assert StatusPage.overall_status([s.(:up), s.(:down)]) == :partial_outage
    assert StatusPage.overall_status([s.(:down)]) == :major_outage
    # Services without checks do not affect the overall status.
    assert StatusPage.overall_status([s.(:down), s.(:pending)]) == :major_outage
    assert StatusPage.overall_status([s.(:degraded), s.(:pending)]) == :degraded
    assert StatusPage.overall_status([s.(:pending), s.(:pending)]) == :no_data
  end
end
