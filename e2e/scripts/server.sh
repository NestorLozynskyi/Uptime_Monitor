#!/bin/sh
# Starts a fresh Uptime Monitor for the Playwright suite (used by
# playwright.config.ts → webServer): a dedicated database, the demo target
# HTTP service, demo data and an e2e administrator, then `mix phx.server`.
set -eu
cd "$(dirname "$0")/../.."

export MIX_ENV=dev
export POSTGRES_DB="${POSTGRES_DB:-uptime_monitor_e2e}"
export PORT="${E2E_PORT:-4010}"
export DEMO_TARGET_PORT="${E2E_TARGET_PORT:-4110}"
export DEMO_TARGET_URL="http://localhost:${DEMO_TARGET_PORT}"
export SSRF_ALLOWLIST="localhost"

mix compile >/dev/null
mix ecto.drop --quiet --force-drop >/dev/null 2>&1 || true
mix ecto.create --quiet
mix ecto.migrate --quiet >/dev/null

mix uptime.demo_target >/dev/null 2>&1 &
TARGET_PID=$!
trap 'kill $TARGET_PID 2>/dev/null || true' EXIT INT TERM

# Wait for the demo target, then seed.
i=0
until curl -fs "${DEMO_TARGET_URL}/ok" >/dev/null 2>&1; do
  i=$((i + 1)); [ "$i" -gt 60 ] && echo "demo target did not start" && exit 1; sleep 0.5
done
mix run e2e/scripts/seed.exs

mix phx.server
