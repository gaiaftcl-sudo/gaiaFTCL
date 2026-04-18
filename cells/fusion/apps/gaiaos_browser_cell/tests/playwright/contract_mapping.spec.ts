import { test, expect } from '@playwright/test';
import { readFileSync } from 'fs';
import { resolve } from 'path';

// Load contract manifest and surface map (single source of truth)
const manifestPath = resolve(__dirname, '../../../../evidence/ui_contract/ui_contract_manifest.json');
const surfaceMapPath = resolve(__dirname, '../../../../evidence/ui_contract/ui_surface_map.json');

const manifest = JSON.parse(readFileSync(manifestPath, 'utf-8'));
const surfaceMap = JSON.parse(readFileSync(surfaceMapPath, 'utf-8'));

test.describe('UI Contract Mapping - 100% Coverage', () => {
  test('All contract items are mapped (no unmapped items)', async () => {
    const mappings = surfaceMap.mappings;
    const totalExpected = manifest.counts.total_mappings;
    
    expect(mappings.length).toBe(totalExpected);
    
    // Verify every mapping has either PRESENT or ABSENT status
    for (const mapping of mappings) {
      const status = mapping.expected_surface?.status;
      expect(['PRESENT', 'ABSENT']).toContain(status);
      
      if (status === 'ABSENT') {
        expect(mapping.expected_surface.reason_code).toBeTruthy();
        expect(mapping.expected_surface.rationale).toBeTruthy();
      } else if (status === 'PRESENT') {
        expect(mapping.expected_surface.page).toBeTruthy();
        expect(mapping.expected_surface.selector).toBeTruthy();
        expect(mapping.expected_surface.assertion).toBeTruthy();
      }
    }
    
    console.log(`✅ All ${totalExpected} contract items are mapped`);
  });

  test('PRESENT mappings: all selectors exist on declared pages', async ({ page, baseURL }) => {
    const presentMappings = surfaceMap.mappings.filter(
      (m: any) => m.expected_surface.status === 'PRESENT'
    );
    
    // Group by page
    const byPage: Record<string, any[]> = {};
    for (const mapping of presentMappings) {
      const pagePath = mapping.expected_surface.page;
      if (!byPage[pagePath]) {
        byPage[pagePath] = [];
      }
      byPage[pagePath].push(mapping);
    }
    
    for (const [pagePath, mappings] of Object.entries(byPage)) {
      await page.goto(`${baseURL}${pagePath}`, { waitUntil: 'networkidle' });
      
      for (const mapping of mappings) {
        const selector = mapping.expected_surface.selector;
        const assertion = mapping.expected_surface.assertion;
        
        if (assertion === 'exists') {
          await expect(page.locator(selector).first())
            .toBeVisible({ timeout: 5000 });
        } else if (assertion === 'text') {
          const element = page.locator(selector).first();
          await expect(element).toBeVisible({ timeout: 5000 });
          await expect(element).toHaveText(/.+/);
        } else if (assertion === 'attr') {
          const element = page.locator(selector).first();
          await expect(element).toBeVisible({ timeout: 5000 });
        }
      }
      
      console.log(`✅ Page ${pagePath}: ${mappings.length} selectors verified`);
    }
  });

  test('ABSENT mappings: all have valid reason codes', async () => {
    const absentMappings = surfaceMap.mappings.filter(
      (m: any) => m.expected_surface.status === 'ABSENT'
    );
    
    const validReasonCodes = [
      'UI_NOT_IMPLEMENTED',
      'UI_PLANNED',
      'UI_DEFERRED',
      'SOURCE_DYNAMIC_NO_FALLBACK',
      'NOT_APPLICABLE'
    ];
    
    const reasonCounts: Record<string, number> = {};
    
    for (const mapping of absentMappings) {
      const reasonCode = mapping.expected_surface.reason_code;
      expect(validReasonCodes).toContain(reasonCode);
      reasonCounts[reasonCode] = (reasonCounts[reasonCode] || 0) + 1;
    }
    
    console.log(`✅ ABSENT items: ${absentMappings.length}`);
    console.log('   By reason:', reasonCounts);
  });

  test('Contract counts match manifest', async () => {
    const counts = manifest.counts;
    const mappings = surfaceMap.mappings;
    
    // Count by item_type
    const typeCounts: Record<string, number> = {};
    for (const mapping of mappings) {
      const type = mapping.item_type;
      typeCounts[type] = (typeCounts[type] || 0) + 1;
    }
    
    // Verify domains
    expect(typeCounts['domain'] || 0).toBe(counts.domains);
    
    // Verify games
    expect(typeCounts['game'] || 0).toBe(counts.games);
    
    // Verify dimensions (global)
    expect(typeCounts['dimension'] || 0).toBe(counts.dimensions);
    
    // Verify game_dimensions
    expect(typeCounts['game_dimension'] || 0).toBe(counts.game_dimensions);
    
    console.log('✅ Contract counts verified:');
    console.log(`   Domains: ${counts.domains}`);
    console.log(`   Games: ${counts.games}`);
    console.log(`   Dimensions: ${counts.dimensions}`);
    console.log(`   Game Dimensions: ${counts.game_dimensions}`);
    console.log(`   Envelopes: ${counts.envelopes}`);
    console.log(`   Game Envelopes: ${counts.game_envelopes}`);
    console.log(`   Total Mappings: ${counts.total_mappings}`);
  });

  test('No console errors on contract page', async ({ page, baseURL }) => {
    const errors: string[] = [];
    page.on('console', msg => {
      if (msg.type() === 'error') {
        errors.push(msg.text());
      }
    });
    
    await page.goto(`${baseURL}/contract.html`, { waitUntil: 'networkidle' });
    await page.waitForSelector('#content', { timeout: 10000 });
    
    expect(errors.length).toBe(0);
    if (errors.length > 0) {
      console.error('Console errors:', errors);
    }
  });

  test('Final coverage report', async ({ page, baseURL }) => {
    const presentCount = surfaceMap.mappings.filter(
      (m: any) => m.expected_surface.status === 'PRESENT'
    ).length;
    
    const absentCount = surfaceMap.mappings.filter(
      (m: any) => m.expected_surface.status === 'ABSENT'
    ).length;
    
    const totalMappings = surfaceMap.mappings.length;
    const expectedTotal = manifest.counts.total_mappings;
    
    console.log('\n=== UI CONTRACT MAPPING REPORT ===');
    console.log(`Total Contract Items: ${expectedTotal}`);
    console.log(`Mapped Items: ${totalMappings}`);
    console.log(`  PRESENT: ${presentCount} (${Math.round(presentCount/totalMappings*100)}%)`);
    console.log(`  ABSENT: ${absentCount} (${Math.round(absentCount/totalMappings*100)}%)`);
    console.log(`Coverage: ${totalMappings === expectedTotal ? '100% PASS' : 'FAIL'}`);
    console.log('==================================\n');
    
    expect(totalMappings).toBe(expectedTotal);
    expect(presentCount + absentCount).toBe(totalMappings);
  });
});
