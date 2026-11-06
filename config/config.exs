# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :uptime_monitor,
  ecto_repos: [UptimeMonitor.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :uptime_monitor, UptimeMonitorWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: UptimeMonitorWeb.ErrorHTML, json: UptimeMonitorWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: UptimeMonitor.PubSub,
  live_view: [signing_salt: "ljIaCNbp"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  uptime_monitor: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  uptime_monitor: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :uptime_monitor, Oban,
  engine: Oban.Engines.Basic,
  repo: UptimeMonitor.Repo,
  queues: [checks: 20, scheduler: 1, maintenance: 1],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24},
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(2)},
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", UptimeMonitor.Monitoring.Workers.Scheduler},
       {"17 * * * *", UptimeMonitor.Monitoring.Workers.Cleanup}
     ]}
  ]

# Monitoring settings. The SSRF allowlist is empty by default and is only
# populated from the SSRF_ALLOWLIST environment variable (see runtime.exs).
config :uptime_monitor, :monitoring,
  check_timeout_ms: 10_000,
  degraded_threshold_ms: 3_000,
  max_redirects: 5,
  ssrf_allowlist: [],
  resolver: UptimeMonitor.Monitoring.Resolver.Inet

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
