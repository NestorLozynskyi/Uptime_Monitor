defmodule UptimeMonitorWeb.AdminAuth do
  @moduledoc "Session-based authentication of the administrator (plugs and LiveView hooks)."
  use UptimeMonitorWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias UptimeMonitor.Accounts

  @session_key :admin_token

  @doc "Logs the admin in: renews the session (fixation protection) and stores a token."
  def log_in_admin(conn, admin) do
    token = Accounts.generate_admin_session_token(admin)
    return_to = get_session(conn, :admin_return_to)

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_session(@session_key, token)
    |> put_session(:live_socket_id, live_socket_id(token))
    |> redirect(to: return_to || ~p"/admin")
  end

  @doc "Logs out: deletes the token and disconnects LiveView sockets of this session."
  def log_out_admin(conn) do
    token = get_session(conn, @session_key)
    token && Accounts.delete_admin_session_token(token)

    if token do
      UptimeMonitorWeb.Endpoint.broadcast(live_socket_id(token), "disconnect", %{})
    end

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> redirect(to: ~p"/login")
  end

  def fetch_current_admin(conn, _opts) do
    token = get_session(conn, @session_key)
    assign(conn, :current_admin, token && Accounts.get_admin_by_session_token(token))
  end

  def require_authenticated_admin(conn, _opts) do
    if conn.assigns[:current_admin] do
      conn
    else
      conn
      |> maybe_store_return_to()
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: ~p"/login")
      |> halt()
    end
  end

  def redirect_if_admin_is_authenticated(conn, _opts) do
    if conn.assigns[:current_admin] do
      conn |> redirect(to: ~p"/admin") |> halt()
    else
      conn
    end
  end

  defp maybe_store_return_to(%{method: "GET"} = conn),
    do: put_session(conn, :admin_return_to, current_path(conn))

  defp maybe_store_return_to(conn), do: conn

  defp live_socket_id(token), do: "admin_sessions:#{Base.url_encode64(token)}"

  ## LiveView hooks: `live_session :admin, on_mount: [{AdminAuth, :require_authenticated}]`

  def on_mount(:mount_current_admin, _params, session, socket) do
    {:cont, mount_current_admin(socket, session)}
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_admin(socket, session)

    if socket.assigns.current_admin do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/login")

      {:halt, socket}
    end
  end

  defp mount_current_admin(socket, session) do
    Phoenix.Component.assign_new(socket, :current_admin, fn ->
      if token = session["admin_token"], do: Accounts.get_admin_by_session_token(token)
    end)
  end
end
