import {expect, test} from "@playwright/test"
import {ADMIN, TARGET, addService, connected, login, unique} from "./helpers"

test.describe("authentication", () => {
  test("signs in with valid credentials and signs out", async ({page}) => {
    await login(page)
    await expect(page.getByRole("heading", {name: "Dashboard"})).toBeVisible()
    await page.getByRole("link", {name: "Sign out"}).click()
    await page.waitForURL("**/login")
    await page.goto("/admin")
    await page.waitForURL("**/login")
  })

  test("shows errors for empty fields and wrong credentials", async ({page}) => {
    await page.goto("/login")
    await page.click("button[type=submit]")
    await expect(page.locator("#email-error")).toHaveText("Enter your email.")
    await expect(page.locator("#password-error")).toHaveText("Enter your password.")

    await page.fill("#email", ADMIN.email)
    await page.fill("#password", "wrong-password")
    await page.click("button[type=submit]")
    await expect(page.locator("#login-error")).toContainText("Incorrect email or password")
    await expect(page.locator("#email")).toHaveValue(ADMIN.email)
  })

  test("admin routes require a session; the public page does not", async ({page}) => {
    for (const path of ["/admin", "/admin/services/new", "/admin/services/1", "/admin/services/1/edit"]) {
      await page.goto(path)
      await expect(page).toHaveURL(/\/login$/)
    }
    await page.goto("/status")
    await expect(page.getByText("Service status").first()).toBeVisible()
    await page.goto("/")
    await expect(page).toHaveURL(/\/status$/)
  })
})

test.describe("services", () => {
  test.beforeEach(async ({page}) => login(page))

  test("create, edit and delete a service; SSRF rejection", async ({page}) => {
    await page.goto("/admin/services/new")
    await connected(page)
    await expect(page.locator("#svc-interval-5")).toBeChecked()

    // Empty name + private address: errors under fields and a summary.
    await page.fill("#svc-url", "http://192.168.1.10/admin")
    await page.click("#save-service")
    await expect(page.locator("#error-summary")).toContainText("Fix 2 problems to continue")
    await expect(page.locator("#svc-name-error")).toHaveText("Enter a name for this service.")
    await expect(page.locator("#svc-url-error")).toHaveText(
      "This address is not allowed. Private, local and internal network addresses can’t be monitored.",
    )
    await page.fill("#svc-url", "http://169.254.169.254/latest")
    await page.locator("#svc-url").blur()
    await expect(page.locator("#svc-url-error")).toContainText("This address is not allowed.")

    // Valid: localhost is allowlisted for the e2e demo target only.
    const name = unique("E2E Website")
    await page.fill("#svc-name", name)
    await page.fill("#svc-url", `${TARGET}/ok`)
    await page.check("#svc-interval-15")
    await page.click("#save-service")
    await page.waitForURL("**/admin")
    const row = page.locator("#services tr", {hasText: name})
    await expect(row).toContainText("Not checked yet")
    await expect(row).toContainText("Every 15 min")
    await expect(row).toContainText("Private")

    // Edit
    await page.locator("#services a.svc-name", {hasText: name}).click()
    await page.getByRole("link", {name: "Edit"}).click()
    await expect(page.getByRole("heading", {name: "Edit service"})).toBeVisible()
    await connected(page)
    await page.fill("#svc-name", `${name} v2`)
    await page.check("#svc-public")
    await page.click("#save-service")
    await page.waitForURL(/\/admin\/services\/\d+$/)
    await expect(page.getByRole("heading", {name: `${name} v2`})).toBeVisible()
    await expect(page.locator("#svc-head")).toContainText("Shown on status page")

    // Delete with confirmation (cancel first)
    await connected(page)
    await page.click("#delete-service")
    const dialog = page.locator("#delete-dialog")
    await expect(dialog).toBeVisible()
    await expect(dialog).toContainText(`Delete “${name} v2”?`)
    await dialog.getByRole("button", {name: "Cancel"}).click()
    await expect(dialog).toHaveCount(0)
    await page.click("#delete-service")
    await page.click("#confirm-delete")
    await page.waitForURL("**/admin")
    await expect(page.locator("#services")).not.toContainText(`${name} v2`)
  })

  test("check now shows the checking state and records a manual check", async ({page}) => {
    const name = unique("Slow API")
    await addService(page, name, `${TARGET}/delay/1500`)
    await expect(page.locator("#service-status")).toHaveText("Not checked yet")
    await expect(page.locator(".chart-empty")).toContainText("No checks yet")

    await page.click("#check-now")
    await expect(page.locator("#svc-head")).toContainText("Checking now…")
    await expect(page.locator("#checking-row")).toContainText("Checking…")
    await expect(page.locator("#check-now")).toHaveAttribute("aria-busy", "true")

    await expect(page.locator("#service-status")).toHaveText("Up")
    await expect(page.locator("#checking-row")).toHaveCount(0)
    await expect(page.locator("#recent-checks tbody tr").first()).toContainText("Manual")
    await expect(page.locator("#recent-checks tbody tr").first()).toContainText("200")
    await expect(page.locator("#response-chart canvas")).toBeVisible()

    // From the dashboard too
    await page.goto("/admin")
    await connected(page)
    const row = page.locator("#services tr", {hasText: name})
    await row.getByRole("button", {name: "Check now"}).click()
    await expect(row).toHaveClass(/is-checking/)
    await expect(row).not.toHaveClass(/is-checking/)
  })

  test("period switch selects the period and changes the data", async ({page}) => {
    await page.getByRole("link", {name: "Marketing Website", exact: true}).click()
    await connected(page)
    const radio = (p: string) => page.locator(`button[data-period="${p}"]`)
    await expect(radio("24h")).toHaveAttribute("aria-checked", "true")
    await expect(page.locator("#availability .bar")).toHaveCount(48)
    await expect(page.locator("#chart-title")).toContainText("last 24 hours")

    await radio("7d").click()
    await expect(page).toHaveURL(/period=7d/)
    await expect(radio("7d")).toHaveAttribute("aria-checked", "true")
    await expect(radio("24h")).toHaveAttribute("aria-checked", "false")
    await expect(page.locator("#availability .bar")).toHaveCount(42)
    await expect(page.locator("#chart-title")).toContainText("last 7 days")

    await radio("7d").focus()
    await page.keyboard.press("ArrowRight")
    await expect(radio("30d")).toHaveAttribute("aria-checked", "true")
    await expect(page.locator("#availability .bar")).toHaveCount(30)
    await expect(page.locator("#availability")).toContainText("30 days ago")
    await expect(page.locator("#response-chart")).toHaveAttribute("data-period", "30d")
  })
})

test("public status page shows only public services, without URLs", async ({page}) => {
  await page.goto("/status")
  await connected(page)
  const list = page.locator("#public-services")
  await expect(list).toContainText("Marketing Website")
  await expect(list).toContainText("Public API")
  // Private demo services and every URL stay hidden.
  for (const hidden of ["Billing Service", "Auth Service", "Legacy Portal", "Reports Worker", "localhost:", "http"]) {
    await expect(page.locator("main")).not.toContainText(hidden)
  }
  await expect(page.locator("main")).not.toContainText("Check now")
  await expect(list.locator("li").first().locator(".bar")).toHaveCount(30)
  await expect(page.locator("#overall-status")).toBeVisible()
})

test("theme switch overrides the system theme and persists", async ({browser}) => {
  const context = await browser.newContext({colorScheme: "dark"})
  const page = await context.newPage()
  await page.goto("/status")
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark")
  await expect(page.locator("html")).toHaveAttribute("data-theme-pref", "system")

  await page.click('#theme-switch [data-theme-set="light"]')
  await expect(page.locator("html")).toHaveAttribute("data-theme", "light")
  await expect(page.locator('#theme-switch [data-theme-set="light"]')).toHaveAttribute("aria-pressed", "true")
  const bg = await page.evaluate(() => getComputedStyle(document.body).backgroundColor)
  expect(bg).toBe("rgb(246, 247, 249)")

  // Persists across pages and reloads, applied before first paint.
  await page.goto("/login")
  await expect(page.locator("html")).toHaveAttribute("data-theme", "light")
  await page.click('#theme-switch [data-theme-set="dark"]')
  await page.reload()
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark")
  expect(await page.evaluate(() => localStorage.getItem("um-theme"))).toBe("dark")

  await page.click('#theme-switch [data-theme-set="system"]')
  await expect(page.locator("html")).toHaveAttribute("data-theme-pref", "system")
  await context.close()
})

test("mobile navigation uses the menu sheet", async ({browser}) => {
  const context = await browser.newContext({viewport: {width: 390, height: 844}, hasTouch: true})
  const page = await context.newPage()
  await login(page)
  await expect(page.locator(".nav-main")).toBeHidden()
  await expect(page.locator("#theme-switch")).toBeHidden()
  await page.click("#menu-button")
  const sheet = page.locator("#menu-sheet")
  await expect(sheet).toBeVisible()
  await expect(sheet.getByRole("link", {name: "Dashboard"})).toBeVisible()
  await expect(sheet.getByRole("link", {name: /Status page/})).toHaveAttribute("href", "/status")
  await sheet.locator('[data-theme-set="dark"]').click()
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark")
  await sheet.getByRole("button", {name: "Close menu"}).click()
  await expect(sheet).toBeHidden()
  await page.click("#menu-button")
  await sheet.getByRole("link", {name: "Sign out"}).click()
  await page.waitForURL("**/login")
  await context.close()
})

test("real-time updates on the dashboard, details and public page", async ({browser}) => {
  const context = await browser.newContext()
  const admin = await context.newPage()
  await login(admin)
  const name = unique("Realtime")
  const detailsUrl = await addService(admin, name, `${TARGET}/ok`, {public: true})

  const dashboard = await context.newPage()
  await dashboard.goto("/admin")
  await connected(dashboard)
  const details = await context.newPage()
  await details.goto(detailsUrl)
  await connected(details)
  const publicPage = await browser.newPage() // separate session, not signed in
  await publicPage.goto("/status")
  await connected(publicPage)
  const publicRow = publicPage.locator("#public-services li", {hasText: name})
  await expect(publicRow).toContainText("No data")

  // Make the service fail and check it from the admin tab.
  await admin.getByRole("link", {name: "Edit"}).click()
  await connected(admin)
  await admin.fill("#svc-url", `${TARGET}/status/503`)
  await admin.click("#save-service")
  await admin.waitForURL(/\/admin\/services\/\d+$/)
  await connected(admin)
  await admin.click("#check-now")
  await expect(admin.locator("#service-status")).toHaveText("Down")

  // Other tabs update without reload.
  await expect(dashboard.locator("#services tr", {hasText: name})).toContainText("Down")
  await expect(dashboard.locator("#services tr", {hasText: name})).toContainText("HTTP 503")
  await expect(details.locator("#service-status")).toHaveText("Down")
  await expect(details.locator("#recent-checks")).toContainText("503")
  await expect(publicRow).toContainText("Down")
  await expect(publicPage.locator("main")).not.toContainText("localhost")

  // Three failures in a row open an incident everywhere.
  await admin.click("#check-now")
  await expect(admin.locator("#check-now")).toHaveAttribute("aria-busy", "false")
  await admin.click("#check-now")
  await expect(details.locator("#incident-banner")).toContainText("Incident ongoing for")
  await expect(dashboard.locator("#active-incidents")).toContainText(name)

  await publicPage.close()
  await context.close()
})

test("shows the reconnecting banner when the live connection is lost", async ({page}) => {
  let socket: {close: () => Promise<void>} | null = null
  let blocked = false
  await page.routeWebSocket(/\/live\/websocket/, ws => {
    if (blocked) { ws.close(); return }
    ws.connectToServer()
    socket = ws
  })
  await page.route(/\/live\/longpoll/, route => (blocked ? route.abort() : route.continue()))

  await login(page)
  await expect(page.locator("#reconnect-banner")).toBeHidden()
  await expect(page.locator(".live-online").first()).toBeVisible()

  blocked = true
  await socket!.close()
  await expect(page.locator("#reconnect-banner")).toBeVisible()
  await expect(page.locator("#reconnect-banner")).toContainText("Connection lost. Reconnecting…")
  await expect(page.locator(".live-offline").first()).toContainText("Reconnecting…")

  blocked = false
  await expect(page.locator("#reconnect-banner")).toBeHidden({timeout: 30_000})
  await expect(page.locator(".live-online").first()).toBeVisible()
})

test.describe("responsive layout", () => {
  for (const width of [834, 768, 1024]) {
    test(`no horizontal overflow at ${width} px; Check now is clickable`, async ({browser}) => {
      const context = await browser.newContext({viewport: {width, height: 1000}})
      const page = await context.newPage()
      await login(page)
      const overflow = () => page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)
      expect(await overflow()).toBeLessThanOrEqual(0)
      const wrap = page.locator("#services").locator("xpath=..")
      expect(await wrap.evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(0)

      const row = page.locator("#services tr", {hasText: "Marketing Website"})
      const button = row.getByRole("button", {name: "Check now"})
      await expect(button).toBeVisible()
      await expect(row.getByRole("link", {name: "Marketing Website details"})).toBeVisible()
      await button.click() // fails if covered or outside the viewport
      await expect(row).not.toHaveClass(/is-checking/)

      await row.locator("a.svc-name").click()
      await page.locator("#response-chart canvas").waitFor()
      expect(await overflow()).toBeLessThanOrEqual(0)
      for (const table of await page.locator(".tbl-wrap").all()) {
        expect(await table.evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(0)
      }
      await page.click("#check-now")
      await expect(page.locator("#check-now")).toHaveAttribute("aria-busy", "false")
      await context.close()
    })
  }

  for (const [width, rows] of [[390, 10], [834, 20], [1280, 20]] as const) {
    test(`recent checks show ${rows} rows at ${width} px`, async ({browser}) => {
      const context = await browser.newContext({viewport: {width, height: 900}})
      const page = await context.newPage()
      await login(page)
      // Public API answers in ~3.5 s, so the "Checking…" row stays visible.
      await page.locator("#services a.svc-name", {hasText: "Public API"}).click()
      await connected(page)
      const visible = page.locator("#recent-checks tbody tr:visible")
      await expect(visible).toHaveCount(rows)

      // The "Checking…" row counts toward the limit.
      const service = await page.locator("#svc-head h1").innerText()
      expect(service).toBe("Public API")
      await page.click("#check-now")
      await expect(page.locator("#checking-row")).toBeVisible()
      await expect(visible).toHaveCount(rows)
      await expect(page.locator("#checking-row")).toHaveCount(0)
      await expect(visible).toHaveCount(rows)
      await expect(visible.first()).toContainText("Manual")
      await context.close()
    })
  }
})

test("response-time axis uses round steps", async ({page}) => {
  await login(page)
  for (const name of ["Marketing Website", "Public API", "Reports Worker"]) {
    await page.goto("/admin")
    await connected(page)
    await page.locator("#services a.svc-name", {hasText: name}).click()
    await page.locator("#response-chart canvas").waitFor()
    const ticks: number[] = JSON.parse((await page.locator("#response-chart canvas").getAttribute("data-y-ticks"))!)
    expect(ticks[0]).toBe(0)
    const step = ticks[1] - ticks[0]
    const mantissa = step / Math.pow(10, Math.floor(Math.log10(step)))
    expect([1, 2, 2.5, 5]).toContain(mantissa)
    for (let i = 1; i < ticks.length; i++) expect(ticks[i] - ticks[i - 1]).toBeCloseTo(step)
  }
})
