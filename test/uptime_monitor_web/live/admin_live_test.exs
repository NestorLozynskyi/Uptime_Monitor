defmodule UptimeMonitorWeb.AdminLiveTest do
  use UptimeMonitorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  defp count(html, selector) when is_binary(html),
    do: html |> LazyHTML.from_document() |> LazyHTML.query(selector) |> Enum.count()

  alias UptimeMonitor.{Monitoring, Repo, TargetServer}
  alias UptimeMonitor.Monitoring.{Service, Stats}

  setup %{conn: conn} do
    %{conn: log_in_admin(conn, admin_fixture())}
  end

  defp down!(service, n \\ 3) do
    for _ <- 1..n, do: {:ok, _} = Monitoring.record_check(service.id, result(:down))
  end

  describe "dashboard" do
    test "empty state without services", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, "#empty-state", "No services yet")
      refute has_element?(view, "#summary")
    end

    test "summary, active incidents and services table", %{conn: conn} do
      up = service_fixture(name: "Website", public: true)
      down = service_fixture(name: "Billing API")
      new_svc = service_fixture(name: "Staging")
      {:ok, _} = Monitoring.record_check(up.id, result(:up))
      down!(down)

      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, ~s([data-tile="up"] .tile-count), "1")
      assert has_element?(view, ~s([data-tile="down"] .tile-count), "1")
      assert has_element?(view, ~s([data-tile="degraded"].is-zero))
      assert has_element?(view, ~s([data-tile="pending"] .tile-count), "1")
      assert has_element?(view, "#active-incidents .inc-item", "Billing API")
      assert has_element?(view, "#active-incidents", "HTTP 503 Service Unavailable")
      assert has_element?(view, "#service-#{up.id} .st-up", "Up")
      assert has_element?(view, "#service-#{up.id}", "Public")
      assert has_element?(view, "#service-#{down.id} .c-down", "HTTP 503")
      assert has_element?(view, "#service-#{down.id}", "Private")
      assert has_element?(view, "#service-#{new_svc.id}", "Not checked yet")
      assert has_element?(view, "#service-#{new_svc.id}", "Waiting")
    end

    test "no active incidents state", %{conn: conn} do
      s = service_fixture()
      {:ok, _} = Monitoring.record_check(s.id, result(:up))
      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, "#active-incidents", "No active incidents")
    end

    test "updates in real time from PubSub events", %{conn: conn} do
      s = service_fixture(name: "Website")
      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, "#service-#{s.id}", "Not checked yet")

      down!(s)
      assert has_element?(view, "#service-#{s.id} .st-down", "Down")
      assert has_element?(view, "#active-incidents .inc-item", "Website")

      {:ok, _} =
        Monitoring.create_service(%{name: "Added elsewhere", url: TargetServer.url("/ok")})

      assert render(view) =~ "Added elsewhere"
    end

    test "check now runs a manual check and shows the checking state", %{conn: conn} do
      s = service_fixture(name: "Website", url: TargetServer.url("/delay/150"))
      {:ok, view, _html} = live(conn, ~p"/admin")

      view |> element("#service-#{s.id} button", "Check now") |> render_click()
      assert has_element?(view, "#service-#{s.id}.is-checking")
      assert has_element?(view, "#service-#{s.id} .st-checking", "Checking")

      render_async(view, 5_000)
      refute has_element?(view, "#service-#{s.id}.is-checking")
      assert has_element?(view, "#service-#{s.id} .st-up", "Up")
      assert [%{manual: true}] = Monitoring.list_recent_checks(s.id)
    end
  end

  describe "service details" do
    test "header, incident banner, statistics, incidents and recent checks", %{conn: conn} do
      s = service_fixture(name: "Billing API", public: true)
      {:ok, _} = Monitoring.record_check(s.id, result(:up), manual: true)
      down!(s)

      {:ok, view, html} = live(conn, ~p"/admin/services/#{s}")
      assert html =~ "Billing API"
      assert has_element?(view, "#service-status", "Down")
      assert has_element?(view, "#svc-head", "Shown on status page")
      assert has_element?(view, "#incident-banner", "Incident ongoing for")
      assert has_element?(view, "#incident-banner", "HTTP 503 Service Unavailable since")
      assert has_element?(view, ~s([data-period="24h"][aria-checked="true"]))
      assert has_element?(view, ~s([data-metric="uptime"]), "25.00%")
      assert has_element?(view, ~s([data-metric="avg"]), "100 ms")
      assert has_element?(view, ~s([data-metric="incidents"]), "1")
      assert has_element?(view, "#response-chart[data-points]")
      assert has_element?(view, "#availability .bar", "")
      assert count(render(view), "#availability .bar") == 48
      assert has_element?(view, "#incidents", "Ongoing")
      assert has_element?(view, "#recent-checks", "Manual")
      assert has_element?(view, "#recent-checks", "Scheduled")
    end

    test "period switch changes data and the selected period", %{conn: conn} do
      s = service_fixture()
      {:ok, _} = Monitoring.record_check(s.id, result(:up))
      {:ok, view, _html} = live(conn, ~p"/admin/services/#{s}")

      view |> element(~s([data-period="7d"])) |> render_click()
      assert_patch(view, ~p"/admin/services/#{s}?period=7d")
      assert has_element?(view, ~s([data-period="7d"][aria-checked="true"]))
      assert has_element?(view, ~s([data-period="24h"][aria-checked="false"]))
      assert has_element?(view, "#response-chart[data-period=\"7d\"]")
      assert has_element?(view, "#chart-title", "last 7 days")
      assert count(render(view), "#availability .bar") == 42

      view |> element(~s([data-period="30d"])) |> render_click()
      assert has_element?(view, ~s([data-period="30d"][aria-checked="true"]))
      assert count(render(view), "#availability .bar") == 30
      assert has_element?(view, "#availability", "30 days ago")
    end

    test "not checked yet, then check now", %{conn: conn} do
      s = service_fixture(name: "Staging", url: TargetServer.url("/delay/150"))
      {:ok, view, _html} = live(conn, ~p"/admin/services/#{s}")
      assert has_element?(view, "#service-status", "Not checked yet")
      assert has_element?(view, "#svc-head", "First check within")
      assert has_element?(view, "#metrics", "After first check")
      assert has_element?(view, ".chart-empty", "No checks yet")
      refute has_element?(view, "#period")
      assert count(render(view), "#availability .bar.b-n") == 30

      view |> element("#check-now") |> render_click()
      assert has_element?(view, "#svc-head", "Checking now…")
      assert has_element?(view, "#checking-row", "Checking…")

      render_async(view, 5_000)
      refute has_element?(view, "#checking-row")
      assert has_element?(view, "#service-status", "Up")
      assert has_element?(view, "#recent-checks", "Manual")
      assert has_element?(view, "#response-chart")
    end

    test "updates in real time", %{conn: conn} do
      s = service_fixture()
      {:ok, view, _html} = live(conn, ~p"/admin/services/#{s}")
      down!(s)
      assert has_element?(view, "#service-status", "Down")
      assert has_element?(view, "#incident-banner")
    end

    test "delete asks for confirmation", %{conn: conn} do
      s = service_fixture(name: "Old service")
      {:ok, view, _html} = live(conn, ~p"/admin/services/#{s}")

      view |> element("#delete-service") |> render_click()
      assert has_element?(view, "#delete-dialog", "Delete “Old service”?")
      view |> element("#delete-dialog button", "Cancel") |> render_click()
      refute has_element?(view, "#delete-dialog")
      assert Repo.get(Service, s.id)

      view |> element("#delete-service") |> render_click()
      view |> element("#confirm-delete") |> render_click()
      assert_redirect(view, ~p"/admin")
      refute Repo.get(Service, s.id)
    end

    test "unknown service redirects to the dashboard", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/admin"}}} = live(conn, ~p"/admin/services/0")
    end
  end

  describe "service form" do
    test "adds a service", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/services/new")
      assert has_element?(view, "#svc-interval-5[checked]")

      view
      |> form("#service-form",
        service: %{
          name: "Website",
          url: TargetServer.url("/ok"),
          interval_minutes: "15",
          public: "true"
        }
      )
      |> render_submit()

      assert_redirect(view, ~p"/admin")
      assert %{interval_minutes: 15, public: true} = Repo.get_by!(Service, name: "Website")
    end

    test "shows field errors and the summary, including the SSRF rejection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/services/new")

      view
      |> form("#service-form", service: %{name: "", url: "http://192.168.1.10/admin"})
      |> render_submit()

      assert has_element?(view, "#error-summary", "Fix 2 problems to continue")
      assert has_element?(view, "#svc-name-error", "Enter a name for this service.")

      assert has_element?(
               view,
               "#svc-url-error",
               "This address is not allowed. Private, local and internal network addresses can’t be monitored."
             )

      assert has_element?(view, ~s(#svc-url[aria-invalid="true"]))
      refute Repo.exists?(Service)
    end

    test "maps other URL problems to readable messages", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/services/new")

      for {url, message} <- [
            {"", "Enter the address to monitor."},
            {"example.com", "Enter a full address that starts with http:// or https://"},
            {"ftp://example.com", "Only http:// and https:// addresses can be monitored."},
            {"http://169.254.169.254/", "This address is not allowed."},
            {"http://unknown-host.invalid/", "We couldn’t find this address."}
          ] do
        view |> form("#service-form", service: %{name: "x", url: url}) |> render_submit()
        assert has_element?(view, "#svc-url-error", message)
      end
    end

    test "edits a service", %{conn: conn} do
      s = service_fixture(name: "Old name", interval_minutes: 1, public: true)
      {:ok, view, html} = live(conn, ~p"/admin/services/#{s}/edit")
      assert html =~ "Edit service"
      assert html =~ "Save changes"
      assert has_element?(view, "#svc-interval-1[checked]")
      assert has_element?(view, "#svc-public[checked]")

      view
      |> form("#service-form",
        service: %{name: "New name", interval_minutes: "60", public: "false"}
      )
      |> render_submit()

      assert_redirect(view, ~p"/admin/services/#{s}")
      assert %{name: "New name", interval_minutes: 60, public: false} = Repo.get!(Service, s.id)
    end
  end

  test "admin pages need a session" do
    for path <- ["/admin", "/admin/services/new", "/admin/services/1", "/admin/services/1/edit"] do
      assert {:error, {:redirect, %{to: "/login"}}} = live(build_conn(), path)
    end
  end

  test "stats helper keeps the design slot counts" do
    assert Stats.periods() == [:day, :week, :month]
  end
end
