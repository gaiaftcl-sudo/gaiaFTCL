import { test, expect } from '@playwright/test';
import { RUN_ID, ensureDirs, writeJson, writeMarkdown } from './helpers/artifacts';
import { attachDiagnostics } from './helpers/diagnostics';
import { screenshot } from './helpers/screenshots';
import { gotoUi, waitConnected, switchWorld, setCameraPreset } from './helpers/worlds';

test.describe('OQ – Human world', () => {
  test('OQ – Human world operational loop', async ({ page, request, baseURL }, testInfo) => {
    ensureDirs();
    attachDiagnostics(page, testInfo);
    await gotoUi(page, baseURL, true);
    await waitConnected(page);

    await switchWorld(page, 'Human');

    await setCameraPreset(page, 'default');
    await screenshot(page, 'ui_worlds/human/views/default.png', testInfo);

    await setCameraPreset(page, 'zoom');
    await screenshot(page, 'ui_worlds/human/views/zoomed.png', testInfo);

    await setCameraPreset(page, 'global');
    await screenshot(page, 'ui_worlds/human/views/global.png', testInfo);

    await screenshot(page, 'ui_worlds/human/views/degraded_capability.png', testInfo);

    // Perception action via UI: create a perception-only mark (not truth).
    page.once('dialog', async (d) => d.accept('Investigate now'));
    await page.getByRole('button', { name: 'Mark (Perception)' }).click();
    await page.waitForTimeout(1000);
    await screenshot(page, 'ui_worlds/human/functions/perception_mark.png', testInfo);

    // Verify rev visible in UI
    const revText = await page.locator('#current-rev').textContent();
    expect(revText).toBeTruthy();

    const caps = await request.get('/capabilities');
    const capsJson = await caps.json();
    writeJson('OQ/capabilities_after_human.json', capsJson);

    writeMarkdown(
      'ui_worlds/human/README.md',
      `# Human world evidence

Run: \`${RUN_ID}\`

## Views
- default.png
- zoomed.png
- global.png
- degraded_capability.png

## Functions
- perception_mark.png

## Notes
- Perception marks are \`not_truth=true\` overlays and must never be treated as truth.
`,
    );

    writeMarkdown(
      'OQ/OQ_HUMAN.md',
      `# Operational Qualification – Human world

Evidence:
- Screenshots under \`ui_worlds/human/\`
- Capabilities snapshot: \`OQ/capabilities_after_human.json\`
`,
    );
  });
});


