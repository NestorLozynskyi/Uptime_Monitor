defmodule UptimeMonitor.Monitoring.HttpAdapter do
  @moduledoc """
  Req adapter that sends a single request to an already-validated IP address.

  It opens a one-off Mint connection to `target.ip` while using the original
  host name for the `Host` header, TLS SNI and certificate verification, so
  the name is never resolved again (DNS-rebinding protection). Only the status
  line and headers are read; the body is discarded.
  """
  alias UptimeMonitor.Monitoring.UrlGuard.Target

  defmodule TimeoutError do
    defexception message: "timeout"
  end

  @doc """
  Attaches the validated target and the absolute deadline (monotonic ms) to
  the request and sets this module as its adapter.
  """
  def attach(%Req.Request{} = request, %Target{} = target, deadline) do
    request
    |> Req.Request.put_private(:uptime_target, target)
    |> Req.Request.put_private(:uptime_deadline, deadline)
    |> Map.put(:adapter, __MODULE__)
  end

  @doc false
  def run(request) do
    target = Req.Request.get_private(request, :uptime_target)
    deadline = Req.Request.get_private(request, :uptime_deadline)

    case do_request(request, target, deadline) do
      {:ok, status, headers} ->
        {request, Req.Response.new(status: status, headers: headers, body: "")}

      {:error, exception} ->
        {request, exception}
    end
  end

  defp do_request(request, target, deadline) do
    path =
      case request.url do
        %URI{path: path, query: query} ->
          if(path in [nil, ""], do: "/", else: path) <> if(query, do: "?" <> query, else: "")
      end

    headers =
      for {name, values} <- request.headers, value <- List.wrap(values), do: {name, value}

    method = request.method |> to_string() |> String.upcase()

    result =
      with {:ok, conn} <- connect(target, deadline) do
        try do
          case Mint.HTTP.request(conn, method, path, headers, nil) do
            {:ok, conn, ref} -> receive_head(conn, ref, deadline, nil)
            {:error, _conn, reason} -> {:error, reason}
          end
        after
          Mint.HTTP.close(conn)
        end
      end

    case result do
      {:ok, _, _} = ok -> ok
      {:error, %{__exception__: true} = e} -> {:error, e}
      {:error, reason} -> {:error, Req.TransportError.exception(reason: reason)}
    end
  end

  defp connect(target, deadline) do
    with {:ok, timeout} <- remaining(deadline) do
      Mint.HTTP.connect(target.scheme, target.ip, target.port,
        hostname: target.host,
        mode: :passive,
        protocols: [:http1],
        transport_opts: [timeout: timeout]
      )
      |> case do
        {:ok, conn} -> {:ok, conn}
        {:error, %{reason: :timeout}} -> {:error, %TimeoutError{}}
        {:error, error} -> {:error, error}
      end
    end
  end

  defp receive_head(conn, ref, deadline, status) do
    with {:ok, timeout} <- remaining(deadline) do
      case Mint.HTTP.recv(conn, 0, timeout) do
        {:ok, conn, responses} ->
          handle_responses(conn, ref, deadline, responses, status)

        {:error, _conn, %{reason: :timeout}, _} ->
          {:error, %TimeoutError{}}

        {:error, _conn, error, _} ->
          {:error, error}
      end
    end
  end

  defp handle_responses(conn, ref, deadline, [], status),
    do: receive_head(conn, ref, deadline, status)

  defp handle_responses(conn, ref, deadline, [response | rest], status) do
    case response do
      {:status, ^ref, code} -> handle_responses(conn, ref, deadline, rest, code)
      # Informational 1xx responses are skipped by Mint; final headers end the read.
      {:headers, ^ref, headers} when is_integer(status) -> {:ok, status, headers}
      {:error, ^ref, error} -> {:error, error}
      _ -> handle_responses(conn, ref, deadline, rest, status)
    end
  end

  defp remaining(deadline) do
    case deadline - System.monotonic_time(:millisecond) do
      ms when ms > 0 -> {:ok, ms}
      _ -> {:error, %TimeoutError{}}
    end
  end
end
