import {defineConfig, devices} from "@playwright/test"

const port = process.env.E2E_PORT || "4010"
export const baseURL = `http://localhost:${port}`

// The suite starts its own server on a fresh database (scripts/server.sh).
// `e2e` runs the end-to-end tests, `screenshots` captures the screens and
// states of the design review into artifacts/screenshots.
export default defineConfig({
  testDir: "./tests",
  timeout: 60_000,
  expect: {timeout: 15_000},
  fullyParallel: false,
  workers: 1,
  reporter: [["list"]],
  use: {baseURL, trace: "retain-on-failure", ...devices["Desktop Chrome"], viewport: {width: 1280, height: 900}},
  projects: [
    {name: "e2e", testMatch: /.*\.e2e\.ts/},
    {name: "screenshots", testMatch: /screenshots\.ts/},
  ],
  webServer: {
    command: "./scripts/server.sh",
    url: `${baseURL}/health`,
    timeout: 240_000,
    reuseExistingServer: false,
    stdout: "ignore",
    stderr: "pipe",
  },
})
