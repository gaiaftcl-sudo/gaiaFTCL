#!/usr/bin/env zsh
# Build a single owner sign-off pack from external-loop evidence.
set -euo pipefail
emulate -LR zsh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRANKLIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$FRANKLIN_DIR/../.." && pwd)"

EVD_ROOT="$REPO_ROOT/cells/health/evidence/mac_gamp5_external_loop"
OUT_ROOT="$REPO_ROOT/cells/health/evidence/mac_gamp5_signoff"
mkdir -p "$OUT_ROOT"

RUN_ID="${1:-}"
if [[ -z "$RUN_ID" ]]; then
  RUN_ID="$(ls -1 "$EVD_ROOT" 2>/dev/null | sort -r | head -n 1 || true)"
fi
if [[ -z "$RUN_ID" ]]; then
  echo "REFUSED: no external loop run found under $EVD_ROOT" >&2
  exit 1
fi

RUN_DIR="$EVD_ROOT/$RUN_ID"
[[ -d "$RUN_DIR" ]] || { echo "REFUSED: missing run dir $RUN_DIR" >&2; exit 1; }

TS="$(date -u "+%Y-%m-%dT%H%M%SZ")"
PACK_DIR="$OUT_ROOT/signoff_${RUN_ID}_${TS}"
mkdir -p "$PACK_DIR"

cp -R "$RUN_DIR" "$PACK_DIR/run"
if [[ -d "$EVD_ROOT/receipts" ]]; then
  cp -R "$EVD_ROOT/receipts" "$PACK_DIR/receipts"
fi
if [[ -d "$EVD_ROOT/visual" ]]; then
  cp -R "$EVD_ROOT/visual" "$PACK_DIR/visual"
fi
if [[ -d "$EVD_ROOT/screenshots" ]]; then
  cp -R "$EVD_ROOT/screenshots" "$PACK_DIR/screenshots"
fi

MANIFEST="$PACK_DIR/signoff_manifest.json"
{
  printf '{\n'
  printf '  "schema": "mac_gamp5_signoff_pack_v1",\n'
  printf '  "run_id": "%s",\n' "$RUN_ID"
  printf '  "repo_root": "%s",\n' "$REPO_ROOT"
  printf '  "files": [\n'
  first=1
  while IFS= read -r f; do
    rel="${f#$PACK_DIR/}"
    sha="$(shasum -a 256 "$f" | awk '{print $1}')"
    bytes="$(stat -f%z "$f" 2>/dev/null || wc -c < "$f" | tr -d ' ')"
    esc_rel="$(printf '%s' "$rel" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    if [[ $first -eq 0 ]]; then
      printf ',\n'
    fi
    printf '    {"path":"%s","sha256":"%s","bytes":%s}' "$esc_rel" "$sha" "$bytes"
    first=0
  done < <(find "$PACK_DIR" -type f ! -name "signoff_manifest.json" | sort)
  printf '\n  ]\n'
  printf '}\n'
} > "$MANIFEST"
echo "Wrote $MANIFEST"

echo "PASS: signoff pack created at $PACK_DIR"
