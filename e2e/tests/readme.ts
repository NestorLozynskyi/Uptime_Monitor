// Screenshots for README.md, from the Docker Compose demo (see playwright.readme.config.ts).
import {Browser, Page, expect, test} from "@playwright/test"
import path from "node:path"
import {connected} from "./helpers"

const OUT = path.resolve(__dirname, "../../docs/screenshots")
const DEMO = {email: process.env.DEMO_EMAIL || "admin@example.com", password: process.env.DEMO_PASSWORD || "uptime-demo-2026"}
const TEST_ARTIFACTS = /Realtime|Slow API|Slow endpoint|E2E|Staging/

async function open(browser: Browser, theme: "light" | "dark", width: number) {
  const context = await browser.newContext({viewport: {width, height: width < 768 ? 844 : 900}, colorScheme: theme})
  await context.addInitScript(t => localStorage.setItem("um-theme", t), theme)
  const page = await context.newPage()
  await page.goto("/login")
  await page.fill("#email", DEMO.email)
  await page.fill("#password", DEMO.password)
  await page.click("button[type=submit]")
  await page.waitForURL("**/admin")
  await connected(page)
  await expect(page.locator("#services")).not.toContainText(TEST_ARTIFACTS)
  return {context, page}
}

async function save(page: Page, file: string) {
  await page.evaluate(() => document.fonts.ready)
  await page.waitForTimeout(400)
  await page.screenshot({path: `${OUT}/${file}`, fullPage: true})
}

test("README screenshots", async ({browser}) => {
  let {context, page} = await open(browser, "light", 1280)
  await save(page, "dashboard-light.png")
  await page.goto("/status")
  await connected(page)
  await save(page, "status-light.png")
  await context.close()

  ;({context, page} = await open(browser, "dark", 1280))
  await page.locator("#services a.svc-name", {hasText: "Billing Service"}).click()
  await page.locator("#response-chart canvas").waitFor()
  await save(page, "service-dark.png")
  await context.close()

  ;({context, page} = await open(browser, "dark", 390))
  await save(page, "dashboard-mobile-dark.png")
  await context.close()
})
