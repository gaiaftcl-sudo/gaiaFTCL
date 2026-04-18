import fs from 'fs';
import path from 'path';
import type { Page, TestInfo } from '@playwright/test';
import { BASE, ensureDirs } from './artifacts';

function append(relPath: string, line: string): void {
  ensureDirs();
  const p = path.join(BASE, relPath);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.appendFileSync(p, line + '\n', { encoding: 'utf8' });
}

export function attachDiagnostics(page: Page, testInfo: TestInfo): void {
  // Aggregate into a single file for the whole run.
  const rel = 'diagnostics/browser_console.log';
  // Playwright versions differ slightly; keep this compatible.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const anyInfo: any = testInfo as any;
  const titlePath: string[] = typeof anyInfo.titlePath === 'function' ? anyInfo.titlePath() : [testInfo.title];
  append(rel, `=== test: ${titlePath.join(' > ')} ===`);

  page.on('console', (msg) => {
    append(rel, `[console.${msg.type()}] ${msg.text()}`);
  });
  page.on('pageerror', (err) => {
    append(rel, `[pageerror] ${String(err)}`);
  });
  page.on('requestfailed', (req) => {
    const failure = req.failure();
    append(rel, `[requestfailed] ${req.method()} ${req.url()} ${failure ? failure.errorText : ''}`);
  });
}


