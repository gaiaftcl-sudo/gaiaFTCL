import { test, expect } from '@playwright/test';
import { RUN_ID, ensureDirs, writeJson, writeMarkdown } from './helpers/artifacts';
import { attachDiagnostics } from './helpers/diagnostics';
import { screenshot } from './helpers/screenshots';
import { gotoUi, waitConnected, switchWorld, setCameraPreset } from './helpers/worlds';

test.describe('OQ – Astro world', () => {
  test('OQ – Astro world operational loop', async ({ page, request, baseURL }, testInfo) => {
    ensureDirs();
    attachDiagnostics(page, testInfo);
    await gotoUi(page, baseURL, true);
    await waitConnected(page);

    await switchWorld(page, 'Astro');

    await setCameraPreset(page, 'default');
    await screenshot(page, 'ui_worlds/astro/views/default.png', testInfo);

    await setCameraPreset(page, 'zoom');
    await screenshot(page, 'ui_worlds/astro/views/zoomed.png', testInfo);

    await setCameraPreset(page, 'global');
    await screenshot(page, 'ui_worlds/astro/views/global.png', testInfo);

    await screenshot(page, 'ui_worlds/astro/views/degraded_capability.png', testInfo);

    // Perception action via UI: create a perception-only mark (not truth).
    page.once('dialog', async (d) => d.accept('Astro world mark'));
    await page.getByRole('button', { name: 'Mark (Perception)' }).click();
    await page.waitForTimeout(1000);
    await screenshot(page, 'ui_worlds/astro/functions/perception_mark.png', testInfo);

    // Verify UI shows connected.
    await expect(page.locator('#connection-status')).toHaveText(/Connected/);

    const caps = await request.get('/capabilities');
    const capsJson = await caps.json();
    writeJson('OQ/capabilities_after_astro.json', capsJson);

    writeMarkdown(
      'ui_worlds/astro/README.md',
      `# Astro world evidence

Run: \`${RUN_ID}\`

## Views
- default.png
- zoomed.png
- global.png
- degraded_capability.png

## Functions
- perception_mark.png
`,
    );

    writeMarkdown(
      'OQ/OQ_ASTRO.md',
      `# Operational Qualification – Astro world

Evidence:
- Screenshots under \`ui_worlds/astro/\`
- Capabilities snapshot: \`OQ/capabilities_after_astro.json\`
`,
    );
  });
});


