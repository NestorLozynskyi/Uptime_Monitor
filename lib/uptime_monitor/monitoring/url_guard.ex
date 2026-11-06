defmodule UptimeMonitor.Monitoring.UrlGuard do
  @moduledoc """
  SSRF protection for monitored URLs.

  A URL is accepted only when it uses http/https, has a host, and **every**
  IP address the host resolves to is outside the forbidden ranges defined in
  `UptimeMonitor.Monitoring.IpRanges`. The caller then connects to the
  returned, already-validated IP (never re-resolving the name), which defeats
  DNS rebinding. Redirect targets are validated with the same function.

  Exceptions come only from the explicit allowlist (`SSRF_ALLOWLIST`, empty by
  default). Entries are either host names (exact, case-insensitive match on
  the URL host) or IPs/CIDRs (matched against each resolved address).
  """
  alias UptimeMonitor.Monitoring.{IpRanges, Resolver}

  defmodule Target do
    @moduledoc "A validated request target."
    defstruct [:uri, :scheme, :host, :port, :ip]
  end

  @doc """
  Validates `url` and resolves it to a safe target.

  Options: `:allowlist` (defaults to the configured allowlist).

  Returns `{:ok, %Target{}}` or `{:error, {kind, message}}` where kind is
  `:invalid`, `:blocked` or `:dns`.
  """
  def resolve(url, opts \\ []) do
    allowlist = Keyword.get_lazy(opts, :allowlist, &configured_allowlist/0)

    with {:ok, uri} <- parse(url),
         {:ok, ips} <- lookup(uri.host),
         :ok <- check_all(uri.host, ips, allowlist) do
      {:ok,
       %Target{
         uri: uri,
         scheme: String.to_existing_atom(uri.scheme),
         host: uri.host,
         port: uri.port,
         ip: pick_ip(ips)
       }}
    end
  end

  @doc "Validates the URL and returns `:ok` or `{:error, message}` (for changesets)."
  def validate(url, opts \\ []) do
    case resolve(url, opts) do
      {:ok, _target} -> :ok
      {:error, {_kind, message}} -> {:error, message}
    end
  end

  def configured_allowlist do
    Application.fetch_env!(:uptime_monitor, :monitoring) |> Keyword.get(:ssrf_allowlist, [])
  end

  defp parse(url) when is_binary(url) do
    case URI.new(String.trim(url)) do
      {:ok, %URI{scheme: scheme} = uri} when scheme in ["http", "https"] ->
        cond do
          uri.host in [nil, ""] -> {:error, {:invalid, "URL must include a host"}}
          uri.userinfo != nil -> {:error, {:invalid, "credentials in the URL are not supported"}}
          true -> {:ok, %{uri | host: String.downcase(uri.host)}}
        end

      {:ok, _} ->
        {:error, {:invalid, "only http:// and https:// URLs are allowed"}}

      {:error, _} ->
        {:error, {:invalid, "is not a valid URL"}}
    end
  end

  defp parse(_), do: {:error, {:invalid, "is not a valid URL"}}

  defp lookup(host) do
    case :inet.parse_strict_address(String.to_charlist(host)) do
      {:ok, ip} ->
        {:ok, [ip]}

      {:error, _} ->
        case Resolver.resolve(host) do
          {:ok, [_ | _] = ips} -> {:ok, ips}
          {:ok, []} -> {:error, {:dns, "DNS resolution failed: no addresses for #{host}"}}
          {:error, reason} -> {:error, {:dns, "DNS resolution failed for #{host} (#{reason})"}}
        end
    end
  end

  defp check_all(host, ips, allowlist) do
    {host_entries, cidrs} = parse_allowlist(allowlist)

    if host in host_entries do
      :ok
    else
      Enum.reduce_while(ips, :ok, fn ip, :ok ->
        case IpRanges.check(ip) do
          :ok ->
            {:cont, :ok}

          {:blocked, description} ->
            if Enum.any?(cidrs, &IpRanges.in_cidr?(ip, &1)) do
              {:cont, :ok}
            else
              {:halt,
               {:error,
                {:blocked, "address #{:inet.ntoa(ip)} of #{host} is not allowed (#{description})"}}}
            end
        end
      end)
    end
  end

  defp parse_allowlist(entries) do
    Enum.reduce(entries, {[], []}, fn entry, {hosts, cidrs} ->
      entry = entry |> to_string() |> String.trim() |> String.downcase()

      case IpRanges.parse_cidr(entry) do
        {:ok, cidr} -> {hosts, [cidr | cidrs]}
        :error when entry != "" -> {[entry | hosts], cidrs}
        :error -> {hosts, cidrs}
      end
    end)
  end

  # Prefer IPv4 (more commonly routable in containers); all IPs were validated.
  defp pick_ip(ips), do: Enum.find(ips, hd(ips), &(tuple_size(&1) == 4))
end
