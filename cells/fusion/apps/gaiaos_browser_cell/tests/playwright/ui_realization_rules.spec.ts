/**
 * UI REALIZATION RULES VALIDATION (NO UI NAVIGATION)
 * 
 * This test validates UI proof rules without navigating to UI.
 * It ensures no UI_PRESENT item lacks route/selector/assertion.
 */

import { test, expect } from '@playwright/test';
import { readFileSync } from 'fs';
import { resolve } from 'path';

const surfaceMapPath = resolve(__dirname, '../../../../evidence/ui_contract/ui_surface_map.json');

test.describe('UI Realization Rules (Filesystem Only)', () => {
  test('No UI_PRESENT item lacks proof requirements', () => {
    const surfaceMap = JSON.parse(readFileSync(surfaceMapPath, 'utf-8'));
    
    let violations = 0;
    const violationDetails: string[] = [];
    
    for (const mapping of surfaceMap.mappings) {
      const uiStatus = mapping.ui_mapping?.status;
      
      if (uiStatus === 'UI_PRESENT') {
        const hasRoute = mapping.ui_mapping.route !== null && mapping.ui_mapping.route !== undefined;
        const hasSelector = mapping.ui_mapping.selector !== null && mapping.ui_mapping.selector !== undefined;
        const hasAssertion = mapping.ui_mapping.assertion !== null && mapping.ui_mapping.assertion !== undefined;
        
        if (!hasRoute || !hasSelector || !hasAssertion) {
          violations++;
          violationDetails.push(`${mapping.id} (${mapping.kind}): missing ${!hasRoute ? 'route ' : ''}${!hasSelector ? 'selector ' : ''}${!hasAssertion ? 'assertion' : ''}`);
        }
      }
    }
    
    if (violations > 0) {
      console.error('UI_PRESENT items lacking proof:');
      violationDetails.forEach(v => console.error(`  - ${v}`));
    }
    
    expect(violations).toBe(0);
  });

  test('UI counts are consistent', () => {
    const surfaceMap = JSON.parse(readFileSync(surfaceMapPath, 'utf-8'));
    
    let uiPresent = 0;
    let uiAbsent = 0;
    let other = 0;
    
    for (const mapping of surfaceMap.mappings) {
      const uiStatus = mapping.ui_mapping?.status;
      
      if (uiStatus === 'UI_PRESENT') {
        uiPresent++;
      } else if (uiStatus === 'UI_ABSENT') {
        uiAbsent++;
      } else {
        other++;
      }
    }
    
    const total = surfaceMap.mappings.length;
    
    console.log(`UI_PRESENT: ${uiPresent}`);
    console.log(`UI_ABSENT: ${uiAbsent}`);
    console.log(`Other: ${other}`);
    console.log(`Total: ${total}`);
    
    expect(uiPresent + uiAbsent).toBe(total);
    expect(other).toBe(0);
  });

  test('All UI_ABSENT items have reason_code', () => {
    const surfaceMap = JSON.parse(readFileSync(surfaceMapPath, 'utf-8'));
    
    let missingReason = 0;
    
    for (const mapping of surfaceMap.mappings) {
      const uiStatus = mapping.ui_mapping?.status;
      
      if (uiStatus === 'UI_ABSENT') {
        const hasReason = mapping.ui_mapping.reason_code !== null && 
                         mapping.ui_mapping.reason_code !== undefined &&
                         mapping.ui_mapping.reason_code !== '';
        if (!hasReason) {
          missingReason++;
          console.error(`${mapping.id} (${mapping.kind}): UI_ABSENT but no reason_code`);
        }
      }
    }
    
    expect(missingReason).toBe(0);
  });

  test('UI realization coverage report', () => {
    const surfaceMap = JSON.parse(readFileSync(surfaceMapPath, 'utf-8'));
    
    let uiPresent = 0;
    let uiAbsent = 0;
    const reasonCounts: Record<string, number> = {};
    
    for (const mapping of surfaceMap.mappings) {
      const uiStatus = mapping.ui_mapping?.status;
      
      if (uiStatus === 'UI_PRESENT') {
        uiPresent++;
      } else if (uiStatus === 'UI_ABSENT') {
        uiAbsent++;
        const reason = mapping.ui_mapping.reason_code || 'UNKNOWN';
        reasonCounts[reason] = (reasonCounts[reason] || 0) + 1;
      }
    }
    
    const total = surfaceMap.mappings.length;
    const uiCoverage = (uiPresent / total) * 100;
    
    console.log('\n=== UI REALIZATION COVERAGE REPORT ===');
    console.log(`Total Items: ${total}`);
    console.log(`UI_PRESENT: ${uiPresent} (${uiCoverage.toFixed(1)}%)`);
    console.log(`UI_ABSENT: ${uiAbsent} (${((uiAbsent/total)*100).toFixed(1)}%)`);
    console.log('UI_ABSENT by reason:');
    Object.entries(reasonCounts).forEach(([reason, count]) => {
      console.log(`  ${reason}: ${count}`);
    });
    console.log('======================================\n');
    
    // This test always passes - it's informational
    expect(uiPresent + uiAbsent).toBe(total);
  });
});
