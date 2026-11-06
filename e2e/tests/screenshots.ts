// Captures every screen and state of the design review from the running app
// (real data: demo services seeded with 30 days of history + live checks).
// Output: e2e/artifacts/screenshots/<screen>--<state>--<theme>--<width>.png
import {Browser, BrowserContext, Page, expect, test} from "@playwright/test"
import path from "node:path"
import {TARGET, addService, connected, login, scenario} from "./helpers"

const OUT = path.resolve(__dirname, "../artifacts/screenshots")
const THEMES = ["light", "dark"] as const
type Theme = (typeof THEMES)[number]

test.describe.configure({mode: "serial"})
test.setTimeout(600_000)

async function open(browser: Browser, theme: Theme, width: number): Promise<{context: BrowserContext; page: Page}> {
  const context = await browser.newContext({
    viewport: {width, height: width < 768 ? 844 : width < 1024 ? 1112 : 900},
    hasTouch: width < 1024,
    colorScheme: theme,
  })
  await context.addInitScript(t => localStorage.setItem("um-theme", t), theme)
  return {context, page: await context.newPage()}
}

async function shot(page: Page, screen: string, state: string, theme: Theme, opts: {fullPage?: boolean} = {}) {
  const width = page.viewportSize()!.width
  await page.evaluate(() => document.fonts.ready)
  await page.waitForTimeout(300)
  await page.screenshot({path: `${OUT}/${screen}--${state}--${theme}--${width}.png`, fullPage: opts.fullPage ?? true})
}

async function serviceUrl(page: Page, name: string) {
  await page.goto("/admin")
  await connected(page)
  return page.locator("#services a.svc-name", {hasText: name}).first().getAttribute("href")
}

test("main screens in both themes at desktop, tablet and mobile widths", async ({browser}) => {
  // Clean demo data, independent of e2e tests that may have run before.
  scenario("reset")
  for (const theme of THEMES) {
    for (const width of [1280, 1024, 834, 390]) {
      const {context, page} = await open(browser, theme, width)
      const full = width === 1280 || width === 390
      if (width === 1024 && theme === "dark") { await context.close(); continue }

      if (full) {
        await page.goto("/login")
        await shot(page, "01-login", "default", theme)
      }
      await login(page)
      await expect(page.locator("#services")).toBeVisible()
      await shot(page, "02-dashboard", "live-with-incidents", theme)

      // Service with an ongoing incident (Billing Service → HTTP 503).
      const billing = await serviceUrl(page, "Billing Service")
      await page.goto(billing!)
      await connected(page)
      await page.locator("#response-chart canvas").waitFor()
      await shot(page, "03-service", "24h-ongoing-incident", theme)

      if (full) {
        const search = await serviceUrl(page, "Search Cluster")
        await page.goto(`${search}?period=7d`)
        await connected(page)
        await page.locator("#response-chart canvas").waitFor()
        await shot(page, "03-service", "7d", theme)
        await page.goto(`${search}?period=30d`)
        await connected(page)
        await page.locator("#response-chart canvas").waitFor()
        await shot(page, "03-service", "30d", theme)

        await page.goto("/admin/services/new")
        await connected(page)
        await shot(page, "04-service-form", "add", theme)
        await page.goto(`${billing}/edit`)
        await connected(page)
        await shot(page, "04-service-form", "edit", theme)

        await page.goto("/status")
        await connected(page)
        await shot(page, "05-status", "demo-data", theme)

        if (width === 390) {
          await page.goto("/admin")
          await connected(page)
          await page.click("#menu-button")
          await expect(page.locator("#menu-sheet")).toBeVisible()
          await shot(page, "06-navigation", "mobile-menu-open", theme, {fullPage: false})
        } else {
          await page.goto("/admin")
          await connected(page)
          await page.locator("header.topbar").screenshot({path: `${OUT}/06-navigation--desktop-topbar--${theme}--${width}.png`})
        }
      }
      await context.close()
    }
  }
})

test("states", async ({browser}) => {
  for (const theme of THEMES) {
    for (const width of [1280, 390]) {
      const {context, page} = await open(browser, theme, width)

      // Login error
      await page.goto("/login")
      await page.fill("#email", "e2e@example.com")
      await page.fill("#password", "wrong-password")
      await page.click("button[type=submit]")
      await expect(page.locator("#login-error")).toBeVisible()
      await shot(page, "01-login", "invalid-credentials", theme)

      await login(page)

      // Form validation errors incl. the SSRF rejection
      await page.goto("/admin/services/new")
      await connected(page)
      await page.fill("#svc-url", "http://192.168.1.10/admin")
      await page.click("#save-service")
      await expect(page.locator("#error-summary")).toBeVisible()
      await page.evaluate(() => window.scrollTo(0, 0))
      await shot(page, "04-service-form", "errors-ssrf", theme)

      // Delete confirmation
      const docs = await serviceUrl(page, "Documentation")
      await page.goto(docs!)
      await connected(page)
      await page.click("#delete-service")
      await expect(page.locator("#delete-dialog")).toBeVisible()
      await shot(page, "03-service", "delete-dialog", theme, {fullPage: false})
      await page.locator("#delete-dialog").getByRole("button", {name: "Cancel"}).click()

      // Check now in progress (slow endpoint keeps the state visible)
      const slowName = `Slow endpoint ${theme} ${width}`
      await addService(page, slowName, `${TARGET}/delay/9000`)
      await shot(page, "03-service", "not-checked-yet", theme)
      await page.click("#check-now")
      await expect(page.locator("#checking-row")).toBeVisible()
      await shot(page, "03-service", "checking", theme)
      await page.goto("/admin")
      await connected(page)
      const row = page.locator("#services tr", {hasText: slowName})
      await row.getByRole("button", {name: "Check now"}).click()
      await expect(row).toHaveClass(/is-checking/)
      await shot(page, "02-dashboard", "checking-row", theme)
      await expect(row).not.toHaveClass(/is-checking/, {timeout: 20_000})
      await context.close()
    }
  }

  // Reconnecting (live connection lost)
  for (const theme of THEMES) {
    for (const width of [1280, 390]) {
      const {context, page} = await open(browser, theme, width)
      let socket: {close: () => Promise<void>} | null = null
      let blocked = false
      await page.routeWebSocket(/\/live\/websocket/, ws => {
        if (blocked) { ws.close(); return }
        ws.connectToServer(); socket = ws
      })
      await page.route(/\/live\/longpoll/, r => (blocked ? r.abort() : r.continue()))
      await login(page)
      blocked = true
      await socket!.close()
      await expect(page.locator("#reconnect-banner")).toBeVisible()
      await shot(page, "02-dashboard", "reconnecting", theme)
      await context.close()
    }
  }
})

test("public status page states", async ({browser}) => {
  for (const state of ["partial", "major", "degraded", "operational"]) {
    scenario(`public:${state}`)
    for (const theme of THEMES) {
      for (const width of [1280, 390]) {
        const {context, page} = await open(browser, theme, width)
        await page.goto("/status")
        await connected(page)
        await shot(page, "05-status", state, theme)
        await context.close()
      }
    }
  }

  // A service that has never been checked, then no services at all.
  scenario("pending")
  for (const theme of THEMES) {
    const {context, page} = await open(browser, theme, 1280)
    await login(page)
    await page.goto((await serviceUrl(page, "Staging"))!)
    await connected(page)
    await shot(page, "03-service", "not-checked-yet-staging", theme)
    await page.goto("/admin")
    await connected(page)
    await shot(page, "02-dashboard", "not-checked-yet-row", theme)
    await context.close()
  }

  scenario("empty")
  for (const theme of THEMES) {
    for (const width of [1280, 390]) {
      const {context, page} = await open(browser, theme, width)
      await page.goto("/status")
      await connected(page)
      await shot(page, "05-status", "empty", theme)
      await login(page)
      await expect(page.locator("#empty-state")).toBeVisible()
      await shot(page, "02-dashboard", "empty", theme)
      await context.close()
    }
  }
})
