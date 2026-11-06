defmodule UptimeMonitorWeb.StatusLiveTest do
  use UptimeMonitorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  defp count(html, selector) when is_binary(html),
    do: html |> LazyHTML.from_document() |> LazyHTML.query(selector) |> Enum.count()

  alias UptimeMonitor.Monitoring

  defp set_status(service, status) do
    {:ok, _} = Monitoring.record_check(service.id, result(status))
    service
  end

  defp overall(conn) do
    {:ok, view, _html} = live(conn, ~p"/status")
    view
  end

  test "is public and shows only public services, without URLs or admin actions", %{conn: conn} do
    pub = service_fixture(name: "Website", public: true) |> set_status(:up)
    priv = service_fixture(name: "Internal DB", public: false) |> set_status(:down)

    {:ok, view, html} = live(conn, ~p"/status")
    assert has_element?(view, "#public-service-#{pub.id}", "Website")
    assert has_element?(view, "#public-service-#{pub.id}", "100.00% uptime")
    assert count(html, "#public-service-#{pub.id} .bar") == 30
    refute html =~ "Internal DB"
    refute html =~ priv.url
    refute html =~ pub.url
    refute html =~ "Check now"
    refute html =~ "Sign out"

    assert has_element?(
             view,
             ~s(#overall-status[data-overall="operational"]),
             "All systems operational"
           )
  end

  test "overall status rules", %{conn: conn} do
    a = service_fixture(public: true) |> set_status(:up)
    b = service_fixture(public: true) |> set_status(:degraded)
    _c = service_fixture(public: true)

    view = overall(conn)
    assert has_element?(view, "#overall-status", "Degraded performance")
    assert has_element?(view, "#overall-status", "1 service is responding slowly")
    # A service without checks shows "No data" and does not affect the overall status.
    assert has_element?(view, "#public-services .st-pending", "No data")

    set_status(a, :down)
    view = overall(conn)
    assert has_element?(view, "#overall-status", "Partial outage")
    assert has_element?(view, "#overall-status", "1 service is down and 1 is slow to respond.")

    set_status(b, :down)
    view = overall(conn)
    assert has_element?(view, "#overall-status", "Major outage")
  end

  test "empty state", %{conn: conn} do
    service_fixture(public: false)
    view = overall(conn)
    assert has_element?(view, "#status-empty", "No services to show yet")
    refute has_element?(view, "#overall-status")
  end

  test "updates live from the public topic only", %{conn: conn} do
    pub = service_fixture(name: "Website", public: true) |> set_status(:up)
    priv = service_fixture(name: "Hidden", public: false)

    {:ok, view, _html} = live(conn, ~p"/status")
    set_status(pub, :down)
    assert has_element?(view, "#public-service-#{pub.id} .st-down", "Down")
    assert has_element?(view, "#overall-status", "Major outage")

    {:ok, _} = Monitoring.update_service(priv, %{public: true})
    assert has_element?(view, "#public-service-#{priv.id}", "Hidden")

    {:ok, _} = Monitoring.update_service(Monitoring.get_service!(priv.id), %{public: false})
    refute has_element?(view, "#public-service-#{priv.id}")
  end
end
