defmodule UptimeMonitorWeb.Router do
  use UptimeMonitorWeb, :router

  import UptimeMonitorWeb.AdminAuth
  import UptimeMonitorWeb.TimeZone, only: [put_tz_offset: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {UptimeMonitorWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_admin
    plug :put_tz_offset
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Public (no authentication).
  scope "/", UptimeMonitorWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/health", HealthController, :show

    live_session :public, on_mount: [UptimeMonitorWeb.TimeZone] do
      live "/status", StatusLive, :index
    end
  end

  scope "/", UptimeMonitorWeb do
    pipe_through [:browser, :redirect_if_admin_is_authenticated]

    get "/login", SessionController, :new
    post "/login", SessionController, :create
  end

  scope "/", UptimeMonitorWeb do
    pipe_through [:browser]

    delete "/logout", SessionController, :delete
  end

  scope "/admin", UptimeMonitorWeb do
    pipe_through [:browser, :require_authenticated_admin]

    live_session :admin,
      on_mount: [{UptimeMonitorWeb.AdminAuth, :require_authenticated}, UptimeMonitorWeb.TimeZone] do
      live "/", DashboardLive, :index
      live "/services/new", ServiceFormLive, :new
      live "/services/:id", ServiceLive, :show
      live "/services/:id/edit", ServiceFormLive, :edit
    end
  end
end
