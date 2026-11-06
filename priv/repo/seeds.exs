# Development seeds: `mix run priv/repo/seeds.exs` (also run by `mix ecto.setup`).
#
# Creates demo services pointing at the demo target (start it with
# `mix uptime.demo_target`; URL from DEMO_TARGET_URL, default
# http://localhost:4100). The target runs on loopback, so seeding requires
# SSRF_ALLOWLIST to include it, e.g. SSRF_ALLOWLIST=localhost.
#
# The administrator is created with `mix uptime.admin EMAIL`.
url = System.get_env("DEMO_TARGET_URL", "http://localhost:4100")
UptimeMonitor.Demo.Seeder.run(url)
