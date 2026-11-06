defmodule UptimeMonitor.Monitoring.Stats do
  @moduledoc """
  Uptime statistics for the periods `:day` (24 h), `:week` (7 d) and `:month` (30 d).

  ## Metric definitions

    * **uptime_pct** — `(up + degraded) / total * 100` over all checks in the
      window (scheduled and Check Now). Degraded checks count as available.
      `nil` when there are no checks.
    * **avg_response_ms** — mean response time of *successful* checks (up and
      degraded). Failed checks are excluded: they either have no response time
      (timeouts, connection errors) or reflect an error response. `nil` when
      there are no successful checks.
    * **incident_count** — incidents that overlap the window (started before its
      end and still open or resolved after its start).
    * **buckets** — a fixed number of consecutive slots for the response-time
      chart and the availability history; the last slot contains `now`.
      Slots are aligned to the viewer's local time (option `:tz_offset`, in
      seconds east of UTC). Each slot has counts, `uptime_pct`,
      `avg_response_ms`, `down_seconds` (time covered by incidents) and a
      `status`:
        * `:down` — an incident (confirmed downtime) overlaps the slot;
        * `:degraded` — no incident, average successful response time above
          the degraded threshold (3 s);
        * `:up` — checks exist, no incident, normal response time;
        * `:no_data` — no checks and no incident.

  ## Data sources

    * `:day` — raw checks (at most 1 440 per service at 1-minute interval),
      48 slots of 30 minutes.
    * `:week` — hourly rollups (168 rows per service), 42 slots of 4 hours.
    * `:month` — hourly rollups (720 rows per service), 30 slots of 1 day.

  Metric windows: `:day` is exactly the last 24 h; rollup-based windows are
  aligned to whole hours (they start at the beginning of the hour that
  contains `now - period`).
  """
  import Ecto.Query

  alias UptimeMonitor.Repo
  alias UptimeMonitor.Monitoring.{Check, CheckRollup, Incident}

  @periods %{
    day: %{seconds: 86_400, bucket_seconds: 1_800, buckets: 48, source: :checks},
    week: %{seconds: 7 * 86_400, bucket_seconds: 4 * 3_600, buckets: 42, source: :rollups},
    month: %{seconds: 30 * 86_400, bucket_seconds: 86_400, buckets: 30, source: :rollups}
  }

  @origin ~U[2000-01-01 00:00:00Z]
  @naive_origin ~N[2000-01-01 00:00:00]

  def periods, do: [:day, :week, :month]

  @doc """
  Full statistics for one service and period. Options: `:tz_offset` — the
  viewer's UTC offset in seconds, used to align slots to local time.
  """
  def service_stats(service_id, period, now \\ DateTime.utc_now(), opts \\ []) do
    %{bucket_seconds: bucket_seconds} = config = Map.fetch!(@periods, period)
    from = window_start(config, now)
    offset = Keyword.get(opts, :tz_offset, 0)
    starts = slot_starts(config, now, offset)
    first = hd(starts)

    totals =
      case total_rows([service_id], config, from, now) do
        [row] -> row
        [] -> empty_row(nil)
      end

    by_bucket =
      [service_id]
      |> bucket_rows(config, first, now, offset)
      |> Map.new(fn row -> {row.bucket, row} end)

    incidents = incident_spans(service_id, first, now)

    buckets =
      for start <- starts do
        slot_end = Enum.min([DateTime.add(start, bucket_seconds, :second), now], DateTime)

        by_bucket
        |> Map.get(start, empty_row(start))
        |> finish_bucket(down_seconds(incidents, start, slot_end))
      end

    %{
      period: period,
      from: from,
      to: now,
      bucket_seconds: bucket_seconds,
      total_checks: totals.total,
      up_checks: totals.up,
      degraded_checks: totals.degraded,
      down_checks: totals.down,
      uptime_pct: uptime(totals),
      avg_response_ms: avg(totals),
      incident_count: incident_counts([service_id], from, now) |> Map.get(service_id, 0),
      buckets: buckets
    }
  end

  @doc """
  Summary (uptime, average response time, incident count, check count) for
  many services at once — one aggregate query per metric, for list pages.
  Returns `%{service_id => summary}` with an entry for every id.
  """
  def summaries(service_ids, period, now \\ DateTime.utc_now()) do
    config = Map.fetch!(@periods, period)
    from = window_start(config, now)

    totals =
      service_ids
      |> total_rows(config, from, now)
      |> Map.new(fn row -> {row.service_id, row} end)

    incidents = incident_counts(service_ids, from, now)

    Map.new(service_ids, fn id ->
      row = Map.get(totals, id, empty_row(nil))

      {id,
       %{
         uptime_pct: uptime(row),
         avg_response_ms: avg(row),
         total_checks: row.total,
         incident_count: Map.get(incidents, id, 0)
       }}
    end)
  end

  defp window_start(%{seconds: seconds, source: :checks}, now),
    do: DateTime.add(now, -seconds, :second)

  defp window_start(%{seconds: seconds, source: :rollups}, now) do
    now
    |> DateTime.add(-seconds, :second)
    |> DateTime.truncate(:second)
    |> Map.merge(%{minute: 0, second: 0})
  end

  # Slot starts (UTC) aligned to local time; the last slot contains `now`.
  defp slot_starts(%{bucket_seconds: size, buckets: n}, now, offset) do
    local = DateTime.diff(now, @origin, :second) + offset
    last = DateTime.add(@origin, local - Integer.mod(local, size) - offset, :second)
    for k <- (n - 1)..0//-1, do: DateTime.add(last, -k * size, :second)
  end

  defp bin_origin(offset), do: NaiveDateTime.add(@naive_origin, -offset, :second)

  # Per-bucket aggregates.
  defp bucket_rows(ids, %{source: :checks, bucket_seconds: s}, from, now, offset) do
    interval = %Postgrex.Interval{secs: s}
    origin = bin_origin(offset)

    from(c in Check,
      where: c.service_id in ^ids and c.checked_at >= ^from and c.checked_at <= ^now,
      group_by: fragment("1"),
      select: %{
        bucket: fragment("date_bin(?, ?, ?)", ^interval, c.checked_at, ^origin),
        total: count(c.id),
        up: filter(count(c.id), c.result == :up),
        degraded: filter(count(c.id), c.result == :degraded),
        down: filter(count(c.id), c.result == :down),
        rt_sum: coalesce(filter(sum(c.response_time_ms), c.result != :down), 0),
        rt_count: filter(count(c.response_time_ms), c.result != :down)
      }
    )
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  defp bucket_rows(ids, %{source: :rollups, bucket_seconds: s}, from, now, offset) do
    interval = %Postgrex.Interval{secs: s}
    origin = bin_origin(offset)

    from(r in CheckRollup,
      where: r.service_id in ^ids and r.bucket_start >= ^from and r.bucket_start <= ^now,
      group_by: fragment("1"),
      select: %{
        bucket: fragment("date_bin(?, ?, ?)", ^interval, r.bucket_start, ^origin),
        total: sum(r.total_count),
        up: sum(r.up_count),
        degraded: sum(r.degraded_count),
        down: sum(r.down_count),
        rt_sum: sum(r.response_time_sum_ms),
        rt_count: sum(r.response_time_count)
      }
    )
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  # Per-service totals.
  defp total_rows([], _config, _from, _now), do: []

  defp total_rows(ids, %{source: :checks}, from, now) do
    from(c in Check,
      where: c.service_id in ^ids and c.checked_at >= ^from and c.checked_at <= ^now,
      group_by: c.service_id,
      select: %{
        service_id: c.service_id,
        total: count(c.id),
        up: filter(count(c.id), c.result == :up),
        degraded: filter(count(c.id), c.result == :degraded),
        down: filter(count(c.id), c.result == :down),
        rt_sum: coalesce(filter(sum(c.response_time_ms), c.result != :down), 0),
        rt_count: filter(count(c.response_time_ms), c.result != :down)
      }
    )
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  defp total_rows(ids, %{source: :rollups}, from, now) do
    from(r in CheckRollup,
      where: r.service_id in ^ids and r.bucket_start >= ^from and r.bucket_start <= ^now,
      group_by: r.service_id,
      select: %{
        service_id: r.service_id,
        total: sum(r.total_count),
        up: sum(r.up_count),
        degraded: sum(r.degraded_count),
        down: sum(r.down_count),
        rt_sum: sum(r.response_time_sum_ms),
        rt_count: sum(r.response_time_count)
      }
    )
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  defp incident_counts([], _from, _now), do: %{}

  defp incident_counts(ids, from, now) do
    from(i in Incident,
      where:
        i.service_id in ^ids and i.started_at <= ^now and
          (is_nil(i.ended_at) or i.ended_at >= ^from),
      group_by: i.service_id,
      select: {i.service_id, count(i.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp incident_spans(service_id, from, now) do
    from(i in Incident,
      where:
        i.service_id == ^service_id and i.started_at <= ^now and
          (is_nil(i.ended_at) or i.ended_at >= ^from),
      select: {i.started_at, i.ended_at}
    )
    |> Repo.all()
  end

  defp down_seconds(spans, slot_start, slot_end) do
    ms =
      Enum.reduce(spans, 0, fn {started, ended}, acc ->
        a = Enum.max([started, slot_start], DateTime)
        b = Enum.min([ended || slot_end, slot_end], DateTime)
        acc + max(DateTime.diff(b, a, :millisecond), 0)
      end)

    div(ms + 999, 1000)
  end

  defp normalize(row) do
    row
    |> Map.update(:bucket, nil, &to_utc/1)
    |> Map.new(fn
      {k, %Decimal{} = v} -> {k, Decimal.to_integer(v)}
      {k, nil} when k != :bucket -> {k, 0}
      pair -> pair
    end)
  end

  defp to_utc(%DateTime{} = dt), do: DateTime.truncate(dt, :second)

  defp to_utc(%NaiveDateTime{} = dt),
    do: dt |> DateTime.from_naive!("Etc/UTC") |> DateTime.truncate(:second)

  defp to_utc(nil), do: nil

  defp empty_row(bucket),
    do: %{bucket: bucket, total: 0, up: 0, degraded: 0, down: 0, rt_sum: 0, rt_count: 0}

  defp finish_bucket(row, down_seconds) do
    avg = avg(row)

    %{
      start: row.bucket,
      total: row.total,
      up: row.up,
      degraded: row.degraded,
      down: row.down,
      uptime_pct: uptime(row),
      avg_response_ms: avg,
      down_seconds: down_seconds,
      status: bucket_status(row.total, avg, down_seconds)
    }
  end

  defp bucket_status(_total, _avg, down) when down > 0, do: :down
  defp bucket_status(0, _avg, _down), do: :no_data

  defp bucket_status(_total, avg, _down) do
    if is_integer(avg) and avg > degraded_threshold(), do: :degraded, else: :up
  end

  defp degraded_threshold do
    :uptime_monitor
    |> Application.fetch_env!(:monitoring)
    |> Keyword.get(:degraded_threshold_ms, 3_000)
  end

  defp uptime(%{total: 0}), do: nil
  defp uptime(%{total: total, down: down}), do: Float.round((total - down) * 100 / total, 2)

  defp avg(%{rt_count: 0}), do: nil
  defp avg(%{rt_sum: sum, rt_count: count}), do: round(sum / count)

  @doc """
  Rebuilds hourly rollups from raw checks (used by demo seeding). Optionally
  limited to one service.
  """
  def rebuild_rollups(service_id \\ nil) do
    {filter, params} =
      if service_id, do: {"WHERE service_id = $1", [service_id]}, else: {"", []}

    Repo.transaction(fn ->
      if service_id,
        do: Repo.query!("DELETE FROM check_rollups WHERE service_id = $1", params),
        else: Repo.query!("DELETE FROM check_rollups")

      Repo.query!(
        """
        INSERT INTO check_rollups
          (service_id, bucket_start, total_count, up_count, degraded_count, down_count,
           response_time_sum_ms, response_time_count)
        SELECT service_id, date_trunc('hour', checked_at),
               count(*),
               count(*) FILTER (WHERE result = 'up'),
               count(*) FILTER (WHERE result = 'degraded'),
               count(*) FILTER (WHERE result = 'down'),
               coalesce(sum(response_time_ms) FILTER (WHERE result <> 'down'), 0),
               count(response_time_ms) FILTER (WHERE result <> 'down')
        FROM checks #{filter}
        GROUP BY 1, 2
        """,
        params
      )
    end)
  end
end
