defmodule UptimeMonitorWeb.TimeZone do
  @moduledoc """
  The viewer's UTC offset (seconds east of UTC), used to show times in the
  browser's time zone. The root layout stores it in the `um_tz` cookie (read
  by the plug for the first, static render) and the LiveView socket sends it
  as the `tz_offset` connect param.
  """
  import Plug.Conn

  @max 14 * 3_600

  @doc "Plug: copies the cookie value into the session."
  def put_tz_offset(conn, _opts) do
    case parse(conn.cookies["um_tz"]) do
      nil -> conn
      offset -> put_session(conn, :tz_offset, offset)
    end
  end

  @doc "LiveView hook: assigns `:tz_offset`."
  def on_mount(:default, _params, session, socket) do
    offset =
      if Phoenix.LiveView.connected?(socket),
        do: parse(Phoenix.LiveView.get_connect_params(socket)["tz_offset"]),
        else: nil

    {:cont, Phoenix.Component.assign(socket, :tz_offset, offset || session["tz_offset"] || 0)}
  end

  def parse(value) when is_integer(value) and abs(value) <= @max, do: value

  def parse(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> parse(int)
      _ -> nil
    end
  end

  def parse(_), do: nil
end
