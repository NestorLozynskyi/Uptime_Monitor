defmodule UptimeMonitor.Monitoring.IpRanges do
  @moduledoc """
  Address ranges that monitoring requests must never reach (SSRF protection),
  plus CIDR helpers.
  """
  import Bitwise

  # {cidr, description}
  @blocked_v4 [
    {"0.0.0.0/8", "unspecified/\"this\" network"},
    {"10.0.0.0/8", "private network"},
    {"100.64.0.0/10", "shared address space (CGNAT)"},
    {"127.0.0.0/8", "loopback"},
    {"169.254.0.0/16", "link-local (cloud metadata)"},
    {"172.16.0.0/12", "private network"},
    {"192.0.0.0/24", "IETF protocol assignments"},
    {"192.0.2.0/24", "documentation (TEST-NET-1)"},
    {"192.88.99.0/24", "6to4 relay anycast"},
    {"192.168.0.0/16", "private network"},
    {"198.18.0.0/15", "benchmarking"},
    {"198.51.100.0/24", "documentation (TEST-NET-2)"},
    {"203.0.113.0/24", "documentation (TEST-NET-3)"},
    {"224.0.0.0/4", "multicast"},
    {"240.0.0.0/4", "reserved"},
    {"255.255.255.255/32", "broadcast"}
  ]

  @blocked_v6 [
    {"::/128", "unspecified"},
    {"::1/128", "loopback"},
    {"::ffff:0:0/96", "IPv4-mapped IPv6"},
    {"::/96", "IPv4-compatible IPv6 (deprecated)"},
    {"64:ff9b::/96", "NAT64"},
    {"64:ff9b:1::/48", "NAT64 (local use)"},
    {"100::/64", "discard-only"},
    {"2001::/23", "IETF protocol assignments (incl. Teredo)"},
    {"2001:db8::/32", "documentation"},
    {"2002::/16", "6to4"},
    {"3fff::/20", "documentation"},
    {"5f00::/16", "SRv6 SIDs (reserved)"},
    {"fc00::/7", "unique local (private)"},
    {"fe80::/10", "link-local"},
    {"fec0::/10", "site-local (deprecated)"},
    {"ff00::/8", "multicast"}
  ]

  @doc """
  Returns `{:blocked, description}` when the IP is in a forbidden range,
  otherwise `:ok`.
  """
  def check(ip) do
    ranges = if tuple_size(ip) == 4, do: blocked_v4(), else: blocked_v6()

    case Enum.find(ranges, fn {cidr, _} -> in_cidr?(ip, cidr) end) do
      nil -> :ok
      {{_, _}, description} -> {:blocked, description}
    end
  end

  defp blocked_v4, do: Enum.map(@blocked_v4, fn {c, d} -> {parse_cidr!(c), d} end)
  defp blocked_v6, do: Enum.map(@blocked_v6, fn {c, d} -> {parse_cidr!(c), d} end)

  @doc "Parses `\"10.0.0.0/8\"` or a bare IP into `{ip_tuple, prefix_length}`."
  def parse_cidr(value) when is_binary(value) do
    {addr, prefix} =
      case String.split(value, "/", parts: 2) do
        [addr, prefix] -> {addr, prefix}
        [addr] -> {addr, nil}
      end

    with {:ok, ip} <- :inet.parse_strict_address(String.to_charlist(String.trim(addr))),
         max = if(tuple_size(ip) == 4, do: 32, else: 128),
         {:ok, len} <- parse_prefix(prefix, max) do
      {:ok, {ip, len}}
    else
      _ -> :error
    end
  end

  defp parse_prefix(nil, max), do: {:ok, max}

  defp parse_prefix(prefix, max) do
    case Integer.parse(prefix) do
      {len, ""} when len >= 0 and len <= max -> {:ok, len}
      _ -> :error
    end
  end

  defp parse_cidr!(value) do
    {:ok, cidr} = parse_cidr(value)
    cidr
  end

  @doc "Whether `ip` is inside the `{network, prefix}` CIDR (same family only)."
  def in_cidr?(ip, {network, len}) when tuple_size(ip) == tuple_size(network) do
    bits = if tuple_size(ip) == 4, do: 32, else: 128
    mask = bsl(1, bits) - bsl(1, bits - len)
    band(to_integer(ip), mask) == band(to_integer(network), mask)
  end

  def in_cidr?(_ip, _cidr), do: false

  defp to_integer({a, b, c, d}), do: bsl(a, 24) + bsl(b, 16) + bsl(c, 8) + d

  defp to_integer({_, _, _, _, _, _, _, _} = ip) do
    ip |> Tuple.to_list() |> Enum.reduce(0, fn part, acc -> bsl(acc, 16) + part end)
  end
end
