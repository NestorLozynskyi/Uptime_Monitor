# Seeds the Playwright database: the e2e administrator and the demo services
# (30 days of history) pointing at the local demo target.
{:ok, _} =
  UptimeMonitor.Accounts.upsert_admin(%{email: "e2e@example.com", password: "e2e-password-2026"})

UptimeMonitor.Demo.Seeder.run(System.fetch_env!("DEMO_TARGET_URL"))
