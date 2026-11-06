import {expect, Page} from "@playwright/test"
import {execFileSync} from "node:child_process"
import path from "node:path"

export const ADMIN = {email: "e2e@example.com", password: "e2e-password-2026"}
export const TARGET = `http://localhost:${process.env.E2E_TARGET_PORT || "4110"}`

export async function login(page: Page) {
  await page.goto("/login")
  await page.fill("#email", ADMIN.email)
  await page.fill("#password", ADMIN.password)
  await page.click("button[type=submit]")
  await page.waitForURL("**/admin")
  await connected(page)
}

/** Waits until the LiveView on the page is connected. */
export async function connected(page: Page) {
  await expect(page.locator(".phx-connected").first()).toBeAttached()
}

export function unique(prefix: string) {
  return `${prefix} ${Date.now().toString(36)}${Math.floor(Math.random() * 1000)}`
}

/** Adds a service through the UI and returns its details URL. */
export async function addService(page: Page, name: string, url: string, opts: {public?: boolean; interval?: number} = {}) {
  await page.goto("/admin/services/new")
  await connected(page)
  await page.fill("#svc-name", name)
  await page.fill("#svc-url", url)
  await page.check(`#svc-interval-${opts.interval ?? 60}`)
  if (opts.public) await page.check("#svc-public")
  await page.click("#save-service")
  await page.waitForURL("**/admin")
  await connected(page)
  await page.getByRole("link", {name, exact: true}).first().click()
  await page.waitForURL(/\/admin\/services\/\d+$/)
  await connected(page)
  return page.url()
}

/** Runs e2e/scripts/scenario.exs in a separate VM against the e2e database. */
export function scenario(name: string) {
  execFileSync("mix", ["run", "--no-start", "e2e/scripts/scenario.exs", name], {
    cwd: path.resolve(__dirname, "../.."),
    env: {
      ...process.env,
      MIX_ENV: "dev",
      POSTGRES_DB: process.env.POSTGRES_DB || "uptime_monitor_e2e",
      DEMO_TARGET_URL: TARGET,
      SSRF_ALLOWLIST: "localhost",
    },
    stdio: "pipe",
  })
}
