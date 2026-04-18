# Discord membrane — Playwright (web)

Runs against **Discord in the browser** on the Mac limb (or CI). Complements **AppleScript** desktop tests in `README_PHASE6_APPLESCRIPT.md`.

## Run

From repo root:

```bash
bash cells/fusion/scripts/run_discord_membrane_playwright.sh
```

Or:

```bash
cd cells/fusion/tests/discord_frontier/playwright && npm install && npx playwright install chromium && npx playwright test
```

## Optional — logged-in guild check

1. On a machine with a browser: generate storage once (do not commit the file):

   ```bash
   cd cells/fusion/tests/discord_frontier/playwright
   npx playwright codegen https://discord.com/login --save-storage=discord-state.json
   ```

2. Export and re-run:

   ```bash
   export DISCORD_PLAYWRIGHT_STORAGE_STATE="$PWD/discord-state.json"
   export DISCORD_WEB_TEST_GUILD_URL="https://discord.com/channels/<GUILD_ID>/<CHANNEL_ID>"
   bash cells/fusion/scripts/run_discord_membrane_playwright.sh
   ```

3. Add `discord-state.json` to `.gitignore` (already ignored by pattern in this folder).

## Developer Portal (your application)

Target: [Developer Portal — application information](https://discord.com/developers/applications/1487798260339966023/information)

1. **Recommended:** save a logged-in storage file (includes developer portal when you use the same Discord account):

   ```bash
   cd cells/fusion/tests/discord_frontier/playwright
   npx playwright codegen "https://discord.com/developers/applications/1487798260339966023/information" \
     --save-storage=discord-devportal-state.json
   ```

   Complete login (and MFA) in the opened browser, then close it.

2. Run automation (opens **Information**, **Bot**, **OAuth2 URL generator**, toggles **bot** + **applications.commands** when checkboxes exist, writes screenshots + JSON under `evidence/discord_closure/dev_portal/`):

   ```bash
   export DISCORD_DEV_PORTAL_STORAGE_STATE="$PWD/discord-devportal-state.json"
   # optional override:
   # export DISCORD_APPLICATION_ID=1487798260339966023
   bash cells/fusion/scripts/run_discord_dev_portal_playwright.sh
   ```

3. **Password login (optional, brittle):** `DISCORD_DEV_PORTAL_EMAIL` + `DISCORD_DEV_PORTAL_PASSWORD` — fails closed on **2FA** (screenshot `*-mfa-required.png`).

## CI / validate script

`INTEGRATION_DISCORD_PLAYWRIGHT=1 bash cells/fusion/scripts/validate_discord_game_rooms.sh` runs registry checks plus Playwright.
