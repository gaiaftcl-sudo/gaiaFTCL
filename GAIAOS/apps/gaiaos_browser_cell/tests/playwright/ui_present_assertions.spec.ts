/**
 * UI_PRESENT ASSERTIONS (REAL UI NAVIGATION)
 * 
 * This test iterates all UI_PRESENT items in ui_surface_map.json
 * and asserts they are visible with correct selectors and labels.
 */

import { test, expect } from '@playwright/test';
import { readFileSync } from 'fs';
import { resolve } from 'path';

const surfaceMapPath = resolve(__dirname, '../../../../evidence/ui_contract/ui_surface_map.json');

test.describe('UI_PRESENT Assertions (Real UI)', () => {
  test('All UI_PRESENT items are visible with correct selectors', async ({ page }) => {
    const surfaceMap = JSON.parse(readFileSync(surfaceMapPath, 'utf-8'));
    
    // Filter UI_PRESENT items
    const presentItems = surfaceMap.mappings.filter((m: any) => m.ui_mapping?.status === 'UI_PRESENT');
    
    console.log(`\nTesting ${presentItems.length} UI_PRESENT items...`);
    
    // Group by route
    const byRoute: Record<string, any[]> = {};
    for (const item of presentItems) {
      const route = item.ui_mapping.route;
      if (!byRoute[route]) byRoute[route] = [];
      byRoute[route].push(item);
    }
    
    let totalAsserted = 0;
    
    for (const [route, items] of Object.entries(byRoute)) {
      console.log(`\n  Route: ${route} (${items.length} items)`);
      
      // Navigate once per route
      await page.goto(`http://localhost:8080${route}`);
      await page.waitForLoadState('networkidle');
      
      for (const item of items) {
        const selector = item.ui_mapping.selector;
        const baseSelector = selector.replace(/\[data-testid='([^']+)'\]/, '$1');
        const labelSelector = `[data-testid='${baseSelector}-label']`;
        const kindSelector = `[data-testid='${baseSelector}-kind']`;
        const statusSelector = `[data-testid='${baseSelector}-status']`;
        
        // Assert element exists
        const element = page.locator(selector);
        await expect(element).toBeVisible({ timeout: 5000 });
        
        // Assert label text
        const label = page.locator(labelSelector);
        await expect(label).toHaveText(item.id);
        
        // Assert kind
        const kind = page.locator(kindSelector);
        await expect(kind).toHaveText(item.kind);
        
        // Assert status
        const status = page.locator(statusSelector);
        await expect(status).toHaveText('UI_PRESENT');
        
        totalAsserted++;
      }
    }
    
    console.log(`\n✅ Total items asserted: ${totalAsserted}/${presentItems.length}\n`);
    expect(totalAsserted).toBe(presentItems.length);
  });
});
