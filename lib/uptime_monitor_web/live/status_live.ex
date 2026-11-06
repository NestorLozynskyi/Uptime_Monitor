defmodule UptimeMonitorWeb.StatusLive do
  @moduledoc """
  Public status page (no authentication). Shows only public services — name,
  status, 30-day uptime and 30 daily availability bars — without URLs, admin
  actions or internal error details. Live updates come only from the public
  PubSub topic.
  """
  use UptimeMonitorWeb, :live_view

  alias UptimeMonitor.Monitoring.Events
  alias UptimeMonitor.StatusPage
  alias UptimeMonitorWeb.Format

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Events.subscribe_public()

    {:ok,
     socket
     |> assign(page_title: "Service status", title_suffix: "")
     |> load()}
  end

  defp load(socket) do
    now = DateTime.utc_now()
    overview = StatusPage.overview(:month, now, tz_offset: socket.assigns.tz_offset)
    assign(socket, overview: overview, updated_at: now)
  end

  @impl true
  def handle_info({:public_status, _event, _payload}, socket), do: {:noreply, load(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.public>
      <.hero overall={@overview.overall_status} services={@overview.services} />

      <section
        :if={@overview.services == []}
        class="panel"
        aria-labelledby="pub-empty"
        id="status-empty"
      >
        <div class="empty">
          <span class="empty-icon"><.icon name="i-server" class="i i-lg" /></span>
          <h1 id="pub-empty" style="font-size:18px">No services to show yet</h1>
          <p>This status page doesn’t list any services at the moment. Check back later.</p>
        </div>
      </section>

      <section :if={@overview.services != []} class="panel" aria-labelledby="pub-services">
        <div class="panel-head">
          <h2 id="pub-services">Services</h2>
          <.bars_legend />
        </div>
        <ul class="pub-list" id="public-services">
          <li :for={s <- @overview.services} class="pub-svc" id={"public-service-#{s.id}"}>
            <div class="pub-svc-head">
              <span class="pub-svc-name od-truncate">{s.name}</span>
              <span class="pub-uptime">
                {Format.pct(s.uptime_pct)}<span class="pub-uptime-label"> uptime</span>
              </span>
              <.status_badge
                status={s.status}
                label={if s.status == :pending, do: "No data", else: nil}
              />
            </div>
            <.bars
              buckets={s.buckets}
              period={:month}
              offset={@tz_offset}
              axis={["30 days ago", "Today"]}
            />
          </li>
        </ul>
      </section>

      <footer class="pub-foot">
        <Layouts.live_indicator
          updated_at={@updated_at}
          online_label="Updates automatically"
          online_prefix=""
        />
        <span>Uptime over the last 30 days</span>
      </footer>
    </Layouts.public>
    """
  end

  attr :overall, :atom, required: true
  attr :services, :list, required: true

  defp hero(%{overall: :no_services} = assigns), do: ~H""

  defp hero(assigns) do
    counts = Enum.frequencies_by(assigns.services, & &1.status)
    {cls, icon, title} = hero_style(assigns.overall)

    assigns =
      assign(assigns,
        cls: cls,
        icon: icon,
        title: title,
        text: hero_text(assigns.overall, counts)
      )

    ~H"""
    <section class={["hero", @cls]} role="status" id="overall-status" data-overall={@overall}>
      <.icon name={@icon} class="i i-xl" />
      <div class="hero-text">
        <h1 class="hero-title">{@title}</h1>
        <span class="muted small">{@text}</span>
      </div>
    </section>
    """
  end

  defp hero_style(:partial_outage), do: {"hero-down", "s-down", "Partial outage"}
  defp hero_style(:major_outage), do: {"hero-down", "s-down", "Major outage"}
  defp hero_style(:degraded), do: {"hero-degraded", "s-degraded", "Degraded performance"}
  defp hero_style(:operational), do: {"hero-up", "s-up", "All systems operational"}
  defp hero_style(:no_data), do: {"hero-neutral", "s-pending", "No data yet"}

  defp hero_text(:partial_outage, counts) do
    down = counts[:down] || 0
    slow = counts[:degraded] || 0
    up = counts[:up] || 0

    first = "#{Format.plural(down, "service", "services")} #{verb(down)} down"
    first = if slow > 0, do: "#{first} and #{slow} #{verb(slow)} slow to respond", else: first
    if up > 0, do: "#{first}. Other services are operating normally.", else: "#{first}."
  end

  defp hero_text(:major_outage, _counts),
    do:
      "All services are currently down. This page updates automatically as soon as they recover."

  defp hero_text(:degraded, counts) do
    slow = counts[:degraded] || 0

    "#{Format.plural(slow, "service", "services")} #{verb(slow)} responding slowly. All services are reachable."
  end

  defp hero_text(:operational, _counts), do: "Every service below is responding normally."

  defp hero_text(:no_data, _counts),
    do: "Services haven’t been checked yet. This page updates automatically."

  defp verb(1), do: "is"
  defp verb(_), do: "are"
end
