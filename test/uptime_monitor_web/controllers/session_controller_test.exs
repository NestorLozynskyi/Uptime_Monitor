defmodule UptimeMonitorWeb.SessionControllerTest do
  use UptimeMonitorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup do
    %{admin: admin_fixture(email: "admin@example.com", password: "correct-horse-battery")}
  end

  test "login page renders", %{conn: conn} do
    html = html_response(get(conn, ~p"/login"), 200)
    assert html =~ "Sign in"
    assert html =~ "View public status page"
  end

  test "logs in with valid credentials", %{conn: conn} do
    conn =
      post(conn, ~p"/login", %{
        "admin" => %{"email" => "admin@example.com", "password" => "correct-horse-battery"}
      })

    assert redirected_to(conn) == ~p"/admin"
    assert get_session(conn, :admin_token)

    conn = get(recycle(conn), ~p"/admin")
    assert html_response(conn, 200) =~ "Dashboard"
  end

  test "rejects invalid credentials", %{conn: conn} do
    conn =
      post(conn, ~p"/login", %{
        "admin" => %{"email" => "admin@example.com", "password" => "nope-nope"}
      })

    html = html_response(conn, 401)
    assert html =~ "Incorrect email or password"
    assert html =~ "Check both fields and try again."
    refute get_session(conn, :admin_token)
  end

  test "validates empty and malformed fields before checking credentials", %{conn: conn} do
    conn = post(conn, ~p"/login", %{"admin" => %{"email" => "", "password" => ""}})
    html = html_response(conn, 422)
    assert html =~ "Enter your email."
    assert html =~ "Enter your password."
    refute html =~ "Incorrect email or password"

    conn = post(build_conn(), ~p"/login", %{"admin" => %{"email" => "nope", "password" => "x"}})
    assert html_response(conn, 422) =~ "Enter a valid email address."
  end

  test "admin pages require authentication", %{conn: conn} do
    conn = get(conn, ~p"/admin")
    assert redirected_to(conn) == ~p"/login"
    assert {:error, {:redirect, %{to: "/login"}}} = live(build_conn(), ~p"/admin")
  end

  test "authenticated admin can open the LiveView and is redirected away from login", %{
    conn: conn,
    admin: admin
  } do
    conn = log_in_admin(conn, admin)
    {:ok, _view, html} = live(conn, ~p"/admin")
    assert html =~ "Dashboard"
    assert html =~ "Sign out"
    assert redirected_to(get(conn, ~p"/login")) == ~p"/admin"
  end

  test "logout deletes the session token", %{conn: conn, admin: admin} do
    conn = log_in_admin(conn, admin)
    token = get_session(conn, :admin_token)
    conn = delete(conn, ~p"/logout")
    assert redirected_to(conn) == ~p"/login"
    refute UptimeMonitor.Accounts.get_admin_by_session_token(token)
    assert redirected_to(get(recycle(conn), ~p"/admin")) == ~p"/login"
  end

  test "public pages and health check need no login", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/")) == ~p"/status"
    assert html_response(get(build_conn(), ~p"/status"), 200) =~ "Service status"
    assert json_response(get(build_conn(), ~p"/health"), 200) == %{"status" => "ok"}
  end

  test "there is no registration route", %{conn: conn} do
    assert get(conn, "/register").status == 404
  end
end
