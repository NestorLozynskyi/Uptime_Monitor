defmodule UptimeMonitor.Monitoring.Resolver do
  @moduledoc """
  DNS resolution behaviour. The implementation is configured with
  `config :uptime_monitor, :monitoring, resolver: Module` so tests can stub DNS.
  """

  @callback resolve(host :: String.t()) :: {:ok, [:inet.ip_address()]} | {:error, term()}

  def resolve(host) do
    Application.fetch_env!(:uptime_monitor, :monitoring)
    |> Keyword.fetch!(:resolver)
    |> then(& &1.resolve(host))
  end
end
