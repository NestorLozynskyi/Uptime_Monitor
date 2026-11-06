import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :uptime_monitor, UptimeMonitor.Repo,
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
  database: "uptime_monitor_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :uptime_monitor, UptimeMonitorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ZoM/cXGJAZtXYvtCehhXdgWtea/FgdwXTaD4w5VCosA8AxarFTnY1BDnAVxveP0f",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

config :uptime_monitor, Oban, testing: :manual

config :bcrypt_elixir, :log_rounds, 1

# Tests resolve hostnames through a stub resolver and run the local test HTTP
# server on 127.0.0.1, which is allowlisted here (SSRF tests pass explicit
# allowlists to exercise the blocking rules).
config :uptime_monitor, :monitoring,
  check_timeout_ms: 1_500,
  degraded_threshold_ms: 300,
  max_redirects: 5,
  ssrf_allowlist: ["127.0.0.1/32"],
  resolver: UptimeMonitor.Monitoring.Resolver.Stub

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
