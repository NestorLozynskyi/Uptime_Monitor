defmodule UptimeMonitor.TargetServer do
  @moduledoc "Starts the demo target on 127.0.0.1 with a random port for HTTP tests."

  def start do
    {:ok, pid} = Bandit.start_link(UptimeMonitor.Demo.Target.bandit_opts(0, {127, 0, 0, 1}))
    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    :persistent_term.put({__MODULE__, :port}, port)
    port
  end

  def port, do: :persistent_term.get({__MODULE__, :port})

  @doc "URL on the target via a stub host name resolving to 127.0.0.1."
  def url(path, host \\ "app.target.test"), do: "http://#{host}:#{port()}#{path}"

  @doc "Returns a TCP port on 127.0.0.1 with nothing listening."
  def closed_port do
    {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end
end
