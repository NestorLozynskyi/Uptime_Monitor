defmodule UptimeMonitorWeb.CoreComponents do
  @moduledoc """
  UI building blocks of the approved design v1.1: icon sprite, status
  badges, theme switch, availability bars and live (browser-updated) times.
  Styles live in `assets/css/app.css`.
  """
  use Phoenix.Component

  alias UptimeMonitorWeb.Format

  # One outline icon family (1.75 stroke), identical to the design sprite.
  @icons %{
    "s-up" => ~s(<circle cx="12" cy="12" r="9"/><path d="M8 12.5l2.7 2.7L16.2 9.5"/>),
    "s-degraded" => ~s(<path d="M12 3.6 21.4 20H2.6z"/><path d="M12 10v4.4M12 17.4v.01"/>),
    "s-down" =>
      ~s(<path d="M8.3 3h7.4L21 8.3v7.4L15.7 21H8.3L3 15.7V8.3z"/><path d="M9.5 9.5l5 5M14.5 9.5l-5 5"/>),
    "s-pending" =>
      ~s(<circle cx="12" cy="12" r="9" stroke-dasharray="2.6 3"/><path d="M12 8v4.2l2.6 1.6"/>),
    "i-sun" =>
      ~s(<circle cx="12" cy="12" r="4"/><path d="M12 2.5v2M12 19.5v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2.5 12h2M19.5 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>),
    "i-moon" => ~s(<path d="M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"/>),
    "i-monitor" =>
      ~s(<rect x="3" y="4" width="18" height="12" rx="1.5"/><path d="M8 20h8M12 16v4"/>),
    "i-plus" => ~s(<path d="M12 5v14M5 12h14"/>),
    "i-refresh" =>
      ~s(<path d="M20 11a8 8 0 0 0-14.6-4.5M4 3.5V8h4.5"/><path d="M4 13a8 8 0 0 0 14.6 4.5M20 20.5V16h-4.5"/>),
    "i-menu" => ~s(<path d="M4 7h16M4 12h16M4 17h16"/>),
    "i-close" => ~s(<path d="M6 6l12 12M18 6 6 18"/>),
    "i-logout" =>
      ~s(<path d="M15 4h3a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-3"/><path d="M10 17l-5-5 5-5M5 12h11"/>),
    "i-back" => ~s(<path d="M15 18l-6-6 6-6"/>),
    "i-chevron" => ~s(<path d="M9 6l6 6-6 6"/>),
    "i-edit" => ~s(<path d="M4 20h4L19 9l-4-4L4 16z"/><path d="M13.5 6.5l4 4"/>),
    "i-trash" => ~s(<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/>),
    "i-external" =>
      ~s(<path d="M14 4h6v6M20 4l-9 9"/><path d="M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/>),
    "i-globe" =>
      ~s(<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.7 3.8 5.7 3.8 9s-1.3 6.3-3.8 9c-2.5-2.7-3.8-5.7-3.8-9S9.5 5.7 12 3z"/>),
    "i-private" =>
      ~s(<rect x="5" y="11" width="14" height="9" rx="1.5"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>),
    "i-alert" => ~s(<circle cx="12" cy="12" r="9"/><path d="M12 7.5v5.5M12 16.5v.01"/>),
    "i-pulse" => ~s(<path d="M3 12h4l2.5-6 5 12 2.5-6h4"/>),
    "i-offline" =>
      ~s(<path d="M3 3l18 18"/><path d="M8.5 16.5a5 5 0 0 1 6.2-.6M5 12.9a10 10 0 0 1 4.3-2.4M19 12.9a10 10 0 0 0-2.6-1.8M2 9.4a15 15 0 0 1 4.2-2.7M22 9.4A15 15 0 0 0 11 5.1"/><path d="M12 20h.01"/>),
    "i-clock" => ~s(<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>),
    "i-server" =>
      ~s(<rect x="4" y="4" width="16" height="7" rx="1.5"/><rect x="4" y="13" width="16" height="7" rx="1.5"/><path d="M8 7.5h.01M8 16.5h.01"/>),
    "i-check" => ~s(<path d="M5 12.5l4.5 4.5L19 7.5"/>)
  }

  @sprite Enum.map_join(@icons, fn {id, d} ->
            ~s(<symbol id="#{id}" viewBox="0 0 24 24">#{d}</symbol>)
          end)

  @doc "The SVG symbol sprite; rendered once per page by the root layout."
  def icon_sprite(assigns) do
    assigns = assign(assigns, :sprite, Phoenix.HTML.raw(@sprite))

    ~H"""
    <svg aria-hidden="true" width="0" height="0" style="position:absolute">{@sprite}</svg>
    """
  end

  attr :name, :string, required: true
  attr :class, :any, default: "i"
  attr :rest, :global

  def icon(assigns) do
    ~H"""
    <svg class={@class} aria-hidden="true" {@rest}><use href={"#" <> @name} /></svg>
    """
  end

  @doc "Status badge: icon + label + color (never color alone)."
  attr :status, :atom, required: true
  attr :large, :boolean, default: false
  attr :label, :string, default: nil
  attr :rest, :global

  def status_badge(assigns) do
    assigns =
      assign(assigns,
        cls: status_class(assigns.status),
        label: assigns.label || Format.status_label(assigns.status)
      )

    ~H"""
    <span class={["st", @cls, @large && "st-lg"]} data-status={@status} {@rest}>
      <.icon name={status_icon(@status)} />{@label}
    </span>
    """
  end

  def status_class(:up), do: "st-up"
  def status_class(:degraded), do: "st-degraded"
  def status_class(:down), do: "st-down"
  def status_class(_), do: "st-pending"

  def status_icon(:up), do: "s-up"
  def status_icon(:degraded), do: "s-degraded"
  def status_icon(:down), do: "s-down"
  def status_icon(_), do: "s-pending"

  @doc "\"Checking\" chip with a spinning icon."
  attr :label, :string, default: "Checking"
  attr :large, :boolean, default: false

  def checking_badge(assigns) do
    ~H"""
    <span class={["st st-checking", @large && "st-lg"]}>
      <.icon name="i-refresh" class="i is-spinning" />{@label}
    </span>
    """
  end

  @doc """
  Light / Dark / System switch. Handled in the browser (assets/js/app.js) and
  ignored by LiveView patches; the pressed state follows `data-theme-pref`.
  """
  attr :id, :string, required: true
  attr :labels, :boolean, default: false

  def theme_switch(assigns) do
    ~H"""
    <div
      id={@id}
      class={["seg", @labels && "seg-labels"]}
      role="group"
      aria-label="Theme"
      phx-update="ignore"
      data-theme-switch
    >
      <button
        :for={
          {value, label, icon} <- [
            {"light", "Light", "i-sun"},
            {"dark", "Dark", "i-moon"},
            {"system", "System", "i-monitor"}
          ]
        }
        type="button"
        data-theme-set={value}
        aria-pressed="false"
        title={!@labels && "#{label} theme"}
      >
        <.icon name={icon} class="i i-sm" /><span class={!@labels && "sr-only"}>{label}</span>
      </button>
    </div>
    """
  end

  @doc "Relative time (\"24 s ago\"), refreshed every second in the browser."
  attr :at, :any, required: true
  attr :class, :string, default: nil
  attr :rest, :global

  def ago(assigns) do
    ~H"""
    <time
      :if={@at}
      class={@class}
      datetime={DateTime.to_iso8601(@at)}
      data-ago
      {@rest}
    >{Format.ago(@at)}</time>
    """
  end

  @doc "Running duration since a time (\"26 min\"), refreshed in the browser."
  attr :since, :any, required: true

  def duration_since(assigns) do
    ~H"""
    <span data-since={DateTime.to_iso8601(@since)}>{Format.duration(@since, nil)}</span>
    """
  end

  @doc "Availability bars (one per slot) with the axis labels."
  attr :buckets, :list, required: true
  attr :period, :atom, required: true
  attr :offset, :integer, default: 0
  attr :axis, :list, required: true
  attr :id, :string, default: nil

  def bars(assigns) do
    counts = Enum.frequencies_by(assigns.buckets, & &1.status)

    label =
      "Availability, #{length(assigns.buckets)} intervals: #{counts[:up] || 0} up, " <>
        "#{counts[:degraded] || 0} degraded, #{counts[:down] || 0} down, " <>
        "#{counts[:no_data] || 0} without data"

    assigns = assign(assigns, aria: label)

    ~H"""
    <div id={@id}>
      <div class="bars" role="img" aria-label={@aria}>
        <span
          :for={b <- @buckets}
          class={["bar", bar_class(b.status)]}
          data-status={b.status}
          title={bar_title(b, @period, @offset)}
        ></span>
      </div>
      <div class="bars-axis"><span>{Enum.at(@axis, 0)}</span><span>{Enum.at(@axis, 1)}</span></div>
    </div>
    """
  end

  defp bar_class(:up), do: "b-u"
  defp bar_class(:degraded), do: "b-g"
  defp bar_class(:down), do: "b-d"
  defp bar_class(_), do: "b-n"

  @bar_names %{up: "Up", degraded: "Degraded", down: "Down", no_data: "No data"}

  defp bar_title(b, period, offset) do
    range =
      case period do
        :month ->
          Format.date(b.start, offset)

        :day ->
          "#{Format.datetime(b.start, offset)}–#{Format.hm(DateTime.add(b.start, 1_800), offset)}"

        :week ->
          "#{Format.datetime(b.start, offset)}–#{Format.hm(DateTime.add(b.start, 4 * 3_600), offset)}"
      end

    extra =
      cond do
        b.status == :down -> " · #{Format.duration(b.down_seconds)} down"
        b.uptime_pct -> " · #{Format.pct(b.uptime_pct)} uptime"
        true -> ""
      end

    "#{range} · #{@bar_names[b.status]}#{extra}"
  end

  @doc "Legend for availability bars."
  def bars_legend(assigns) do
    ~H"""
    <div class="legend">
      <span><span class="bar b-u" aria-hidden="true"></span>Up</span>
      <span><span class="bar b-g" aria-hidden="true"></span>Degraded</span>
      <span><span class="bar b-d" aria-hidden="true"></span>Down</span>
      <span><span class="bar b-n" aria-hidden="true"></span>No data</span>
    </div>
    """
  end

  @doc "Inline field error (design `.err`)."
  attr :id, :string, required: true
  slot :inner_block, required: true

  def field_error(assigns) do
    ~H"""
    <p id={@id} class="err">
      <.icon name="i-alert" class="i i-sm" /><span>{render_slot(@inner_block)}</span>
    </p>
    """
  end

  ## JS helpers

  alias Phoenix.LiveView.JS

  def show(js \\ %JS{}, selector), do: JS.show(js, to: selector)
  def hide(js \\ %JS{}, selector), do: JS.hide(js, to: selector)
end
