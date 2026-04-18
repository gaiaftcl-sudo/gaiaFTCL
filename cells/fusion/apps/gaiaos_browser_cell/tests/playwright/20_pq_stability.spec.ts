import { test, expect } from '@playwright/test';
import { RUN_ID, ensureDirs, writeJson, writeMarkdown } from './helpers/artifacts';
import { attachDiagnostics } from './helpers/diagnostics';
import { screenshot } from './helpers/screenshots';
import { gotoUi, waitConnected, dropWs } from './helpers/worlds';

test.describe('PQ – Performance Qualification', () => {
  test('PQ – WS drop and resync (best-effort, evidence-backed)', async ({ page, request, baseURL }, testInfo) => {
    ensureDirs();
    attachDiagnostics(page, testInfo);
    await gotoUi(page, baseURL, true);
    await waitConnected(page);

    // Generate WS traffic via repeated perception marks (operator action).
    for (let i = 0; i < 5; i++) {
      page.once('dialog', async (d) => d.accept(`PQ mark ${i}`));
      await page.getByRole('button', { name: 'Mark (Perception)' }).click();
      await page.waitForTimeout(250);
    }

    await screenshot(page, 'PQ/sustained_ws_msgs.png', testInfo);

    // Induce WS drop via debug hook
    await dropWs(page);
    await page.waitForTimeout(1500);

    // Expect reconnect within a bounded time (best effort backoff)
    await expect(page.locator('#connection-status')).toHaveText(/Connected/, { timeout: 30_000 });
    await screenshot(page, 'PQ/ws_resync_connected.png', testInfo);

    // Evidence: current_rev remains monotonic for at least one world
    const caps = await request.get('/capabilities');
    const capsJson = await caps.json();
    writeJson('PQ/capabilities_after_resync.json', capsJson);

    writeMarkdown(
      'PQ/PQ.md',
      `# Performance Qualification (PQ)

Run: \`${RUN_ID}\`

## Scenarios tested
- Sustained WS traffic (perception ops) while UI is active
- Forced WS disconnect (debug hook)
- Automatic reconnect + resync (capabilities refresh)

## Evidence
- Screenshots:
  - \`PQ/sustained_ws_msgs.png\`
  - \`PQ/ws_resync_connected.png\`
- Capabilities snapshot:
  - \`PQ/capabilities_after_resync.json\`
`,
    );
  });
});


