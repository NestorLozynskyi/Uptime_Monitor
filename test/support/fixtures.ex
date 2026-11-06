defmodule UptimeMonitor.Fixtures do
  @moduledoc "Test data helpers."
  alias UptimeMonitor.{Accounts, Repo}
  alias UptimeMonitor.Monitoring.{Check, HttpCheck, Incident, Service}

  def admin_fixture(attrs \\ %{}) do
    {:ok, admin} =
      attrs
      |> Enum.into(%{email: "admin@example.com", password: "correct-horse-battery"})
      |> Accounts.upsert_admin()

    admin
  end

  @doc "Inserts a service directly (bypassing URL validation)."
  def service_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        name: "Service #{System.unique_integer([:positive])}",
        url: UptimeMonitor.TargetServer.url("/ok"),
        interval_minutes: 1,
        public: false,
        next_check_at: DateTime.utc_now()
      })

    struct!(Service, attrs) |> Repo.insert!()
  end

  def result(result, checked_at \\ DateTime.utc_now(), attrs \\ []) do
    defaults =
      case result do
        :up -> [status_code: 200, response_time_ms: 100]
        :degraded -> [status_code: 200, response_time_ms: 3500]
        :down -> [status_code: 503, response_time_ms: 50, error: "HTTP 503"]
      end

    struct!(
      HttpCheck.Result,
      Keyword.merge(defaults, attrs) ++ [result: result, checked_at: checked_at]
    )
  end

  def check_fixture(service, result, checked_at, attrs \\ []) do
    r = result(result, checked_at, attrs)

    Repo.insert!(%Check{
      service_id: service.id,
      checked_at: checked_at,
      result: r.result,
      status_code: r.status_code,
      response_time_ms: r.response_time_ms,
      error: r.error
    })
  end

  def incident_fixture(service, started_at, ended_at \\ nil) do
    Repo.insert!(%Incident{
      service_id: service.id,
      started_at: started_at,
      ended_at: ended_at,
      reason: "HTTP 503"
    })
  end
end
