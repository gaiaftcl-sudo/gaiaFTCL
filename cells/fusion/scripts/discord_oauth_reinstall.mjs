#!/usr/bin/env node
import fs from "fs";
import os from "os";
import path from "path";
import { chromium } from "playwright";

function requireEnv(name) {
  const v = process.env[name]?.trim();
  if (!v) {
    throw new Error(`Missing ${name}`);
  }
  return v;
}

const guild = requireEnv("DISCORD_GUILD_ID");
const appIds = (process.env.DISCORD_APP_IDS || "").split(",").map((s) => s.trim()).filter(Boolean);
if (appIds.length === 0) {
  throw new Error("Missing DISCORD_APP_IDS (comma-separated app IDs)");
}

const perms = process.env.DISCORD_BOT_PERMISSIONS?.trim() || "8";
const storagePath =
  process.env.DISCORD_PLAYWRIGHT_STORAGE_STATE?.trim() ||
  path.join(os.homedir(), ".playwright-discord", "storage-gaiaftcl.json");
if (!fs.existsSync(storagePath)) {
  throw new Error(`Missing storage state: ${storagePath}`);
}

const browser = await chromium.launch({ headless: false });
const context = await browser.newContext({ storageState: storagePath });
const page = await context.newPage();

for (const appId of appIds) {
  const url = `https://discord.com/api/oauth2/authorize?client_id=${appId}&scope=bot%20applications.commands&permissions=${perms}&guild_id=${guild}&disable_guild_select=true`;
  console.log(`OPEN ${url}`);
  await page.goto(url, { waitUntil: "domcontentloaded", timeout: 120000 });
  await page.waitForTimeout(1500);

  const authorize = page.getByRole("button", { name: /authorize|continue/i }).first();
  const already = page.getByText(/already|authorized|installed/i).first();
  if (await authorize.isVisible().catch(() => false)) {
    await authorize.click();
    await page.waitForTimeout(2000);
    console.log(`OAUTH_ATTEMPT app_id=${appId} action=clicked_authorize`);
  } else if (await already.isVisible().catch(() => false)) {
    console.log(`OAUTH_ATTEMPT app_id=${appId} action=already_present`);
  } else {
    console.log(`OAUTH_ATTEMPT app_id=${appId} action=no_authorize_ui`);
  }
}

await context.close();
await browser.close();
console.log("DONE oauth reinstall attempts");

