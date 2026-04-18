/**
 * CONTRACT MAPPING VALIDATION (NO UI NAVIGATION)
 * 
 * This test validates that all contract items are mapped.
 * It does NOT test UI realization - see ui_realization_rules.spec.ts for that.
 */

import { test, expect } from '@playwright/test';
import { readFileSync } from 'fs';
import { resolve } from 'path';

const manifestPath = resolve(__dirname, '../../../../evidence/ui_contract/ui_contract_manifest.json');
const surfaceMapPath = resolve(__dirname, '../../../../evidence/ui_contract/ui_surface_map.json');

test.describe('UI Contract Validation (Filesystem Only)', () => {
  test('Manifest and surface map files exist', () => {
    expect(() => readFileSync(manifestPath, 'utf-8')).not.toThrow();
    expect(() => readFileSync(surfaceMapPath, 'utf-8')).not.toThrow();
  });

  test('All contract items are mapped (no unmapped items)', () => {
    const manifest = JSON.parse(readFileSync(manifestPath, 'utf-8'));
    const surfaceMap = JSON.parse(readFileSync(surfaceMapPath, 'utf-8'));
    
    const totalExpected = manifest.counts.total_mappings;
    const totalMapped = surfaceMap.mappings.length;
    
    console.log(`Expected: ${totalExpected} items`);
    console.log(`Mapped: ${totalMapped} items`);
    
    expect(totalMapped).toBe(totalExpected);
  });

  test('Every mapping has PRESENT or ABSENT status', () => {
    const surfaceMap = JSON.parse(readFileSync(surfaceMapPath, 'utf-8'));
    
    let presentCount = 0;
    let absentCount = 0;
    let invalidCount = 0;
    
    for (const mapping of surfaceMap.mappings) {
      const status = mapping.expected_surface?.status;
      
      if (status === 'PRESENT') {
        presentCount++;
        // Verify PRESENT has required fields
        expect(mapping.expected_surface.page).toBeTruthy();
        expect(mapping.expected_surface.selector).toBeTruthy();
        expect(mapping.expected_surface.assertion).toBeTruthy();
      } else if (status === 'ABSENT') {
        absentCount++;
        // Verify ABSENT has reason_code
        expect(mapping.expected_surface.reason_code).toBeTruthy();
      } else {
        invalidCount++;
      }
    }
    
    console.log(`PRESENT: ${presentCount}`);
    console.log(`ABSENT: ${absentCount}`);
    console.log(`Invalid: ${invalidCount}`);
    
    expect(invalidCount).toBe(0);
    expect(presentCount + absentCount).toBe(surfaceMap.mappings.length);
  });

  test('Counts consistency: present + absent = total', () => {
    const manifest = JSON.parse(readFileSync(manifestPath, 'utf-8'));
    const surfaceMap = JSON.parse(readFileSync(surfaceMapPath, 'utf-8'));
    
    const totalExpected = manifest.counts.total_mappings;
    
    let presentCount = 0;
    let absentCount = 0;
    
    for (const mapping of surfaceMap.mappings) {
      const status = mapping.expected_surface?.status;
      if (status === 'PRESENT') presentCount++;
      if (status === 'ABSENT') absentCount++;
    }
    
    const unmapped = totalExpected - (presentCount + absentCount);
    
    console.log(`Total expected: ${totalExpected}`);
    console.log(`Present: ${presentCount}`);
    console.log(`Absent: ${absentCount}`);
    console.log(`Unmapped: ${unmapped}`);
    
    expect(unmapped).toBe(0);
    expect(presentCount + absentCount).toBe(totalExpected);
  });

  test('Contract counts match expected values', () => {
    const manifest = JSON.parse(readFileSync(manifestPath, 'utf-8'));
    
    const counts = manifest.counts;
    
    expect(counts.domains).toBe(2);
    expect(counts.games).toBe(4);
    expect(counts.envelopes).toBe(16);
    expect(counts.dimensions).toBe(8);
    expect(counts.game_envelopes).toBe(11);
    expect(counts.game_dimensions).toBe(20);
    expect(counts.total_mappings).toBe(61);
    
    console.log('✅ All counts verified');
    console.log(JSON.stringify(counts, null, 2));
  });

  test('Final report: 100% mapping coverage', () => {
    const manifest = JSON.parse(readFileSync(manifestPath, 'utf-8'));
    const surfaceMap = JSON.parse(readFileSync(surfaceMapPath, 'utf-8'));
    
    const totalExpected = manifest.counts.total_mappings;
    const totalMapped = surfaceMap.mappings.length;
    
    let presentCount = 0;
    let absentCount = 0;
    
    for (const mapping of surfaceMap.mappings) {
      const status = mapping.expected_surface?.status;
      if (status === 'PRESENT') presentCount++;
      if (status === 'ABSENT') absentCount++;
    }
    
    const coverage = (totalMapped / totalExpected) * 100;
    
    console.log('\n=== FINAL CONTRACT VALIDATION REPORT ===');
    console.log(`Total Items: ${totalExpected}`);
    console.log(`Mapped Items: ${totalMapped}`);
    console.log(`Coverage: ${coverage.toFixed(1)}%`);
    console.log(`PRESENT: ${presentCount} (${((presentCount/totalExpected)*100).toFixed(1)}%)`);
    console.log(`ABSENT: ${absentCount} (${((absentCount/totalExpected)*100).toFixed(1)}%)`);
    console.log(`Unmapped: ${totalExpected - totalMapped}`);
    console.log('========================================\n');
    
    expect(coverage).toBe(100);
    expect(totalMapped).toBe(totalExpected);
  });
});
