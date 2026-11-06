defmodule UptimeMonitor.Demo.Target do
  @moduledoc """
  A small HTTP service used as a monitoring target in the demo and in tests,
  so no external websites are needed.

  | Path                       | Behaviour                                            |
  |----------------------------|------------------------------------------------------|
  | `/` , `/ok`                | 200 OK                                               |
  | `/status/:code`            | responds with the given status (100–599)             |
  | `/delay/:ms`               | waits `ms` (max 60 000) then 200; `?status=` overrides |
  | `/redirect/:n`             | chain of `n` 302 redirects ending at `/ok`           |
  | `/redirect-to?url=...`     | 302 to an arbitrary URL (for SSRF redirect tests)    |
  | `/redirect-loop`           | redirects to itself forever                          |
  | `/flaky/:percent`          | fails with 500 in `percent`% of requests             |
  | `/cycle/:up/:down`         | 200 for `up` minutes, then 503 for `down` minutes, repeating |
  | `/slow-random/:min/:max`   | 200 after a random delay between `min` and `max` ms  |

  Run standalone with `UptimeMonitor.Demo.Target.serve/0` (port from
  `DEMO_TARGET_PORT`, default 4100) or `mix uptime.demo_target`.
  """
  use Plug.Router

  plug :match
  plug Plug.Parsers, parsers: [], pass: ["*/*"]
  plug :dispatch

  get "/" do
    text(conn, 200, """
    Uptime Monitor demo target
    /ok /status/:code /delay/:ms /redirect/:n /redirect-to?url= /redirect-loop
    /flaky/:percent /cycle/:up_minutes/:down_minutes /slow-random/:min_ms/:max_ms
    """)
  end

  get("/ok", do: text(conn, 200, "OK"))

  get "/status/:code" do
    case Integer.parse(code) do
      {status, ""} when status in 200..599 -> text(conn, status, "Status #{status}")
      _ -> text(conn, 400, "invalid status")
    end
  end

  get "/delay/:ms" do
    ms = ms |> to_int(0) |> min(60_000)
    Process.sleep(ms)
    status = conn.query_params |> Map.get("status", "200") |> to_int(200)
    text(conn, status, "Delayed #{ms} ms")
  end

  get "/redirect/:n" do
    case to_int(n, 0) do
      n when n > 0 -> redirect(conn, "/redirect/#{n - 1}")
      _ -> text(conn, 200, "Redirect chain finished")
    end
  end

  get "/redirect-to" do
    case conn.query_params do
      %{"url" => url} -> redirect(conn, url)
      _ -> text(conn, 400, "missing url")
    end
  end

  get("/redirect-loop", do: redirect(conn, "/redirect-loop"))

  get "/flaky/:percent" do
    percent = percent |> to_int(50) |> max(0) |> min(100)

    if :rand.uniform(100) <= percent,
      do: text(conn, 500, "Random failure"),
      else: text(conn, 200, "OK")
  end

  get "/cycle/:up/:down" do
    up = up |> to_int(10) |> max(1)
    down = down |> to_int(5) |> max(1)
    minute = div(System.os_time(:second), 60)

    if rem(minute, up + down) < up,
      do: text(conn, 200, "OK (up phase)"),
      else: text(conn, 503, "Service Unavailable (down phase)")
  end

  get "/slow-random/:min/:max" do
    min = min |> to_int(0) |> max(0)
    max = max |> to_int(min) |> max(min) |> min(60_000)
    Process.sleep(min + :rand.uniform(max - min + 1) - 1)
    text(conn, 200, "OK")
  end

  match(_, do: text(conn, 404, "Not found"))

  defp text(conn, status, body) do
    conn |> put_resp_content_type("text/plain") |> send_resp(status, body)
  end

  defp redirect(conn, location) do
    conn |> put_resp_header("location", location) |> text(302, "Redirecting")
  end

  defp to_int(value, default) do
    case Integer.parse(to_string(value)) do
      {int, ""} -> int
      _ -> default
    end
  end

  @doc "Child spec options for running the target under Bandit."
  def bandit_opts(port, ip \\ :any),
    do: [plug: __MODULE__, port: port, ip: ip, startup_log: false]

  @doc "Starts the target standalone and blocks forever (used by Docker Compose)."
  def serve do
    {:ok, _} = Application.ensure_all_started(:bandit)
    port = String.to_integer(System.get_env("DEMO_TARGET_PORT", "4100"))
    {:ok, _} = Bandit.start_link(bandit_opts(port))
    IO.puts("Demo target listening on port #{port}")
    Process.sleep(:infinity)
  end
end
