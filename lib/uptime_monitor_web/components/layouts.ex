defmodule UptimeMonitorWeb.Layouts do
  @moduledoc """
  Page shells of the design: the admin shell (top bar with Dashboard,
  Status page, theme switch and Sign out; a menu sheet below 768 px), the
  public status page shell and the sign-in shell.
  """
  use UptimeMonitorWeb, :html

  embed_templates "layouts/*"

  @doc "Admin shell with the shared navigation and the reconnect banner."
  slot :inner_block, required: true

  def admin(assigns) do
    ~H"""
    <a class="skip-link" href="#main">Skip to content</a>
    <header class="topbar">
      <div class="container topbar-in">
        <.link class="brand" navigate={~p"/admin"}>
          <span class="brand-mark"><.icon name="i-pulse" /></span><span>Uptime Monitor</span>
        </.link>
        <nav class="nav-main" aria-label="Main">
          <.link class="nav-link" navigate={~p"/admin"} aria-current="page">Dashboard</.link>
          <a class="nav-link" href={~p"/status"} target="_blank" rel="noopener">
            Status page<.icon name="i-external" class="i i-sm" /><span class="sr-only">(opens in a new tab)</span>
          </a>
        </nav>
        <div class="topbar-end">
          <.theme_switch id="theme-switch" />
          <.link class="btn btn-ghost btn-sm" href={~p"/logout"} method="delete">
            <.icon name="i-logout" class="i i-sm" /><span>Sign out</span>
          </.link>
        </div>
        <button
          class="btn btn-ghost btn-icon menu-btn"
          type="button"
          id="menu-button"
          data-dialog-open="menu-sheet"
          aria-haspopup="dialog"
          aria-expanded="false"
        >
          <.icon name="i-menu" /><span class="sr-only">Open menu</span>
        </button>
      </div>
    </header>
    <dialog class="sheet" id="menu-sheet" aria-label="Menu" phx-update="ignore">
      <div class="sheet-head">
        <span class="brand">
          <span class="brand-mark"><.icon name="i-pulse" /></span><span>Uptime Monitor</span>
        </span>
        <button class="btn btn-ghost btn-icon" type="button" data-dialog-close>
          <.icon name="i-close" /><span class="sr-only">Close menu</span>
        </button>
      </div>
      <div class="sheet-body">
        <nav class="sheet-nav" aria-label="Main">
          <.link class="nav-link" navigate={~p"/admin"} aria-current="page">Dashboard</.link>
          <a class="nav-link" href={~p"/status"} target="_blank" rel="noopener">
            Status page<.icon name="i-external" class="i i-sm" />
          </a>
        </nav>
        <div>
          <p class="sheet-label">Theme</p>
          <.theme_switch id="theme-switch-sheet" labels />
        </div>
        <.link class="btn btn-secondary btn-block" href={~p"/logout"} method="delete">
          <.icon name="i-logout" class="i i-sm" /><span>Sign out</span>
        </.link>
      </div>
    </dialog>

    <main class="page" id="main">
      <div class="container">
        <.reconnect_banner />
        {render_slot(@inner_block)}
      </div>
    </main>
    """
  end

  @doc """
  Shown only while the LiveView connection is lost (LiveView adds
  `phx-client-error` / `phx-server-error` to the view container).
  """
  def reconnect_banner(assigns) do
    ~H"""
    <div class="alert alert-warn reconnect-banner" id="reconnect-banner" role="status">
      <.icon name="i-offline" />
      <div class="alert-body">
        <span class="alert-title">Connection lost. Reconnecting…</span>
        <span class="muted">Statuses below may be out of date until the connection is back.</span>
      </div>
    </div>
    """
  end

  @doc "Live indicator: \"Live · updated …\" or \"Reconnecting… · last update …\"."
  attr :updated_at, :any, required: true
  attr :online_label, :string, default: "Live"
  attr :online_prefix, :string, default: "updated"
  attr :id, :string, default: "live-indicator"

  def live_indicator(assigns) do
    ~H"""
    <span id={@id}>
      <span class="live live-online">
        <span class="live-dot" aria-hidden="true"></span><span>{@online_label}</span><span class="subtle">· {@online_prefix}
        <.ago at={@updated_at} /></span>
      </span>
      <span class="live is-offline live-offline">
        <span class="live-dot" aria-hidden="true"></span><span>Reconnecting…</span><span class="subtle">· last update
        <.ago at={@updated_at} /></span>
      </span>
    </span>
    """
  end

  @doc "Public status page shell."
  slot :inner_block, required: true

  def public(assigns) do
    ~H"""
    <header class="pub-top">
      <div class="container container-narrow topbar-in">
        <span class="brand">
          <span class="brand-mark"><.icon name="i-pulse" /></span><span>Service status</span>
        </span>
        <div class="topbar-end"><.theme_switch id="theme-switch" /></div>
      </div>
    </header>
    <main class="page" id="main">
      <div class="container container-narrow">
        {render_slot(@inner_block)}
      </div>
    </main>
    """
  end

  @doc "Sign-in shell."
  slot :inner_block, required: true

  def auth(assigns) do
    ~H"""
    <div class="auth">
      <header class="auth-top">
        <span class="brand">
          <span class="brand-mark"><.icon name="i-pulse" /></span><span>Uptime Monitor</span>
        </span>
        <.theme_switch id="theme-switch" />
      </header>
      <main class="auth-main" id="main">
        {render_slot(@inner_block)}
      </main>
      <footer class="auth-foot"><a href={~p"/status"}>View public status page</a></footer>
    </div>
    """
  end
end
