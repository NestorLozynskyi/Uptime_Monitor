defmodule UptimeMonitor.Monitoring.Resolver.Inet do
  @moduledoc "Resolves A and AAAA records with the Erlang `:inet` resolver."
  @behaviour UptimeMonitor.Monitoring.Resolver

  @timeout 5_000

  @impl true
  def resolve(host) do
    charlist = String.to_charlist(host)

    results =
      for family <- [:inet, :inet6] do
        :inet.getaddrs(charlist, family, @timeout)
      end

    case for({:ok, ips} <- results, ip <- ips, do: ip) do
      [] ->
        reason =
          Enum.find_value(results, :nxdomain, fn
            {:error, reason} when reason != :nxdomain -> reason
            _ -> nil
          end)

        {:error, reason}

      ips ->
        {:ok, Enum.uniq(ips)}
    end
  end
end
