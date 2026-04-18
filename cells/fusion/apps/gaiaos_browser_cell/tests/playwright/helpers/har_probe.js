const fs = require('fs');
const path = require('path');

async function main() {
  const baseUrl = process.env.BROWSER_CELL_BASE_URL;
  const out = process.env.GAIAOS_HAR_PATH;
  if (!baseUrl) throw new Error('BROWSER_CELL_BASE_URL not set');
  if (!out) throw new Error('GAIAOS_HAR_PATH not set');

  const { chromium } = require('playwright');
  fs.mkdirSync(path.dirname(out), { recursive: true });

  const browser = await chromium.launch();
  const context = await browser.newContext({
    recordHar: { path: out, content: 'embed' },
  });

  const page = await context.newPage();
  await page.goto(baseUrl, { waitUntil: 'domcontentloaded', timeout: 30_000 });
  // Give the UI a moment to fetch /capabilities and attempt WS connect.
  await page.waitForTimeout(2000);

  await context.close(); // required for HAR flush
  await browser.close();

  if (!fs.existsSync(out)) {
    throw new Error(`HAR not written: ${out}`);
  }
}

main().catch((e) => {
  // eslint-disable-next-line no-console
  console.error(e);
  process.exit(2);
});


