defmodule UptimeMonitorWeb.DashboardLive do
  @moduledoc "Admin dashboard: status summary, active incidents and the services table."
  use UptimeMonitorWeb, :live_view

  alias UptimeMonitor.Monitoring
  alias UptimeMonitor.Monitoring.{Events, Stats}
  alias UptimeMonitorWeb.Format

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Events.subscribe_admin()

    {:ok,
     socket
     |> assign(page_title: "Dashboard", checking: MapSet.new())
     |> load()}
  end

  defp load(socket) do
    now = DateTime.utc_now()
    services = Monitoring.list_services()
    counts = Enum.frequencies_by(services, & &1.status)

    incidents =
      [since: now]
      |> Monitoring.list_incidents()
      |> Enum.filter(&is_nil(&1.ended_at))
      |> Enum.sort_by(& &1.started_at, {:asc, DateTime})

    assign(socket,
      services: services,
      counts: counts,
      uptime: Stats.summaries(Enum.map(services, & &1.id), :day, now),
      incidents: incidents,
      updated_at: now
    )
  end

  @impl true
  def handle_event("check_now", %{"id" => id}, socket) do
    id = String.to_integer(id)

    if MapSet.member?(socket.assigns.checking, id) do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> update(:checking, &MapSet.put(&1, id))
       |> start_async({:check, id}, fn -> Monitoring.check_now(id) end)}
    end
  end

  @impl true
  def handle_async({:check, id}, _result, socket) do
    {:noreply, socket |> update(:checking, &MapSet.delete(&1, id)) |> load()}
  end

  @impl true
  def handle_info({:monitoring, event, payload}, socket) do
    socket = load(socket)

    socket =
      case {event, payload} do
        {:check_completed, %{service: %{id: id}}} ->
          push_event(socket, "um:updated", %{id: "service-#{id}"})

        _ ->
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin>
      <div class="page-head">
        <div class="page-head-title">
          <h1>Dashboard</h1>
          <Layouts.live_indicator :if={@services != []} updated_at={@updated_at} />
        </div>
        <div :if={@services != []} class="page-head-actions">
          <.link class="btn btn-primary" navigate={~p"/admin/services/new"}>
            <.icon name="i-plus" class="i i-sm" /><span>Add service</span>
          </.link>
        </div>
      </div>

      <section :if={@services == []} class="panel" aria-labelledby="empty-title" id="empty-state">
        <div class="empty">
          <span class="empty-icon"><.icon name="i-server" class="i i-lg" /></span>
          <h2 id="empty-title">No services yet</h2>
          <p>
            Add the first website or server address. It’s checked on the interval you choose, from every minute to once an hour.
          </p>
          <.link class="btn btn-primary" navigate={~p"/admin/services/new"}>
            <.icon name="i-plus" class="i i-sm" /><span>Add service</span>
          </.link>
        </div>
      </section>

      <div :if={@services != []}>
        <section class="od-grid summary" aria-label="Status summary" id="summary">
          <.tile status={:up} label="Up" count={@counts[:up] || 0} />
          <.tile status={:degraded} label="Degraded" count={@counts[:degraded] || 0} />
          <.tile status={:down} label="Down" count={@counts[:down] || 0} />
          <.tile status={:pending} label="Not checked yet" count={@counts[:pending] || 0} />
        </section>

        <div class="stack">
          <section class="panel" aria-labelledby="inc-title" id="active-incidents">
            <div class="panel-head">
              <h2 id="inc-title">
                Active incidents<span :if={@incidents != []} class="count">{length(@incidents)}</span>
              </h2>
              <span class="subtle small">Opens after 3 failed checks in a row · closes after 2 successful</span>
            </div>
            <ul :if={@incidents != []} class="inc-list">
              <li :for={i <- @incidents} class="inc-item" id={"incident-#{i.id}"}>
                <.icon name="s-down" class="i inc-icon" />
                <div class="inc-main">
                  <.link class="inc-title" navigate={~p"/admin/services/#{i.service_id}"}>
                    {i.service.name}
                  </.link>
                  <span class="small muted">{Format.cause(i.reason)}</span>
                </div>
                <div class="inc-side">
                  <span class="c-down" style="font-weight:600">
                    Ongoing · <.duration_since since={i.started_at} />
                  </span>
                  <span class="subtle">Since {Format.datetime(i.started_at, @tz_offset)}</span>
                </div>
              </li>
            </ul>
            <div :if={@incidents == []} class="no-incidents">
              <.icon name="s-up" class="i c-up" />
              <div class="od-stack" style="--od-gap: 0">
                <span style="font-weight:600">No active incidents</span>
                <span class="small muted">Every checked service is responding.</span>
              </div>
            </div>
          </section>

          <section class="panel" aria-labelledby="svc-title">
            <div class="panel-head">
              <h2 id="svc-title">Services<span class="count">{length(@services)}</span></h2>
            </div>
            <div class="tbl-wrap">
              <table class="tbl tbl-hover tbl-cards tbl-services" id="services">
                <thead>
                  <tr>
                    <th scope="col">Service</th>
                    <th scope="col">Status</th>
                    <th scope="col" class="num">Response</th>
                    <th scope="col" class="num">Uptime 24h</th>
                    <th scope="col">Last check</th>
                    <th scope="col">Visibility</th>
                    <th scope="col"><span class="sr-only">Actions</span></th>
                  </tr>
                </thead>
                <tbody>
                  <.service_row
                    :for={s <- @services}
                    service={s}
                    uptime={@uptime[s.id]}
                    checking={MapSet.member?(@checking, s.id)}
                  />
                </tbody>
              </table>
            </div>
          </section>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  attr :status, :atom, required: true
  attr :label, :string, required: true
  attr :count, :integer, required: true

  defp tile(assigns) do
    ~H"""
    <div
      class={["tile od-stat", @status == :down && "tile-down", @count == 0 && "is-zero"]}
      data-tile={@status}
    >
      <span class="tile-label">
        <.icon name={status_icon(@status)} class={"i i-sm c-#{@status}"} />{@label}
      </span>
      <span class="tile-count">{@count}</span>
    </div>
    """
  end

  attr :service, :map, required: true
  attr :uptime, :map, required: true
  attr :checking, :boolean, default: false

  defp service_row(assigns) do
    ~H"""
    <tr id={"service-#{@service.id}"} class={@checking && "is-checking"} data-status={@service.status}>
      <td class="cell-full">
        <div class="svc-cell">
          <.link class="svc-name" navigate={~p"/admin/services/#{@service.id}"}>{@service.name}</.link>
          <span class="svc-url od-truncate">{@service.url}</span>
        </div>
      </td>
      <td data-label="Status">
        <div class="status-cell">
          <.status_badge status={@service.status} />
          <.checking_badge :if={@checking} />
        </div>
      </td>
      <.response_cell service={@service} />
      <td class={["num", is_nil(@uptime.uptime_pct) && "subtle"]} data-label="Uptime 24h">
        {Format.pct(@uptime.uptime_pct)}
      </td>
      <td :if={@service.last_checked_at} data-label="Last check">
        <.ago at={@service.last_checked_at} class="block od-nowrap" />
        <span class="block subtle xsmall">Every {Format.interval(@service.interval_minutes)}</span>
      </td>
      <td :if={!@service.last_checked_at} data-label="Last check" class="subtle">
        <span class="block">Waiting</span>
        <span class="block xsmall">Every {Format.interval(@service.interval_minutes)}</span>
      </td>
      <td data-label="Visibility">
        <span class="vis" title={if @service.public, do: "Public", else: "Private"}>
          <.icon name={if @service.public, do: "i-globe", else: "i-private"} class="i i-sm" />
          <span class="vis-label">{if @service.public, do: "Public", else: "Private"}</span>
        </span>
      </td>
      <td class="cell-full">
        <div class="row-actions">
          <button
            class="btn btn-secondary btn-sm btn-check"
            type="button"
            title={if @checking, do: "Checking…", else: "Check now"}
            phx-click="check_now"
            phx-value-id={@service.id}
            aria-busy={to_string(@checking)}
            aria-disabled={to_string(@checking)}
          >
            <.icon name="i-refresh" class={["i i-sm", @checking && "is-spinning"]} />
            <span class="btn-label">{if @checking, do: "Checking…", else: "Check now"}</span>
          </button>
          <.link class="btn btn-ghost btn-sm btn-icon" navigate={~p"/admin/services/#{@service.id}"}>
            <.icon name="i-chevron" class="i i-sm" /><span class="sr-only">{@service.name} details</span>
          </.link>
        </div>
      </td>
    </tr>
    """
  end

  attr :service, :map, required: true

  defp response_cell(%{service: %{status: :pending}} = assigns) do
    ~H"""
    <td class="num subtle" data-label="Response">—</td>
    """
  end

  defp response_cell(%{service: %{status: :down}} = assigns) do
    ~H"""
    <td class="num" data-label="Response">
      <span class="c-down">
        {Format.failure_label(%{status_code: @service.last_status_code, error: @service.last_error})}
      </span>
      <span :if={@service.last_response_time_ms} class="subtle xsmall">
        {Format.ms(@service.last_response_time_ms)}
      </span>
    </td>
    """
  end

  defp response_cell(%{service: %{status: :degraded}} = assigns) do
    ~H"""
    <td class="num" data-label="Response">
      <span class="ms-slow">{Format.ms(@service.last_response_time_ms)}</span>
      <span class="subtle xsmall">over 3 s</span>
    </td>
    """
  end

  defp response_cell(assigns) do
    ~H"""
    <td class="num" data-label="Response">
      <span>{Format.ms(@service.last_response_time_ms)}</span>
    </td>
    """
  end
end
