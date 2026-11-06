defmodule UptimeMonitor.Monitoring.HttpCheck do
  @moduledoc """
  Performs one HTTP check of a URL and classifies the outcome.

    * `:up` — final response is HTTP 2xx/3xx within the degraded threshold;
    * `:degraded` — successful response that took longer than the threshold (3 s);
    * `:down` — HTTP 4xx/5xx, timeout (10 s total), DNS, connection/TLS error,
      a forbidden (SSRF) address or too many redirects.

  Redirects (3xx with `Location`) are followed manually, up to `max_redirects`,
  and every hop is re-validated by `UrlGuard`. The total time budget covers
  DNS, all hops and the response headers of the final hop.
  """
  alias UptimeMonitor.Monitoring.{HttpAdapter, UrlGuard}

  @user_agent "UptimeMonitor/1.0"

  defmodule Result do
    @moduledoc "Outcome of a single check."
    @enforce_keys [:result, :checked_at]
    defstruct [:result, :checked_at, :status_code, :response_time_ms, :error]

    @type t :: %__MODULE__{
            result: :up | :degraded | :down,
            checked_at: DateTime.t(),
            status_code: integer() | nil,
            response_time_ms: non_neg_integer() | nil,
            error: String.t() | nil
          }
  end

  @doc "Runs a check. Options override the configured `:timeout`, `:degraded_threshold`, `:max_redirects`, `:allowlist`."
  def run(url, opts \\ []) do
    config = Application.fetch_env!(:uptime_monitor, :monitoring)
    timeout = Keyword.get(opts, :timeout, config[:check_timeout_ms])
    threshold = Keyword.get(opts, :degraded_threshold, config[:degraded_threshold_ms])

    opts =
      opts
      |> Keyword.put_new(:max_redirects, config[:max_redirects])
      |> Keyword.put_new_lazy(:allowlist, &UrlGuard.configured_allowlist/0)

    checked_at = DateTime.utc_now()
    started = System.monotonic_time(:millisecond)
    deadline = started + timeout

    task =
      Task.Supervisor.async_nolink(UptimeMonitor.TaskSupervisor, fn ->
        follow(url, 0, deadline, opts)
      end)

    outcome =
      case Task.yield(task, timeout + 50) || Task.shutdown(task, :brutal_kill) do
        {:ok, outcome} -> outcome
        {:exit, reason} -> {:error, "Check crashed: #{Exception.format_exit(reason)}"}
        nil -> {:error, :timeout}
      end

    elapsed = System.monotonic_time(:millisecond) - started
    classify(outcome, elapsed, timeout, threshold, checked_at)
  end

  defp classify({:ok, status}, elapsed, _timeout, threshold, checked_at)
       when status in 200..399 do
    %Result{
      result: if(elapsed > threshold, do: :degraded, else: :up),
      status_code: status,
      response_time_ms: elapsed,
      checked_at: checked_at
    }
  end

  defp classify({:ok, status}, elapsed, _timeout, _threshold, checked_at) do
    %Result{
      result: :down,
      status_code: status,
      response_time_ms: elapsed,
      error: "HTTP #{status}",
      checked_at: checked_at
    }
  end

  defp classify({:error, :timeout}, _elapsed, timeout, _threshold, checked_at) do
    %Result{
      result: :down,
      error: "Timed out after #{format_seconds(timeout)}",
      checked_at: checked_at
    }
  end

  defp classify({:error, message}, _elapsed, _timeout, _threshold, checked_at) do
    %Result{result: :down, error: message, checked_at: checked_at}
  end

  defp format_seconds(ms) when rem(ms, 1000) == 0, do: "#{div(ms, 1000)} s"
  defp format_seconds(ms), do: "#{Float.round(ms / 1000, 1)} s"

  defp follow(url, hops, deadline, opts) do
    case UrlGuard.resolve(url, allowlist: opts[:allowlist]) do
      {:ok, target} ->
        case request(url, target, deadline) do
          {:ok, %Req.Response{status: status} = response} when status in 300..399 ->
            case Req.Response.get_header(response, "location") do
              [location | _] ->
                if hops >= opts[:max_redirects] do
                  {:error, "Too many redirects (more than #{opts[:max_redirects]})"}
                else
                  next = url |> URI.merge(location) |> URI.to_string()
                  follow(next, hops + 1, deadline, opts)
                end

              [] ->
                {:ok, status}
            end

          {:ok, %Req.Response{status: status}} ->
            {:ok, status}

          {:error, %HttpAdapter.TimeoutError{}} ->
            {:error, :timeout}

          {:error, exception} ->
            {:error, describe(exception)}
        end

      {:error, {:blocked, message}} ->
        prefix = if hops > 0, do: "Redirect blocked: ", else: "Blocked: "
        {:error, prefix <> message}

      {:error, {:invalid, message}} ->
        prefix = if hops > 0, do: "Invalid redirect URL: ", else: "Invalid URL: "
        {:error, prefix <> message}

      {:error, {:dns, message}} ->
        {:error, message}
    end
  end

  defp request(url, target, deadline) do
    Req.new(
      url: url,
      method: :get,
      redirect: false,
      retry: false,
      compressed: false,
      decode_body: false,
      headers: [{"user-agent", @user_agent}, {"accept", "*/*"}]
    )
    |> HttpAdapter.attach(target, deadline)
    |> Req.request()
  end

  defp describe(%Req.TransportError{reason: reason}), do: describe_reason(reason)
  defp describe(%Mint.TransportError{reason: reason}), do: describe_reason(reason)
  defp describe(%Mint.HTTPError{} = e), do: "HTTP protocol error: " <> Exception.message(e)
  defp describe(exception), do: "Request failed: " <> Exception.message(exception)

  defp describe_reason(:econnrefused), do: "Connection refused"
  defp describe_reason(:closed), do: "Connection closed by the server"
  defp describe_reason(:ehostunreach), do: "Host unreachable"
  defp describe_reason(:enetunreach), do: "Network unreachable"
  defp describe_reason(:econnreset), do: "Connection reset by the server"
  defp describe_reason(:timeout), do: "Timed out"

  defp describe_reason({:tls_alert, {alert, _description}}),
    do: "TLS error: #{alert |> to_string() |> String.replace("_", " ")}"

  defp describe_reason(reason),
    do: "Connection error: " <> Exception.message(%Mint.TransportError{reason: reason})
end
