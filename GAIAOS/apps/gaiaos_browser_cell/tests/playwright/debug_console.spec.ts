import { test } from '@playwright/test';

test('Debug console logs', async ({ page }) => {
  const logs: string[] = [];
  const errors: string[] = [];
  
  page.on('console', msg => {
    logs.push(`[${msg.type()}] ${msg.text()}`);
  });
  
  page.on('pageerror', err => {
    errors.push(err.message);
  });
  
  await page.goto('http://localhost:8080/index.html');
  await page.waitForTimeout(5000);
  
  console.log('\n=== CONSOLE LOGS ===');
  logs.forEach(log => console.log(log));
  
  console.log('\n=== PAGE ERRORS ===');
  errors.forEach(err => console.log(err));
  
  const panelVisible = await page.locator('#envelopes-panel').isVisible();
  console.log('\n=== PANEL VISIBLE:', panelVisible, '===');
  
  const panelHTML = await page.locator('#envelopes-panel').innerHTML();
  console.log('\n=== PANEL HTML (first 500 chars) ===');
  console.log(panelHTML.substring(0, 500));
});
