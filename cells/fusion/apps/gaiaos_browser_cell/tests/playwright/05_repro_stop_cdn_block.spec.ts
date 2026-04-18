import { test, expect } from '@playwright/test';
import { ensureDirs } from './helpers/artifacts';
import { attachDiagnostics } from './helpers/diagnostics';
import { gotoUi, waitConnected } from './helpers/worlds';

test.describe('Diagnostics – stop reproduction (CDN blocked)', () => {
  test('UI should load without external CDN (when GAIAOS_REPRO_STOP=1)', async ({ page, baseURL }) => {
    test.skip(process.env.GAIAOS_REPRO_STOP !== '1', 'Enable with GAIAOS_REPRO_STOP=1');

    ensureDirs();
    attachDiagnostics(page, test.info());

    // Block known external module sources. If the UI depends on these, it will stall at the loading overlay.
    await page.route('https://cdn.jsdelivr.net/**', (route) => route.abort());
    await page.route('https://unpkg.com/**', (route) => route.abort());

    await gotoUi(page, baseURL);

    // If the UI has no external dependency, it should still connect and hide loading.
    await waitConnected(page);
    await expect(page.locator('#connection-status')).toHaveText(/Connected/, { timeout: 30_000 });
  });
});


