/**
 * Discord Developer Portal — open your application, capture evidence, touch Bot + OAuth2 URL generator.
 *
 * Auth (pick one):
 *   1) DISCORD_DEV_PORTAL_STORAGE_STATE=./discord-devportal-state.json  (recommended; log in once via codegen)
 *   2) DISCORD_DEV_PORTAL_EMAIL + DISCORD_DEV_PORTAL_PASSWORD  (fragile; 2FA / captcha = skip)
 *
 * App: https://discord.com/developers/applications/1487798260339966023/information
 */
import * as fs from "fs";
import * as path from "path";
import { test, expect } from "@playwright/test";

const APP_ID = (process.env.DISCORD_APPLICATION_ID || "1487798260339966023").trim();
const DEV_EMAIL = (process.env.DISCORD_DEV_PORTAL_EMAIL || "").trim();
const DEV_PASSWORD = (process.env.DISCORD_DEV_PORTAL_PASSWORD || "").trim();
const STORAGE =
  (process.env.DISCORD_DEV_PORTAL_STORAGE_STATE || process.env.DISCORD_PLAYWRIGHT_STORAGE_STATE || "").trim();

const evidenceDir = path.join(__dirname, "..", "..", "..", "evidence", "discord_closure", "dev_portal");

function useStorage(): string | undefined {
  if (STORAGE && fs.existsSync(STORAGE)) return STORAGE;
  return undefined;
}

// Use saved session when file exists (same pattern as discord_membrane_smoke).
const st = useStorage();
if (st) {
  test.use({ storageState: st });
}

test.describe("Discord Developer Portal — GaiaFTCL app setup witness", () => {
  test("open Information, Bot, OAuth2 URL generator + screenshots", async ({ page }, testInfo) => {
    test.setTimeout(180_000);

    if (!st && (!DEV_EMAIL || !DEV_PASSWORD)) {
      test.skip(
        true,
        "Set DISCORD_DEV_PORTAL_STORAGE_STATE (or DISCORD_PLAYWRIGHT_STORAGE_STATE) after `playwright codegen https://discord.com/login --save-storage=...`, OR set DISCORD_DEV_PORTAL_EMAIL + DISCORD_DEV_PORTAL_PASSWORD",
      );
    }

    fs.mkdirSync(evidenceDir, { recursive: true });
    const tag = new Date().toISOString().replace(/[:.]/g, "-");

    if (!st && DEV_EMAIL && DEV_PASSWORD) {
      await page.goto("https://discord.com/login", { waitUntil: "domcontentloaded", timeout: 60_000 });
      const email = page.locator('input[name="email"], input[type="email"]').first();
      const pw = page.locator('input[name="password"], input[type="password"]').first();
      await email.fill(DEV_EMAIL);
      await pw.fill(DEV_PASSWORD);
      await page.locator('button[type="submit"]').first().click();
      await page.waitForTimeout(3000);
      const mfa = page.getByText(/mfa|two-factor|2fa|authenticator/i).first();
      if (await mfa.isVisible().catch(() => false)) {
        await page.screenshot({ path: path.join(evidenceDir, `${tag}-mfa-required.png`), fullPage: true });
        test.skip(true, "2FA / MFA required — use DISCORD_DEV_PORTAL_STORAGE_STATE after logging in manually once");
      }
    }

    const infoUrl = `https://discord.com/developers/applications/${APP_ID}/information`;
    const res = await page.goto(infoUrl, { waitUntil: "domcontentloaded", timeout: 90_000 });
    expect(res?.ok() ?? false).toBeTruthy();

    if (page.url().includes("/login")) {
      await page.screenshot({ path: path.join(evidenceDir, `${tag}-still-on-login.png`), fullPage: true });
      test.skip(true, "Still on login — fix storage state or credentials");
    }

    await page.waitForTimeout(2000);
    await page.screenshot({ path: path.join(evidenceDir, `${tag}-information.png`), fullPage: true });

    const botUrl = `https://discord.com/developers/applications/${APP_ID}/bot`;
    await page.goto(botUrl, { waitUntil: "domcontentloaded", timeout: 60_000 });
    await page.waitForTimeout(1500);
    await page.screenshot({ path: path.join(evidenceDir, `${tag}-bot.png`), fullPage: true });

    const oauthUrl = `https://discord.com/developers/applications/${APP_ID}/oauth2/url-generator`;
    await page.goto(oauthUrl, { waitUntil: "domcontentloaded", timeout: 60_000 });
    await page.waitForTimeout(1500);

    // Prefer scopes: bot + applications.commands (matches membrane slash sync).
    const botScope = page.getByRole("checkbox", { name: /bot/i }).first();
    const cmdScope = page.getByRole("checkbox", { name: /applications\.commands|commands/i }).first();
    if (await botScope.isVisible().catch(() => false)) {
      await botScope.check().catch(() => {});
    }
    if (await cmdScope.isVisible().catch(() => false)) {
      await cmdScope.check().catch(() => {});
    }

    await page.screenshot({ path: path.join(evidenceDir, `${tag}-oauth2-url-generator.png`), fullPage: true });

    const summary = {
      app_id: APP_ID,
      test: testInfo.title,
      evidence_dir: evidenceDir,
      screenshots: [`${tag}-information.png`, `${tag}-bot.png`, `${tag}-oauth2-url-generator.png`],
      urls: { infoUrl, botUrl, oauthUrl },
    };
    fs.writeFileSync(path.join(evidenceDir, `${tag}-summary.json`), JSON.stringify(summary, null, 2), "utf-8");

    await expect(page.locator("body")).toBeVisible();
  });
});
