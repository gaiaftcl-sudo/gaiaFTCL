#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# Check ONLY UI entrypoints / config that affect runtime loading.
# Intentionally excludes vendored libraries (they may contain URLs in comments).
TARGETS=(
  "${ROOT_DIR}/apps/gaiaos_browser_cell/web/index.html"
  "${ROOT_DIR}/apps/gaiaos_browser_cell/public"
)

FAIL=0

for t in "${TARGETS[@]}"; do
  if [[ -d "$t" ]]; then
    # Exclude vendored code from checks.
    MATCHES="$(rg -n --no-messages 'https?://' "$t" --glob '!**/vendor/**' || true)"
  else
    MATCHES="$(rg -n --no-messages 'https?://' "$t" || true)"
  fi

  if [[ -n "$MATCHES" ]]; then
    echo "FAIL: remote dependency detected in ${t}"
    echo "$MATCHES"
    FAIL=1
  fi
done

if [[ "$FAIL" -ne 0 ]]; then
  exit 2
fi

echo "PASS: no remote UI dependencies detected"


