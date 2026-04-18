import { test, expect } from '@playwright/test';
import { BASE, RUN_ID, ensureDirs, writeJson, writeMarkdown, writeText } from './helpers/artifacts';
import { attachDiagnostics } from './helpers/diagnostics';
import { captureDockerPs } from './helpers/transport';
import { gotoUi, waitConnected } from './helpers/worlds';

test.describe('IQ – Installation Qualification', () => {
  test('IQ – transport is healthy and truthful', async ({ page, request, baseURL }) => {
    ensureDirs();
    attachDiagnostics(page, test.info());
    writeJson('meta/run_meta.json', {
      run_id: RUN_ID,
      base_url: baseURL,
      ts: new Date().toISOString(),
    });

    captureDockerPs();

    const health = await request.get('/health', { timeout: 10_000 });
    expect(health.ok()).toBeTruthy();
    const healthJson = await health.json();
    writeJson('IQ/transport_health.json', healthJson);

    const caps = await request.get('/capabilities', { timeout: 10_000 });
    expect(caps.ok()).toBeTruthy();
    const capsJson = await caps.json();
    writeJson('IQ/transport_capabilities.json', capsJson);

    expect(capsJson.current_rev).toBeTruthy();

    // USD live.usdc existence must be consistent with capabilities (degraded-but-honest allowed).
    const usdc = await request.fetch('/usd/state/live.usdc', { method: 'HEAD' });
    writeText('IQ/live_usdc_head.txt', `status=${usdc.status()}\n`);
    if (capsJson.usd_write_live_usdc === true) {
      expect(usdc.status()).toBe(200);
    }

    // WS probe (browser-side)
    await gotoUi(page, baseURL, true);
    await waitConnected(page);
    await expect(page.locator('#connection-status')).toHaveText(/Connected/, { timeout: 30_000 });

    writeMarkdown(
      'IQ/IQ.md',
      `# Installation Qualification (IQ)

Run ID: \`${RUN_ID}\`
Artifacts base: \`${BASE}\`

## Checks
- \`GET /health\` reachable (see \`IQ/transport_health.json\`)
- \`GET /capabilities\` reachable and includes \`current_rev\` (see \`IQ/transport_capabilities.json\`)
- \`WS /ws/usd-deltas\` reachable (UI connected screenshot stored in OQ/PQ)
- \`/usd/state/live.usdc\` HEAD recorded (see \`IQ/live_usdc_head.txt\`)

## Notes
- Degraded-but-honest is valid when \`pxr_ok=false\` and \`usd_write_live_usdc=false\`.
`,
    );
  });
});


