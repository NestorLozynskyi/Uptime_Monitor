defmodule UptimeMonitor.Demo.Seeder do
  @moduledoc """
  Creates demo services pointing at the demo target service, with 30 days of
  generated check history and the incidents derived from it (using the same
  `IncidentTracker` rules as live checks), so statistics and charts have data
  for 24 h / 7 d / 30 d right away.

  Seeding is skipped when any service already exists.
  """
  import Ecto.Query
  require Logger

  alias UptimeMonitor.{Monitoring, Repo}
  alias UptimeMonitor.Monitoring.{Check, Incident, IncidentTracker, Service, Stats}

  @minute 60
  @hour 3_600
  @day 86_400

  @doc "Seeds demo data unless services exist. `base_url` is the demo target URL."
  def run(base_url, now \\ DateTime.utc_now()) do
    if Repo.exists?(Service) do
      Logger.info("Demo seed skipped: services already exist")
      :skipped
    else
      :rand.seed(:exsss, {2026, 11, 5})
      base_url = String.trim_trailing(base_url, "/")
      now = DateTime.truncate(now, :second)

      for profile <- profiles() do
        seed_service(profile, base_url, now)
      end

      Stats.rebuild_rollups()
      :ok
    end
  end

  defp profiles do
    [
      %{
        name: "Marketing Website",
        path: "/ok",
        interval: 1,
        public: true,
        rt: {80, 250},
        outages: [{12 * @day, 25 * @minute, :http_502}, {26 * @day, 8 * @minute, :conn}],
        slow_ratio: 0.01
      },
      %{
        name: "Public API",
        path: "/delay/3500",
        interval: 1,
        public: true,
        rt: {300, 900},
        degraded_since: 2 * @day,
        outages: [{5 * @day, 40 * @minute, :timeout}, {17 * @day, 12 * @minute, :http_500}],
        slow_ratio: 0.03
      },
      %{
        name: "Billing Service",
        path: "/status/503",
        interval: 5,
        public: false,
        rt: {120, 400},
        outages: [{3 * @hour, 3 * @hour, :http_503}, {20 * @day, 1 * @hour, :http_503}],
        slow_ratio: 0.02
      },
      %{
        name: "Search Cluster",
        path: "/cycle/20/5",
        interval: 1,
        public: true,
        rt: {150, 500},
        outages:
          for(d <- 0..6, do: {d * @day + 7 * @hour, 8 * @minute, :http_503}) ++
            [{9 * @day, 2 * @hour, :timeout}, {23 * @day, 35 * @minute, :http_503}],
        slow_ratio: 0.05
      },
      %{
        name: "Auth Service",
        path: "/flaky/10",
        interval: 1,
        public: false,
        rt: {60, 200},
        outages: [{8 * @day, 15 * @minute, :conn}],
        random_failure: 0.05,
        slow_ratio: 0.01
      },
      %{
        name: "Legacy Portal",
        path: "/redirect/2",
        interval: 15,
        public: false,
        rt: {200, 700},
        outages: [{14 * @day, 2 * @hour, :http_502}],
        slow_ratio: 0.05
      },
      %{
        name: "Reports Worker",
        path: "/delay/12000",
        interval: 5,
        public: false,
        rt: {900, 2_500},
        outages: [{40 * @minute, 40 * @minute, :timeout}, {4 * @day, 3 * @hour, :timeout}],
        slow_ratio: 0.15
      },
      %{
        name: "Documentation",
        path: "/slow-random/100/600",
        interval: 5,
        public: true,
        rt: {100, 600},
        outages: [],
        slow_ratio: 0.0
      }
    ]
  end

  defp seed_service(profile, base_url, now) do
    {:ok, service} =
      Monitoring.create_service(%{
        name: profile.name,
        url: base_url <> profile.path,
        interval_minutes: profile.interval,
        public: profile.public
      })
      |> case do
        {:ok, service} ->
          {:ok, service}

        {:error, changeset} ->
          raise "Could not create demo service #{profile.name}: " <>
                  inspect(Ecto.Changeset.traverse_errors(changeset, &elem(&1, 0))) <>
                  " (is the demo target host in SSRF_ALLOWLIST?)"
      end

    step = profile.interval * @minute
    first = DateTime.add(now, -30 * @day + step, :second)
    count = div(30 * @day, step) - 1

    rows =
      for n <- 0..(count - 1) do
        at = DateTime.add(first, n * step, :second)
        ago = DateTime.diff(now, at, :second)
        sample(profile, ago) |> Map.merge(%{service_id: service.id, checked_at: to_usec(at)})
      end

    rows
    |> Enum.chunk_every(5_000)
    |> Enum.each(&Repo.insert_all(Check, Enum.map(&1, fn r -> Map.put(r, :manual, false) end)))

    {tracker, incidents} =
      Enum.reduce(rows, {%IncidentTracker{}, []}, fn row, {tracker, incidents} ->
        case IncidentTracker.step(tracker, row.result, row.checked_at, row.error) do
          {tracker, :none} ->
            {tracker, incidents}

          {tracker, {:open, started, reason}} ->
            {tracker, [%{started_at: started, ended_at: nil, reason: reason} | incidents]}

          {tracker, {:close, ended}} ->
            [open | rest] = incidents
            {tracker, [%{open | ended_at: ended} | rest]}
        end
      end)

    timestamp = DateTime.utc_now()

    Repo.insert_all(
      Incident,
      Enum.map(incidents, fn i ->
        Map.merge(i, %{service_id: service.id, inserted_at: timestamp, updated_at: timestamp})
      end)
    )

    last = List.last(rows)

    from(s in Service, where: s.id == ^service.id)
    |> Repo.update_all(
      set: [
        status: last.result,
        consecutive_failures: tracker.consecutive_failures,
        consecutive_successes: tracker.consecutive_successes,
        streak_started_at: tracker.streak_started_at,
        last_checked_at: last.checked_at,
        last_response_time_ms: last.response_time_ms,
        last_status_code: last.status_code,
        last_error: last.error,
        next_check_at: to_usec(now)
      ]
    )

    Logger.info(
      "Demo service #{profile.name}: #{length(rows)} checks, #{length(incidents)} incidents"
    )
  end

  defp sample(profile, ago) do
    outage =
      Enum.find(profile.outages, fn {start_ago, duration, _} ->
        ago <= start_ago and ago > start_ago - duration
      end)

    random_failure? = :rand.uniform() < Map.get(profile, :random_failure, 0.0)

    cond do
      outage -> failure(elem(outage, 2))
      random_failure? -> failure(:http_500)
      degraded?(profile, ago) -> success(:degraded, 3_100 + :rand.uniform(1_400))
      true -> success(:up, random_rt(profile.rt))
    end
  end

  defp degraded?(profile, ago) do
    ago <= Map.get(profile, :degraded_since, -1) or :rand.uniform() < profile.slow_ratio
  end

  defp random_rt({min, max}), do: min + :rand.uniform(max - min + 1) - 1

  defp success(result, rt),
    do: %{result: result, status_code: 200, response_time_ms: rt, error: nil}

  defp failure(:timeout),
    do: %{result: :down, status_code: nil, response_time_ms: nil, error: "Timed out after 10 s"}

  defp failure(:conn),
    do: %{result: :down, status_code: nil, response_time_ms: nil, error: "Connection refused"}

  defp failure(:http_500), do: http_failure(500)
  defp failure(:http_502), do: http_failure(502)
  defp failure(:http_503), do: http_failure(503)

  defp http_failure(code),
    do: %{
      result: :down,
      status_code: code,
      response_time_ms: 40 + :rand.uniform(200),
      error: "HTTP #{code}"
    }

  defp to_usec(%DateTime{microsecond: {us, _}} = dt), do: %{dt | microsecond: {us, 6}}
end
