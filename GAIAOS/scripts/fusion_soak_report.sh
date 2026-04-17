#!/usr/bin/env bash
# Emit evidence/fusion_control/FUSION_SOAK_TEST_REPORT.md from JSONL tails + last receipt (Node aggregate).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EV="$ROOT/evidence/fusion_control"
OUT="${FUSION_SOAK_REPORT_OUT:-$EV/FUSION_SOAK_TEST_REPORT.md}"
mkdir -p "$EV"

GAIA_ROOT="$ROOT" FUSION_SOAK_REPORT_OUT="$OUT" node -e "
const path = require('path');
const fs = require('fs/promises');
const root = process.env.GAIA_ROOT;
const out = process.env.FUSION_SOAK_REPORT_OUT;
const { buildSoakSummary, formatSoakMarkdown } = require(path.join(root, 'scripts', 'lib', 'fusion_soak_summary.cjs'));
(async () => {
  const s = await buildSoakSummary(root);
  await fs.writeFile(out, formatSoakMarkdown(s), 'utf8');
  console.log('[fusion_soak_report] wrote', out);
})().catch((e) => { console.error(e); process.exit(1); });
"
