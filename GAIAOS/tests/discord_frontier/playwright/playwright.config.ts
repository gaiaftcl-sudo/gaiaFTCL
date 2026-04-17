import { defineConfig, devices } from "@playwright/test";

/**
 * Discord web smoke — optional logged-in state via DISCORD_PLAYWRIGHT_STORAGE_STATE.
 * Generate once: npx playwright codegen discord.com --save-storage=discord-state.json
 */
export default defineConfig({
  testDir: ".",
  forbidOnly: !!process.env.CI,
  retries: 0,
  workers: 1,
  reporter: [["list"]],
  use: {
    ...devices["Desktop Chrome"],
    trace: "on-first-retry",
    screenshot: "only-on-failure",
    storageState: process.env.DISCORD_PLAYWRIGHT_STORAGE_STATE || undefined,
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
