import {defineConfig, devices} from "@playwright/test"

// README screenshots are taken from the Docker Compose demo (clean demo data,
// no test services): start it with `docker compose up` first, then
// `npm run readme-screenshots`. Output: docs/screenshots/*.png
export default defineConfig({
  testDir: "./tests",
  testMatch: /readme\.ts/,
  timeout: 120_000,
  workers: 1,
  reporter: [["list"]],
  use: {...devices["Desktop Chrome"], baseURL: process.env.README_BASE_URL || "http://localhost:4000"},
})
