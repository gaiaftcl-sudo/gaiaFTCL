import fs from 'fs';
import path from 'path';
import os from 'os';
import { execSync } from 'child_process';

function mustGetEnv(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`ERROR: ${name} not set`);
  return v;
}

function gitShortSha(): string {
  try {
    return execSync('git rev-parse --short HEAD', { cwd: process.cwd() }).toString('utf8').trim();
  } catch {
    return 'nogit';
  }
}

function playwrightVersion(): string {
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    return require('@playwright/test/package.json').version ?? 'unknown';
  } catch {
    return 'unknown';
  }
}

function ensureFile(runDir: string, rel: string, missing: string[]): void {
  const p = path.join(runDir, rel);
  if (!fs.existsSync(p) || !fs.statSync(p).isFile()) missing.push(rel);
}

function normalizePosix(rel: string): string {
  return rel.split(path.sep).join(path.posix.sep);
}

function mdLink(label: string, relPath: string): string {
  const target = `./${normalizePosix(relPath)}`;
  // Hard rules from plan v2:
  if (!target.startsWith('./')) throw new Error(`non-relative link: ${target}`);
  if (target.includes('://')) throw new Error(`url link forbidden: ${target}`);
  if (target.startsWith('/')) throw new Error(`absolute link forbidden: ${target}`);
  if (target.includes('\\')) throw new Error(`windows separator forbidden: ${target}`);
  if (target.includes('..')) throw new Error(`parent traversal forbidden: ${target}`);
  return `- [${label}](${target})`;
}

function walkFilesAbs(dirAbs: string): string[] {
  const out: string[] = [];
  if (!fs.existsSync(dirAbs)) return out;
  const st = fs.statSync(dirAbs);
  if (!st.isDirectory()) return out;
  const stack: string[] = [dirAbs];
  while (stack.length) {
    const d = stack.pop() as string;
    for (const ent of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, ent.name);
      if (ent.isDirectory()) stack.push(p);
      else if (ent.isFile()) out.push(p);
    }
  }
  return out;
}

export function buildIndex(): void {
  const runId = mustGetEnv('GAIAOS_RUN_ID');
  const runDir = path.resolve('apps/gaiaos_browser_cell/validation_artifacts', runId);
  const indexPath = path.join(runDir, 'INDEX.md');

  const required: string[] = [
    'diagnostics/server.log',
    'diagnostics/playwright.log',
    'diagnostics/browser_console.log',
    'diagnostics/network.har',
    'IQ/IQ.md',
    'IQ/transport_health.json',
    'IQ/transport_capabilities.json',
    'IQ/docker_ps.txt',
    'IQ/live_usdc_head.txt',
    'OQ/OQ_CELL.md',
    'OQ/OQ_HUMAN.md',
    'OQ/OQ_ASTRO.md',
    'OQ/perception_last.json',
    'OQ/audit_tail_10.jsonl',
    'OQ/perception_rejections_tail_20.ndjson',
    'PQ/PQ.md',
    'PQ/capabilities_after_resync.json',
    'PQ/sustained_ws_msgs.png',
    'PQ/ws_resync_connected.png',
    'meta/run_meta.json',
    'ui_worlds/cell/README.md',
    'ui_worlds/human/README.md',
    'ui_worlds/astro/README.md',
  ];

  // Required screenshot minimums (hard).
  const worlds = ['cell', 'human', 'astro'] as const;
  for (const w of worlds) {
    required.push(
      `ui_worlds/${w}/views/default.png`,
      `ui_worlds/${w}/views/zoomed.png`,
      `ui_worlds/${w}/views/global.png`,
      `ui_worlds/${w}/views/degraded_capability.png`,
      `ui_worlds/${w}/functions/perception_mark.png`,
    );
  }

  required.push('ui_worlds/cell/functions/perception_reject_toast.png');

  const missing: string[] = [];
  if (!fs.existsSync(runDir)) {
    throw new Error(`RUN_DIR does not exist: ${runDir}`);
  }
  for (const rel of required) ensureFile(runDir, rel, missing);
  if (missing.length) {
    const msg = missing.map((m) => `MISSING: ${path.join(runDir, m)}`).join('\n');
    throw new Error(`FAIL: missing required artifacts; not generating INDEX.md\n${msg}`);
  }

  const baseUrl = process.env.BROWSER_CELL_BASE_URL ?? '';
  const headerLines: string[] = [];
  headerLines.push('# GaiaOS Browser Cell Validation Evidence');
  headerLines.push('');
  headerLines.push(`- RUN_ID: \`${runId}\``);
  headerLines.push(`- RUN_DIR: \`${normalizePosix(path.relative(process.cwd(), runDir))}\``);
  headerLines.push(`- git_sha: \`${gitShortSha()}\``);
  headerLines.push(`- base_url: \`${baseUrl || '(unset)'}\``);
  headerLines.push(`- timestamp: \`${new Date().toISOString()}\``);
  headerLines.push(`- playwright_version: \`${playwrightVersion()}\``);
  headerLines.push(`- os: \`${os.platform()} ${os.release()} ${os.arch()}\``);

  const lines: string[] = [];
  lines.push(...headerLines);
  lines.push('');
  lines.push('## Diagnostics');
  lines.push(mdLink('server.log', 'diagnostics/server.log'));
  lines.push(mdLink('playwright.log', 'diagnostics/playwright.log'));
  lines.push(mdLink('browser_console.log', 'diagnostics/browser_console.log'));
  lines.push(mdLink('network.har', 'diagnostics/network.har'));

  const diagOptional = ['diagnostics/index_generator.log', 'diagnostics/har_probe.log'];
  for (const f of diagOptional) {
    if (fs.existsSync(path.join(runDir, f))) lines.push(mdLink(path.basename(f), f));
  }

  // Optional: present when a stop/failure occurs.
  const opt = ['diagnostics/stop_state.png', 'diagnostics/stop_state.webm', 'diagnostics/playwright_trace.zip'];
  for (const f of opt) {
    if (fs.existsSync(path.join(runDir, f))) lines.push(mdLink(path.basename(f), f));
  }

  lines.push('');
  lines.push('## IQ');
  lines.push(mdLink('IQ.md', 'IQ/IQ.md'));
  lines.push(mdLink('transport_health.json', 'IQ/transport_health.json'));
  lines.push(mdLink('transport_capabilities.json', 'IQ/transport_capabilities.json'));
  lines.push(mdLink('docker_ps.txt', 'IQ/docker_ps.txt'));
  lines.push(mdLink('live_usdc_head.txt', 'IQ/live_usdc_head.txt'));

  lines.push('');
  lines.push('## OQ');
  lines.push(mdLink('OQ_CELL.md', 'OQ/OQ_CELL.md'));
  lines.push(mdLink('OQ_HUMAN.md', 'OQ/OQ_HUMAN.md'));
  lines.push(mdLink('OQ_ASTRO.md', 'OQ/OQ_ASTRO.md'));
  lines.push(mdLink('perception_last.json', 'OQ/perception_last.json'));
  lines.push(mdLink('audit_tail_10.jsonl', 'OQ/audit_tail_10.jsonl'));

  lines.push('');
  lines.push('## PQ');
  lines.push(mdLink('PQ.md', 'PQ/PQ.md'));
  lines.push(mdLink('capabilities_after_resync.json', 'PQ/capabilities_after_resync.json'));
  lines.push(mdLink('sustained_ws_msgs.png', 'PQ/sustained_ws_msgs.png'));
  lines.push(mdLink('ws_resync_connected.png', 'PQ/ws_resync_connected.png'));

  lines.push('');
  lines.push('## Meta');
  lines.push(mdLink('run_meta.json', 'meta/run_meta.json'));

  // Machine-readable file manifest (generated here for auditability).
  const manifestPath = path.join(runDir, 'meta', 'file_manifest.json');
  const allFilesAbs = walkFilesAbs(runDir).sort();
  const manifest = allFilesAbs.map((abs) => {
    const st = fs.statSync(abs);
    return {
      path: normalizePosix(path.relative(runDir, abs)),
      bytes: st.size,
      mtime_ms: Math.trunc(st.mtimeMs),
    };
  });
  fs.mkdirSync(path.dirname(manifestPath), { recursive: true });
  fs.writeFileSync(manifestPath, JSON.stringify({ run_id: runId, ts: new Date().toISOString(), files: manifest }, null, 2) + '\n', {
    encoding: 'utf8',
  });
  lines.push(mdLink('file_manifest.json', 'meta/file_manifest.json'));

  lines.push('');
  lines.push('## World Screenshots');
  for (const w of worlds) {
    lines.push('');
    lines.push(`### ${w}`);
    lines.push(mdLink('README.md', `ui_worlds/${w}/README.md`));

    const abs = path.join(runDir, 'ui_worlds', w);
    const rels = walkFilesAbs(abs)
      .filter((p) => p.endsWith('.png') || p.endsWith('.md'))
      .map((p) => normalizePosix(path.relative(runDir, p)))
      .sort();
    for (const rel of rels) lines.push(mdLink(rel, rel));
  }

  lines.push('');
  lines.push('## Full File Listing');
  const all = walkFilesAbs(runDir)
    .map((p) => normalizePosix(path.relative(runDir, p)))
    .sort();
  for (const rel of all) lines.push(`- \`${rel}\``);

  fs.writeFileSync(indexPath, lines.join('\n') + '\n', { encoding: 'utf8' });
  // one-line confirmation for wrapper usage
  // eslint-disable-next-line no-console
  console.log(`OK: wrote ${indexPath}`);
}

if (require.main === module) {
  buildIndex();
}


