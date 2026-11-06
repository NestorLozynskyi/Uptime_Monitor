defmodule UptimeMonitorWeb.ServiceLive do
  @moduledoc """
  Service details: status header with Check now / Edit / Delete, the ongoing
  incident banner, statistics for 24 h / 7 d / 30 d (metrics, response-time
  chart, availability bars, incidents) and the most recent checks.
  """
  use UptimeMonitorWeb, :live_view

  alias UptimeMonitor.Monitoring
  alias UptimeMonitor.Monitoring.{Events, Stats}
  alias UptimeMonitorWeb.Format

  @periods %{"24h" => :day, "7d" => :week, "30d" => :month}
  @period_titles %{day: "last 24 hours", week: "last 7 days", month: "last 30 days"}
  @axis %{day: ["24 h ago", "Now"], week: ["7 days ago", "Now"], month: ["30 days ago", "Today"]}
  @recent_checks 20

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Integer.parse(id) do
      {id, ""} ->
        if service = Monitoring.get_service(id) do
          if connected?(socket), do: Events.subscribe_service(id)

          {:ok,
           assign(socket,
             service: service,
             page_title: service.name,
             checking: false,
             confirm_delete: false
           )}
        else
          {:ok, not_found(socket)}
        end

      _ ->
        {:ok, not_found(socket)}
    end
  end

  defp not_found(socket) do
    socket
    |> put_flash(:error, "Service not found.")
    |> push_navigate(to: ~p"/admin")
    |> assign(service: nil)
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{service: nil}} = socket),
    do: {:noreply, socket}

  def handle_params(params, _uri, socket) do
    key = if Map.has_key?(@periods, params["period"]), do: params["period"], else: "24h"
    {:noreply, socket |> assign(period_key: key, period: @periods[key]) |> load()}
  end

  defp load(socket) do
    %{service: service, period: period, tz_offset: offset} = socket.assigns
    now = DateTime.utc_now()

    case Monitoring.get_service(service.id) do
      nil ->
        push_navigate(socket, to: ~p"/admin")

      service ->
        # Before the first check the availability history shows 30 empty days (design).
        period = if is_nil(service.last_checked_at), do: :month, else: period
        stats = Stats.service_stats(service.id, period, now, tz_offset: offset)

        assign(socket,
          service: service,
          page_title: service.name,
          stats: stats,
          bars_period: period,
          open_incident: Monitoring.get_open_incident(service.id),
          incidents: Monitoring.list_incidents(service_id: service.id, since: stats.from),
          checks: Monitoring.list_recent_checks(service.id, @recent_checks),
          updated_at: now
        )
    end
  end

  @impl true
  def handle_event("period", %{"period" => key}, socket) when is_map_key(@periods, key) do
    {:noreply,
     push_patch(socket, to: ~p"/admin/services/#{socket.assigns.service}?period=#{key}")}
  end

  def handle_event("check_now", _params, %{assigns: %{checking: true}} = socket),
    do: {:noreply, socket}

  def handle_event("check_now", _params, socket) do
    id = socket.assigns.service.id

    {:noreply,
     socket
     |> assign(checking: true)
     |> start_async(:check, fn -> Monitoring.check_now(id) end)}
  end

  def handle_event("confirm_delete", _params, socket),
    do: {:noreply, assign(socket, confirm_delete: true)}

  def handle_event("cancel_delete", _params, socket),
    do: {:noreply, assign(socket, confirm_delete: false)}

  def handle_event("delete", _params, socket) do
    case Monitoring.get_service(socket.assigns.service.id) do
      nil -> :ok
      service -> {:ok, _} = Monitoring.delete_service(service)
    end

    {:noreply, push_navigate(socket, to: ~p"/admin")}
  end

  @impl true
  def handle_async(:check, _result, socket) do
    {:noreply, socket |> assign(checking: false) |> load()}
  end

  @impl true
  def handle_info({:monitoring, :service_deleted, _payload}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/admin")}
  end

  def handle_info({:monitoring, event, _payload}, socket) do
    socket = load(socket)

    socket =
      if event == :check_completed,
        do: push_event(socket, "um:updated", %{id: "svc-head"}),
        else: socket

    {:noreply, socket}
  end

  defp no_data?(service), do: is_nil(service.last_checked_at)

  # Due services are picked up by the scheduler once a minute.
  defp first_check_in(service) do
    seconds = DateTime.diff(service.next_check_at, DateTime.utc_now())
    minutes = div(max(seconds, 0) + 59, 60) + 1
    Format.interval(min(minutes, service.interval_minutes) |> max(1))
  end

  defp chart_points(stats) do
    stats.buckets
    |> Enum.map(fn b ->
      %{
        s: DateTime.to_iso8601(b.start),
        e: DateTime.to_iso8601(DateTime.add(b.start, stats.bucket_seconds)),
        ms: b.avg_response_ms,
        st: b.status,
        down: b.down_seconds
      }
    end)
    |> Jason.encode!()
  end

  @impl true
  def render(%{service: nil} = assigns) do
    ~H"""
    <Layouts.admin>
      <p class="muted">Service not found.</p>
    </Layouts.admin>
    """
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        no_data: no_data?(assigns.service),
        title: @period_titles[assigns.period],
        axis: @axis[assigns.bars_period]
      )

    ~H"""
    <Layouts.admin>
      <.link class="back" navigate={~p"/admin"} style="margin-bottom: 12px">
        <.icon name="i-back" class="i i-sm" />Dashboard
      </.link>

      <section
        class={["svc-head flashable", @checking && "is-checking"]}
        id="svc-head"
        aria-label="Service"
      >
        <div class="svc-head-main">
          <div class="svc-title">
            <h1>{@service.name}</h1>
            <.status_badge status={@service.status} large id="service-status" />
            <.checking_badge :if={@checking} label="Checking now…" large />
          </div>
          <a class="svc-link" href={@service.url} target="_blank" rel="noopener noreferrer">
            <span>{@service.url}</span><.icon name="i-external" class="i i-sm" />
          </a>
          <div class="meta">
            <span>
              <.icon name="i-clock" class="i i-sm" />Every
              <strong>{Format.interval(@service.interval_minutes)}</strong>
            </span>
            <span :if={@service.public}><.icon name="i-globe" class="i i-sm" />Shown on status page</span>
            <span :if={!@service.public}><.icon name="i-private" class="i i-sm" />Not on status page</span>
            <span :if={@no_data}>First check within {first_check_in(@service)}</span>
            <span :if={!@no_data}>Last check <strong><.ago at={@service.last_checked_at} /></strong></span>
          </div>
        </div>
        <div class="svc-actions">
          <button
            class="btn btn-primary"
            type="button"
            id="check-now"
            phx-click="check_now"
            aria-busy={to_string(@checking)}
            aria-disabled={to_string(@checking)}
          >
            <.icon name="i-refresh" class={["i i-sm", @checking && "is-spinning"]} />
            <span class="btn-label">{if @checking, do: "Checking…", else: "Check now"}</span>
          </button>
          <.link class="btn btn-secondary" navigate={~p"/admin/services/#{@service}/edit"}>
            <.icon name="i-edit" class="i i-sm" /><span>Edit</span>
          </.link>
          <button
            class="btn btn-danger-outline"
            type="button"
            id="delete-service"
            phx-click="confirm_delete"
            aria-haspopup="dialog"
          >
            <.icon name="i-trash" class="i i-sm" /><span>Delete</span>
          </button>
        </div>
      </section>

      <div class="stack">
        <div :if={@open_incident} class="alert alert-error" id="incident-banner">
          <.icon name="s-down" />
          <div class="alert-body">
            <span class="alert-title">
              Incident ongoing for <.duration_since since={@open_incident.started_at} />
            </span>
            <span class="muted">
              {Format.cause(@open_incident.reason)} since {Format.datetime(
                @open_incident.started_at,
                @tz_offset
              )}. Closes automatically after 2 successful checks in a row.
            </span>
          </div>
        </div>

        <section aria-labelledby="stats-title">
          <div class="toolbar">
            <h2 id="stats-title">Statistics</h2>
            <div
              :if={!@no_data}
              class="seg"
              role="radiogroup"
              aria-label="Period"
              data-period-group
              id="period"
            >
              <button
                :for={{key, label} <- [{"24h", "24 h"}, {"7d", "7 d"}, {"30d", "30 d"}]}
                type="button"
                role="radio"
                phx-click="period"
                phx-value-period={key}
                aria-checked={to_string(@period_key == key)}
                tabindex={if @period_key == key, do: "0", else: "-1"}
                data-period={key}
              >
                {label}
              </button>
            </div>
          </div>

          <div :if={!@no_data} class="od-grid metrics" id="metrics">
            <div class="metric od-stat">
              <span class="metric-label">Uptime</span>
              <span class="metric-value" data-metric="uptime">{Format.pct(@stats.uptime_pct)}</span>
            </div>
            <div class="metric od-stat">
              <span class="metric-label">Avg response</span>
              <span class="metric-value" data-metric="avg">{Format.ms(@stats.avg_response_ms)}</span>
            </div>
            <div class="metric od-stat">
              <span class="metric-label">Incidents</span>
              <span class="metric-value" data-metric="incidents">{@stats.incident_count}</span>
            </div>
          </div>
          <div :if={@no_data} class="od-grid metrics" id="metrics">
            <div :for={label <- ["Uptime", "Avg response", "Incidents"]} class="metric od-stat">
              <span class="metric-label">{label}</span>
              <span class="metric-value subtle">—</span>
              <span class="metric-note">After first check</span>
            </div>
          </div>
        </section>

        <section class="panel" aria-labelledby="chart-title">
          <div class="panel-head">
            <h2 id="chart-title">
              Response time
              <span :if={!@no_data} class="subtle" style="font-weight:500">· {@title}</span>
            </h2>
            <div :if={!@no_data} class="legend">
              <span><span class="sw-line" aria-hidden="true"></span>Avg response</span>
              <span><span class="sw-band" aria-hidden="true"></span>Down</span>
            </div>
          </div>
          <div class="panel-body">
            <div
              :if={!@no_data}
              class="chart"
              id="response-chart"
              phx-hook="ResponseChart"
              phx-update="ignore"
              data-points={chart_points(@stats)}
              data-period={@period_key}
              data-label={"Response time, #{@title}. Average #{Format.ms(@stats.avg_response_ms)}. Hatched areas mark downtime."}
            >
              <canvas role="img"></canvas>
              <div class="chart-tip" data-chart-tip hidden></div>
            </div>
            <div :if={@no_data} class="chart">
              <div class="chart-empty">
                <div class="od-stack" style="--od-gap: 4px; justify-items:center">
                  <span style="font-weight:600">No checks yet</span>
                  <span class="small muted">
                    The chart appears after the first check. Run Check now to start right away.
                  </span>
                </div>
              </div>
            </div>
          </div>
        </section>

        <section class="panel" aria-labelledby="avail-title">
          <div class="panel-head">
            <h2 id="avail-title">Availability</h2>
            <.bars_legend />
          </div>
          <div class="panel-body">
            <.bars
              id="availability"
              buckets={@stats.buckets}
              period={@bars_period}
              offset={@tz_offset}
              axis={@axis}
            />
          </div>
        </section>

        <div class="cols-2">
          <section class="panel" aria-labelledby="incidents-title">
            <div class="panel-head">
              <h2 id="incidents-title">
                Incidents<span :if={!@no_data} class="count">{length(@incidents)}</span>
              </h2>
              <span :if={!@no_data} class="subtle small">{@title}</span>
            </div>
            <div class="tbl-wrap">
              <table class="tbl tbl-cards" id="incidents">
                <thead>
                  <tr>
                    <th scope="col">Started</th>
                    <th scope="col">Ended</th>
                    <th scope="col" class="num">Duration</th>
                    <th scope="col">Cause</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={i <- @incidents} id={"incident-#{i.id}"}>
                    <td data-label="Started" class="od-nowrap">
                      {Format.datetime(i.started_at, @tz_offset)}
                    </td>
                    <td :if={is_nil(i.ended_at)} data-label="Ended">
                      <.status_badge status={:down} label="Ongoing" />
                    </td>
                    <td :if={i.ended_at} data-label="Ended" class="od-nowrap">
                      <span class="block">{Format.datetime(i.ended_at, @tz_offset)}</span>
                      <span class="block subtle xsmall">Resolved</span>
                    </td>
                    <td data-label="Duration" class="num">
                      <.duration_since :if={is_nil(i.ended_at)} since={i.started_at} />
                      <span :if={i.ended_at}>{Format.duration(i.started_at, i.ended_at)}</span>
                    </td>
                    <td data-label="Cause" class="cell-full">{Format.cause(i.reason)}</td>
                  </tr>
                  <tr :if={@incidents == []} class="empty-row">
                    <td colspan="4">
                      {if @no_data, do: "No incidents recorded.", else: "No incidents in this period."}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          <section class="panel" aria-labelledby="checks-title">
            <div class="panel-head">
              <h2 id="checks-title">Recent checks</h2>
              <span class="subtle small">Newest first</span>
            </div>
            <div class="tbl-wrap">
              <table class="tbl tbl-cards" id="recent-checks">
                <thead>
                  <tr>
                    <th scope="col">Time</th>
                    <th scope="col">Result</th>
                    <th scope="col">HTTP</th>
                    <th scope="col" class="num">Response</th>
                    <th scope="col">Source</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :if={@checking} id="checking-row">
                    <td class="mono" data-label="Time">Now</td>
                    <td data-label="Result"><.checking_badge label="Checking…" /></td>
                    <td data-label="HTTP"><span class="skeleton" style="width:36px"></span></td>
                    <td class="num" data-label="Response">
                      <span class="skeleton" style="width:56px; margin-left:auto"></span>
                    </td>
                    <td data-label="Source" class="subtle">Manual</td>
                  </tr>
                  <tr :if={@checks == [] and !@checking} class="empty-row">
                    <td colspan="5">
                      No checks yet. The first scheduled check runs within {first_check_in(@service)}.
                    </td>
                  </tr>
                  <tr :for={c <- @checks} id={"check-#{c.id}"}>
                    <td class="mono" data-label="Time">
                      {Format.check_time(c.checked_at, @tz_offset)}
                    </td>
                    <td data-label="Result"><.status_badge status={c.result} /></td>
                    <td class="mono" data-label="HTTP">{c.status_code || "—"}</td>
                    <td class="num" data-label="Response">{check_response(c)}</td>
                    <td data-label="Source" class="subtle">
                      {if c.manual, do: "Manual", else: "Scheduled"}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        </div>
      </div>

      <dialog
        :if={@confirm_delete}
        class="modal"
        id="delete-dialog"
        aria-labelledby="delete-title"
        aria-describedby="delete-desc"
        phx-hook="Modal"
        phx-update="ignore"
        data-on-close="cancel_delete"
      >
        <div class="modal-body">
          <span class="modal-icon"><.icon name="i-trash" /></span>
          <h2 id="delete-title">Delete “{@service.name}”?</h2>
          <p id="delete-desc">
            Monitoring stops and all checks, incidents and statistics for this service are deleted. It also disappears from the public status page. This can’t be undone.
          </p>
        </div>
        <div class="modal-actions">
          <button class="btn btn-secondary" type="button" phx-click="cancel_delete" autofocus>
            Cancel
          </button>
          <button class="btn btn-danger" type="button" phx-click="delete" id="confirm-delete">
            <.icon name="i-trash" class="i i-sm" /><span>Delete service</span>
          </button>
        </div>
      </dialog>
    </Layouts.admin>
    """
  end

  defp check_response(%{error: "Timed out after " <> rest}), do: "Timeout #{rest}"
  defp check_response(%{response_time_ms: nil}), do: "—"
  defp check_response(%{response_time_ms: ms}), do: Format.ms(ms)
end
