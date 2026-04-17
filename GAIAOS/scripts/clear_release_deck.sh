#!/usr/bin/env bash
# Clear stale release artifacts so a full spine cannot pass on yesterday's REPORT alone.
# Moves (does not delete) into evidence/release/_cleared_deck_<ts>/ for audit recovery.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
ARCH="$ROOT/evidence/release/_cleared_deck_${TS}"
mkdir -p "$ARCH"

n=0
move_one() {
  local f="$1"
  if [[ -e "$f" ]]; then
    mv "$f" "$ARCH/"
    n=$((n + 1))
  fi
}

shopt -s nullglob
for f in "$ROOT/evidence/discord"/RELEASE_REPORT_*.json "$ROOT/evidence/discord"/RELEASE_REPORT_*.md; do
  move_one "$f"
done
for f in "$ROOT/evidence/release"/SESSION_RELEASE_RECEIPT_*.json "$ROOT/evidence/release"/SESSION_RELEASE_LOG_*.txt; do
  move_one "$f"
done
shopt -u nullglob

RECEIPT="$ROOT/evidence/release/CLEAR_DECK_RECEIPT_${TS}.json"
export ROOT TS ARCH RECEIPT
export n
python3 <<'PY'
import json, os
from pathlib import Path
rec = {
    "schema": "clear_deck_receipt_v1",
    "ts_utc": os.environ["TS"],
    "archive_dir": os.environ["ARCH"],
    "files_moved": int(os.environ["n"]),
    "note": "Stale RELEASE_REPORT / SESSION logs archived — next spine is authoritative.",
}
Path(os.environ["RECEIPT"]).write_text(json.dumps(rec, indent=2), encoding="utf-8")
PY

echo "CLEAR_DECK_ARCHIVE=$ARCH"
echo "CLEAR_DECK_RECEIPT=$RECEIPT"
echo "CLEAR_DECK_FILES_MOVED=$n"
