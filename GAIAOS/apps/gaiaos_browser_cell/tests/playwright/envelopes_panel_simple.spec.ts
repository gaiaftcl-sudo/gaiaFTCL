/**
 * Simple test for envelopes panel in index.html
 */

import { test, expect } from '@playwright/test';

test('Envelopes panel shows top 10 game_envelopes', async ({ page }) => {
  await page.goto('http://localhost:8080/index.html');
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(2000); // Wait for JS to execute
  
  // Check panel exists
  const panel = page.locator('#envelopes-panel');
  await expect(panel).toBeVisible();
  
  // Check first item
  const firstItem = page.locator('[data-testid="contract-g_ftcl_update_fleet_v1_fleet_update_request"]');
  await expect(firstItem).toBeVisible();
  
  const firstLabel = page.locator('[data-testid="contract-g_ftcl_update_fleet_v1_fleet_update_request-label"]');
  await expect(firstLabel).toHaveText('G_FTCL_UPDATE_FLEET_V1:FLEET_UPDATE_REQUEST');
  
  const firstKind = page.locator('[data-testid="contract-g_ftcl_update_fleet_v1_fleet_update_request-kind"]');
  await expect(firstKind).toHaveText('game_envelope');
  
  const firstStatus = page.locator('[data-testid="contract-g_ftcl_update_fleet_v1_fleet_update_request-status"]');
  await expect(firstStatus).toHaveText('UI_PRESENT');
  
  console.log('✅ First envelope item verified');
  
  // Count all envelope rows
  const rows = page.locator('.envelope-row');
  const count = await rows.count();
  console.log(`Found ${count} envelope rows`);
  expect(count).toBe(27);
});
