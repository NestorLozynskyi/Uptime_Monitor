defmodule UptimeMonitor.Monitoring.Resolver.Stub do
  @moduledoc """
  Test DNS resolver. Hosts are registered with `put/2` (global, so use unique
  host names per test). `localhost` and `*.target.test` resolve to 127.0.0.1;
  anything else unregistered fails with `:nxdomain`.
  """
  @behaviour UptimeMonitor.Monitoring.Resolver

  def put(host, result), do: :persistent_term.put({__MODULE__, String.downcase(host)}, result)

  @impl true
  def resolve(host) do
    case :persistent_term.get({__MODULE__, host}, nil) do
      nil ->
        if host == "localhost" or String.ends_with?(host, ".target.test"),
          do: {:ok, [{127, 0, 0, 1}]},
          else: {:error, :nxdomain}

      {:error, _} = error ->
        error

      ips when is_list(ips) ->
        {:ok, ips}
    end
  end
end
