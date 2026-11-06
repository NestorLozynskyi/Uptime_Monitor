defmodule UptimeMonitorWeb.Format do
  @moduledoc """
  Display formatting shared by the screens. Absolute times are shown in the
  viewer's time zone using the UTC offset reported by the browser (seconds
  east of UTC); relative times are refreshed in the browser every second.
  """

  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

  @doc "Shifts a UTC datetime by the viewer's offset."
  def local(%DateTime{} = dt, offset), do: DateTime.add(dt, offset || 0, :second)

  @doc ~S|"Nov 5, 14:02"|
  def datetime(nil, _offset), do: "—"

  def datetime(%DateTime{} = dt, offset) do
    l = local(dt, offset)
    "#{day(l)}, #{pad(l.hour)}:#{pad(l.minute)}"
  end

  @doc ~S|"Nov 5"|
  def date(%DateTime{} = dt, offset), do: dt |> local(offset) |> day()

  @doc ~S|"14:02"|
  def hm(%DateTime{} = dt, offset) do
    l = local(dt, offset)
    "#{pad(l.hour)}:#{pad(l.minute)}"
  end

  @doc ~S|"14:28:00" today, "Nov 4, 14:28" on other days|
  def check_time(%DateTime{} = dt, offset, now \\ DateTime.utc_now()) do
    l = local(dt, offset)

    if Date.compare(DateTime.to_date(l), DateTime.to_date(local(now, offset))) == :eq,
      do: "#{pad(l.hour)}:#{pad(l.minute)}:#{pad(l.second)}",
      else: datetime(dt, offset)
  end

  defp day(l), do: "#{Enum.at(@months, l.month - 1)} #{l.day}"
  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")

  @doc "Relative time, mirrored by the browser ticker (assets/js/app.js)."
  def ago(dt, now \\ DateTime.utc_now())
  def ago(nil, _now), do: "—"

  def ago(%DateTime{} = dt, now) do
    s = max(DateTime.diff(now, dt, :second), 0)

    cond do
      s < 5 -> "just now"
      s < 60 -> "#{s} s ago"
      s < 3_600 -> "#{div(s, 60)} min ago"
      s < 86_400 -> "#{div(s, 3_600)} h ago"
      true -> "#{div(s, 86_400)} d ago"
    end
  end

  @doc ~S|Duration: "26 min", "1 h 4 min", "2 d 3 h"|
  def duration(seconds) when is_integer(seconds) do
    m = div(max(seconds, 0), 60)

    cond do
      m < 60 -> "#{m} min"
      m < 1_440 -> "#{div(m, 60)} h #{rem(m, 60)} min"
      true -> "#{div(m, 1_440)} d #{div(rem(m, 1_440), 60)} h"
    end
  end

  def duration(%DateTime{} = from, to),
    do: duration(DateTime.diff(to || DateTime.utc_now(), from))

  @doc ~S|Response time: "214 ms", "3.42 s"|
  def ms(nil), do: "—"
  def ms(ms) when ms >= 1_000, do: "#{:erlang.float_to_binary(ms / 1_000, decimals: 2)} s"
  def ms(ms), do: "#{ms} ms"

  def pct(nil), do: "—"
  def pct(value), do: :erlang.float_to_binary(value * 1.0, decimals: 2) <> "%"

  def interval(minutes), do: "#{minutes} min"

  @doc "Human-readable cause of a failed check or incident."
  def cause(nil), do: "Check failed"

  def cause("HTTP " <> code = reason) do
    case Integer.parse(code) do
      {status, ""} ->
        phrase =
          try do
            Plug.Conn.Status.reason_phrase(status)
          rescue
            ArgumentError -> nil
          end

        if phrase, do: "HTTP #{status} #{phrase}", else: reason

      _ ->
        reason
    end
  end

  def cause("Timed out after " <> rest), do: "Timeout — no response in #{rest}"
  def cause("DNS" <> _), do: "DNS lookup failed"
  def cause(reason), do: reason

  @doc "Short label for a failed check in tables."
  def failure_label(%{status_code: code}) when is_integer(code), do: "HTTP #{code}"
  def failure_label(%{error: "Timed out" <> _}), do: "Timeout"
  def failure_label(%{error: "DNS" <> _}), do: "DNS error"
  def failure_label(%{error: "Blocked" <> _}), do: "Blocked"
  def failure_label(%{error: "Redirect blocked" <> _}), do: "Blocked"
  def failure_label(%{error: "Too many redirects" <> _}), do: "Redirects"
  def failure_label(%{error: "TLS" <> _}), do: "TLS error"
  def failure_label(_), do: "Connection error"

  def status_label(:up), do: "Up"
  def status_label(:degraded), do: "Degraded"
  def status_label(:down), do: "Down"
  def status_label(:pending), do: "Not checked yet"

  def plural(1, one, _many), do: "1 #{one}"
  def plural(n, _one, many), do: "#{n} #{many}"
end
