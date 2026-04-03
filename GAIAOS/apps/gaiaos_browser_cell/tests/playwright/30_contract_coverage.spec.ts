import { test, expect } from '@playwright/test';
import { readFileSync } from 'fs';
import { resolve } from 'path';

// Load contract manifest (single source of truth)
const contractPath = resolve(__dirname, '../../src/ui_contract/ui_contract_manifest.json');
const contract = JSON.parse(readFileSync(contractPath, 'utf-8'));

test.describe('Contract Coverage - 100% Element Assertion', () => {
  test.beforeEach(async ({ page, baseURL }) => {
    await page.goto(`${baseURL}/contract.html`, { waitUntil: 'networkidle' });
    await expect(page.locator('#content')).toBeVisible({ timeout: 10000 });
  });

  test('All domains are rendered (exact set)', async ({ page }) => {
    const expectedDomains = contract.domains.map((d: any) => d.domain_id);
    
    for (const domainId of expectedDomains) {
      await expect(page.locator(`[data-testid="domain:${domainId}"]`))
        .toBeVisible({ timeout: 5000 });
    }
    
    // Verify no unexpected domains
    const renderedDomains = await page.locator('[data-testid^="domain:"]').count();
    expect(renderedDomains).toBe(expectedDomains.length);
    
    console.log(`✅ Domains: ${expectedDomains.length}/${expectedDomains.length} present`);
  });

  test('All games are rendered (exact set)', async ({ page }) => {
    const expectedGames = contract.games.map((g: any) => g.game_id);
    
    for (const gameId of expectedGames) {
      await expect(page.locator(`[data-testid="game:${gameId}"]`))
        .toBeVisible({ timeout: 5000 });
    }
    
    // Verify no unexpected games
    const renderedGames = await page.locator('[data-testid^="game:"]').count();
    expect(renderedGames).toBe(expectedGames.length);
    
    console.log(`✅ Games: ${expectedGames.length}/${expectedGames.length} present`);
  });

  test('All UUM-8D dimensions are rendered for each game (exact)', async ({ page }) => {
    let totalDimsExpected = 0;
    let totalDimsFound = 0;
    
    for (const game of contract.games) {
      for (const dimKey of game.required_uum8d_dims) {
        totalDimsExpected++;
        const selector = `[data-testid="dim:${game.game_id}:${dimKey}"]`;
        await expect(page.locator(selector))
          .toBeVisible({ timeout: 5000 });
        totalDimsFound++;
      }
    }
    
    // Verify no unexpected dimensions in game contexts
    const renderedGameDims = await page.locator('[data-testid^="dim:"]:not([data-testid^="dim:all:"])').count();
    expect(renderedGameDims).toBe(totalDimsExpected);
    
    console.log(`✅ Game Dimensions: ${totalDimsFound}/${totalDimsExpected} present`);
  });

  test('All envelopes are rendered for each game (exact)', async ({ page }) => {
    let totalEnvelopesExpected = 0;
    let totalEnvelopesFound = 0;
    
    for (const game of contract.games) {
      for (const envSubject of game.expected_envelopes) {
        totalEnvelopesExpected++;
        const envId = Buffer.from(envSubject).toString('base64').replace(/[+/=]/g, '_');
        const selector = `[data-testid="env:${game.game_id}:${envId}"]`;
        await expect(page.locator(selector))
          .toBeVisible({ timeout: 5000 });
        totalEnvelopesFound++;
      }
    }
    
    // Verify no unexpected envelopes in game contexts
    const renderedGameEnvs = await page.locator('[data-testid^="env:"]:not([data-testid^="env:all:"])').count();
    expect(renderedGameEnvs).toBe(totalEnvelopesExpected);
    
    console.log(`✅ Game Envelopes: ${totalEnvelopesFound}/${totalEnvelopesExpected} present`);
  });

  test('All UUM-8D dimensions are listed in global section (exact)', async ({ page }) => {
    const expectedDims = contract.uum8d_dims.map((d: any) => d.dim_key);
    
    for (const dimKey of expectedDims) {
      await expect(page.locator(`[data-testid="dim:all:${dimKey}"]`))
        .toBeVisible({ timeout: 5000 });
    }
    
    // Verify exact count in "all" section
    const renderedAllDims = await page.locator('[data-testid^="dim:all:"]').count();
    expect(renderedAllDims).toBe(expectedDims.length);
    
    console.log(`✅ All Dimensions: ${expectedDims.length}/${expectedDims.length} present`);
  });

  test('All envelopes are listed in global section (exact)', async ({ page }) => {
    const expectedEnvelopes = contract.envelopes.map((e: any) => e.subject);
    
    for (const envSubject of expectedEnvelopes) {
      const envId = Buffer.from(envSubject).toString('base64').replace(/[+/=]/g, '_');
      await expect(page.locator(`[data-testid="env:all:${envId}"]`))
        .toBeVisible({ timeout: 5000 });
    }
    
    // Verify exact count in "all" section
    const renderedAllEnvs = await page.locator('[data-testid^="env:all:"]').count();
    expect(renderedAllEnvs).toBe(expectedEnvelopes.length);
    
    console.log(`✅ All Envelopes: ${expectedEnvelopes.length}/${expectedEnvelopes.length} present`);
  });

  test('Summary displays correct counts', async ({ page }) => {
    const summaryText = await page.locator('#summary').textContent();
    
    expect(summaryText).toContain(`Domains:\n          ${contract.domains.length}`);
    expect(summaryText).toContain(`Games:\n          ${contract.games.length}`);
    expect(summaryText).toContain(`Envelopes:\n          ${contract.envelopes.length}`);
    expect(summaryText).toContain(`UUM-8D Dimensions:\n          ${contract.uum8d_dims.length}`);
    
    console.log(`✅ Summary: Domains=${contract.domains.length}, Games=${contract.games.length}, Envelopes=${contract.envelopes.length}, Dims=${contract.uum8d_dims.length}`);
  });

  test('No console errors during load', async ({ page }) => {
    const errors: string[] = [];
    page.on('console', msg => {
      if (msg.type() === 'error') {
        errors.push(msg.text());
      }
    });
    
    await page.reload({ waitUntil: 'networkidle' });
    await expect(page.locator('#content')).toBeVisible({ timeout: 10000 });
    
    expect(errors.length).toBe(0);
    if (errors.length > 0) {
      console.error('Console errors:', errors);
    }
  });
});

test.describe('Contract Coverage - Final Counts', () => {
  test('Report final coverage metrics', async ({ page, baseURL }) => {
    await page.goto(`${baseURL}/contract.html`, { waitUntil: 'networkidle' });
    await expect(page.locator('#content')).toBeVisible({ timeout: 10000 });
    
    const domains = contract.domains.length;
    const games = contract.games.length;
    const envelopes = contract.envelopes.length;
    const dims = contract.uum8d_dims.length;
    
    // Count rendered elements
    const renderedDomains = await page.locator('[data-testid^="domain:"]').count();
    const renderedGames = await page.locator('[data-testid^="game:"]').count();
    const renderedGameDims = await page.locator('[data-testid^="dim:"]:not([data-testid^="dim:all:"])').count();
    const renderedGameEnvs = await page.locator('[data-testid^="env:"]:not([data-testid^="env:all:"])').count();
    const renderedAllDims = await page.locator('[data-testid^="dim:all:"]').count();
    const renderedAllEnvs = await page.locator('[data-testid^="env:all:"]').count();
    
    // Calculate expected game-level dimensions and envelopes
    let expectedGameDims = 0;
    let expectedGameEnvs = 0;
    for (const game of contract.games) {
      expectedGameDims += game.required_uum8d_dims.length;
      expectedGameEnvs += game.expected_envelopes.length;
    }
    
    console.log('\n=== FINAL COVERAGE REPORT ===');
    console.log(`Domains: ${renderedDomains}/${domains} (${renderedDomains === domains ? '100% PASS' : 'FAIL'})`);
    console.log(`Games: ${renderedGames}/${games} (${renderedGames === games ? '100% PASS' : 'FAIL'})`);
    console.log(`Game Dimensions: ${renderedGameDims}/${expectedGameDims} (${renderedGameDims === expectedGameDims ? '100% PASS' : 'FAIL'})`);
    console.log(`Game Envelopes: ${renderedGameEnvs}/${expectedGameEnvs} (${renderedGameEnvs === expectedGameEnvs ? '100% PASS' : 'FAIL'})`);
    console.log(`All Dimensions: ${renderedAllDims}/${dims} (${renderedAllDims === dims ? '100% PASS' : 'FAIL'})`);
    console.log(`All Envelopes: ${renderedAllEnvs}/${envelopes} (${renderedAllEnvs === envelopes ? '100% PASS' : 'FAIL'})`);
    console.log('=============================\n');
    
    expect(renderedDomains).toBe(domains);
    expect(renderedGames).toBe(games);
    expect(renderedGameDims).toBe(expectedGameDims);
    expect(renderedGameEnvs).toBe(expectedGameEnvs);
    expect(renderedAllDims).toBe(dims);
    expect(renderedAllEnvs).toBe(envelopes);
  });
});
