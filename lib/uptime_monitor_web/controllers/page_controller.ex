defmodule UptimeMonitorWeb.PageController do
  use UptimeMonitorWeb, :controller

  @doc "The site root shows the public status page."
  def home(conn, _params), do: redirect(conn, to: ~p"/status")
end
