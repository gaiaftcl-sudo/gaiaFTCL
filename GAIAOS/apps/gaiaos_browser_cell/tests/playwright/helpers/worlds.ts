import type { Page } from '@playwright/test';

export async function gotoUi(page: Page, baseURL: string | undefined, debug = false): Promise<void> {
  const url = (baseURL ?? '/') + (debug ? '?debug=1' : '');
  await page.goto(url, { waitUntil: 'domcontentloaded' });
}

export async function waitConnected(page: Page): Promise<void> {
  await page.locator('#loading').waitFor({ state: 'hidden', timeout: 30_000 });
  await page.locator('#connection-status').waitFor({ state: 'visible', timeout: 30_000 });
}

export async function switchWorld(page: Page, world: 'Cell' | 'Human' | 'Astro'): Promise<void> {
  // ATC-first UX: world selector UI is hidden unless ?debug=1, so use keyboard shortcuts.
  if (world === 'Cell') await page.keyboard.press('Shift+C');
  if (world === 'Human') await page.keyboard.press('Shift+H');
  if (world === 'Astro') await page.keyboard.press('Shift+A');
  await page.waitForTimeout(150);
}

export async function setCameraPreset(page: Page, preset: 'default' | 'zoom' | 'global'): Promise<void> {
  await page.evaluate((p) => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const dbg: any = (window as any).__gaiaos_debug;
    if (dbg?.setCameraPreset) dbg.setCameraPreset(p);
  }, preset);
  await page.waitForTimeout(250);
}

export async function dropWs(page: Page): Promise<void> {
  await page.evaluate(() => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const dbg: any = (window as any).__gaiaos_debug;
    if (dbg?.dropWs) dbg.dropWs();
  });
}


