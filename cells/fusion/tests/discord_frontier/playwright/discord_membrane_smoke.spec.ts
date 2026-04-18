import { test, expect } from "@playwright/test";

const guildChannelUrl = (process.env.DISCORD_WEB_TEST_GUILD_URL || "").trim();
const storageState = (process.env.DISCORD_PLAYWRIGHT_STORAGE_STATE || "").trim();

test.describe("Discord membrane — web smoke", () => {
  test("discord.com loads (unauthenticated surface)", async ({ page }) => {
    const res = await page.goto("https://discord.com/login", {
      waitUntil: "domcontentloaded",
      timeout: 45_000,
    });
    expect(res?.ok() ?? false).toBeTruthy();
    await expect(page.locator("body")).toBeVisible();
  });

  test("guild channel URL loads when logged in (storage state + URL required)", async ({
    page,
  }) => {
    test.skip(!guildChannelUrl, "Set DISCORD_WEB_TEST_GUILD_URL to a channel deep link");
    test.skip(!storageState, "Set DISCORD_PLAYWRIGHT_STORAGE_STATE to saved auth JSON");

    const res = await page.goto(guildChannelUrl, {
      waitUntil: "domcontentloaded",
      timeout: 90_000,
    });
    expect(res?.ok() ?? false).toBeTruthy();
    await expect(page.locator("body")).toBeVisible();
    // Message list or channel chrome — tolerant selectors
    const maybeMain = page.locator('[class*="chat"], [class*="messages"], main, [role="textbox"]');
    await expect(maybeMain.first()).toBeVisible({ timeout: 60_000 });
  });
});
