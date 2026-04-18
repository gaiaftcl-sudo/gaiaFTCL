import path from 'path';
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: 1,
  reporter: 'html',
  globalSetup: './global-setup.ts',
  globalTeardown: './global-teardown.ts',
  outputDir: process.env.GAIAOS_RUN_ID
    ? path.resolve('apps/gaiaos_browser_cell/validation_artifacts', process.env.GAIAOS_RUN_ID, 'diagnostics', 'playwright_output')
    : undefined,
  use: {
    ...devices['Desktop Chrome'],
    baseURL: process.env.BROWSER_CELL_BASE_URL || 'http://127.0.0.1:8896',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    recordHar: process.env.GAIAOS_RUN_ID
      ? { path: path.resolve('apps/gaiaos_browser_cell/validation_artifacts', process.env.GAIAOS_RUN_ID, 'diagnostics', 'network.har') }
      : undefined,
  },
});


