const { chromium } = require('playwright');

const APP_ID = '1487798260339966023';
const PORTAL_URL = `https://discord.com/developers/applications/${APP_ID}/bot`;

(async () => {
  console.log('🚀 Starting Discord Intents Automation...');
  
  const browser = await chromium.launch({ 
    headless: false,
    slowMo: 500
  });
  
  const context = await browser.newContext();
  const page = await context.newPage();
  
  try {
    console.log('📍 Navigating to Discord Developer Portal...');
    await page.goto(PORTAL_URL);
    
    console.log('⏳ Waiting for page to load...');
    await page.waitForLoadState('networkidle');
    
    const needsLogin = await page.locator('input[name="email"]').isVisible().catch(() => false);
    
    if (needsLogin) {
      console.log('🔐 Login required. Please login in the browser window...');
      await page.waitForURL('**/bot', { timeout: 120000 });
      console.log('✅ Login successful!');
    }
    
    console.log('📋 Checking Privileged Gateway Intents...');
    
    const intentsSection = page.locator('text=Privileged Gateway Intents').first();
    await intentsSection.scrollIntoViewIfNeeded();
    
    const intents = [
      'PRESENCE INTENT',
      'SERVER MEMBERS INTENT', 
      'MESSAGE CONTENT INTENT'
    ];
    
    for (const intent of intents) {
      console.log(`🔧 Enabling: ${intent}...`);
      
      const intentRow = page.locator(`text=${intent}`).locator('..').locator('..').first();
      const toggle = intentRow.locator('button[role="switch"]').first();
      
      const isEnabled = await toggle.getAttribute('aria-checked');
      
      if (isEnabled === 'true') {
        console.log(`   ✅ ${intent} already enabled`);
      } else {
        await toggle.click();
        console.log(`   ✅ ${intent} enabled`);
        
        const confirmButton = page.locator('button:has-text("Enable")').first();
        if (await confirmButton.isVisible({ timeout: 2000 }).catch(() => false)) {
          await confirmButton.click();
          console.log(`   ✅ Confirmed`);
        }
        
        await page.waitForTimeout(1000);
      }
    }
    
    console.log('💾 Saving changes...');
    const saveButton = page.locator('button:has-text("Save Changes")').first();
    if (await saveButton.isVisible().catch(() => false)) {
      await saveButton.click();
      await page.waitForTimeout(2000);
      console.log('✅ Changes saved!');
    }
    
    console.log('');
    console.log('✅ ALL PRIVILEGED INTENTS ENABLED');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    console.log('');
    console.log('Keeping browser open for 10 seconds...');
    await page.waitForTimeout(10000);
    await browser.close();
  }
})();
