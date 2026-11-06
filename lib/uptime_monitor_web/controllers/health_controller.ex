defmodule UptimeMonitorWeb.HealthController do
  use UptimeMonitorWeb, :controller

  @doc "Liveness/readiness endpoint: checks the database connection."
  def show(conn, _params) do
    case Ecto.Adapters.SQL.query(UptimeMonitor.Repo, "SELECT 1", []) do
      {:ok, _} -> json(conn, %{status: "ok"})
      {:error, _} -> conn |> put_status(503) |> json(%{status: "error"})
    end
  end
end
