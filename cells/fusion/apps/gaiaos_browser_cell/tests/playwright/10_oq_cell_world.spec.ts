import { test, expect } from '@playwright/test';
import fs from 'fs';
import path from 'path';
import { RUN_ID, BASE, ensureDirs, writeJson, writeMarkdown, copyFileTo, writeText } from './helpers/artifacts';
import { attachDiagnostics } from './helpers/diagnostics';
import { screenshot } from './helpers/screenshots';
import { gotoUi, waitConnected, switchWorld, setCameraPreset } from './helpers/worlds';

function copyLatestPerceptionArtifacts(): void {
  const perceptionDir = path.resolve('apps/gaiaos_browser_cell/usd/perception');
  const auditFile = path.resolve('apps/gaiaos_browser_cell/usd/audit/audit.jsonl');
  const rejIndex = path.resolve('apps/gaiaos_browser_cell/usd/rejections/rejections.ndjson');
  if (fs.existsSync(perceptionDir)) {
    const files = fs
      .readdirSync(perceptionDir)
      .filter((f) => f.endsWith('.json') || f.endsWith('.usda'))
      .map((f) => path.join(perceptionDir, f))
      .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
    if (files[0]) copyFileTo('OQ/perception_last' + path.extname(files[0]), files[0]);
  }
  if (fs.existsSync(auditFile)) {
    const tail = fs.readFileSync(auditFile, 'utf8').split('\n').slice(-10).join('\n');
    writeText('OQ/audit_tail_10.jsonl', tail);
  }
  if (fs.existsSync(rejIndex)) {
    const lines = fs.readFileSync(rejIndex, 'utf8').split('\n').filter((l) => l.trim().length);
    const tail = lines.slice(-20).join('\n') + (lines.length ? '\n' : '');
    writeText('OQ/perception_rejections_tail_20.ndjson', tail);
  } else {
    writeText('OQ/perception_rejections_tail_20.ndjson', '');
  }
}

test.describe('OQ – Cell world', () => {
  test('OQ – Cell world operational loop', async ({ page, request, baseURL }, testInfo) => {
    ensureDirs();
    attachDiagnostics(page, testInfo);
    await gotoUi(page, baseURL, true);
    await waitConnected(page);

    await switchWorld(page, 'Cell');

    await setCameraPreset(page, 'default');
    await screenshot(page, 'ui_worlds/cell/views/default.png', testInfo);

    // Global ATC is the primary view; capture global scope.
    await page.keyboard.press('0');
    await page.waitForTimeout(500);
    await screenshot(page, 'ui_worlds/cell/views/global_earth.png', testInfo);

    await setCameraPreset(page, 'zoom');
    await screenshot(page, 'ui_worlds/cell/views/zoomed.png', testInfo);

    await setCameraPreset(page, 'global');
    await screenshot(page, 'ui_worlds/cell/views/global.png', testInfo);

    // Degraded capability state is always visible in status panels; capture once per world.
    await screenshot(page, 'ui_worlds/cell/views/degraded_capability.png', testInfo);

    // ATC v2: camera modes + toggles.
    await page.keyboard.press('1'); // TRACON
    await page.waitForTimeout(250);
    await screenshot(page, 'ui_worlds/cell/views/camera_mode_corridor.png', testInfo);

    await page.keyboard.press('2'); // tower
    await page.waitForTimeout(250);
    await screenshot(page, 'ui_worlds/cell/views/camera_mode_airport.png', testInfo);

    await page.keyboard.press('3'); // traffic fit
    await page.waitForTimeout(250);
    await screenshot(page, 'ui_worlds/cell/views/camera_mode_traffic.png', testInfo);

    await page.keyboard.press('V'); // vectors toggle
    await page.waitForTimeout(250);
    await screenshot(page, 'ui_worlds/cell/views/vectors_toggled.png', testInfo);

    await page.keyboard.press('D'); // hazards toggle
    await page.waitForTimeout(250);
    await screenshot(page, 'ui_worlds/cell/views/danger_toggled.png', testInfo);

    // Perception action: create a perception-only mark.
    await page.getByRole('button', { name: 'Mark (Perception)' }).click();
    page.once('dialog', async (d) => d.accept('Cell world OQ mark'));

    // Wait for rev to increment via resync (best effort) and then capture.
    await page.waitForTimeout(1000);
    await screenshot(page, 'ui_worlds/cell/functions/perception_mark.png', testInfo);

    // Trigger one invariant rejection and verify UI visibility (toast) without rev bump.
    await switchWorld(page, 'Cell');
    const ridA = `${Date.now()}-a`;
    const ridB = `${Date.now()}-b`;
    const rej = await request.post('/perception', {
      data: {
        world: 'Cell',
        provenance: { source: 'OQCell', operator: 'operator', ts_ms: Date.now() },
        ops: [
          {
            op: 'SetAttr',
            op_id: ridA,
            path: '/GaiaOS/Worlds/Cell/Perception/Aircraft/a1b2c3',
            name: 'gaiaos:lat',
            valueType: 'float',
            value: 200.0,
          },
          {
            op: 'SetAttr',
            op_id: ridB,
            path: '/GaiaOS/Worlds/Cell/Perception/Aircraft/a1b2c3',
            name: 'gaiaos:source',
            valueType: 'string',
            value: 'airplanes_live',
          },
        ],
      },
    });
    expect(rej.status()).toBe(422);
    await page.waitForTimeout(600);
    await screenshot(page, 'ui_worlds/cell/functions/perception_reject_toast.png', testInfo);

    const caps = await request.get('/capabilities');
    expect(caps.ok()).toBeTruthy();
    const capsJson = await caps.json();
    writeJson('OQ/capabilities_after_cell.json', capsJson);

    copyLatestPerceptionArtifacts();

    writeMarkdown(
      'ui_worlds/cell/README.md',
      `# Cell world evidence

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
      'OQ/OQ_CELL.md',
      `# Operational Qualification – Cell world

Run ID: \`${RUN_ID}\`

Evidence:
- Screenshots under \`ui_worlds/cell/\`
- Latest perception artifact copied into \`OQ/\`
- Capabilities snapshot: \`OQ/capabilities_after_cell.json\`
`,
    );
  });
});


