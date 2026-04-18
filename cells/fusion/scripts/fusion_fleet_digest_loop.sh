#!/usr/bin/env bash
# Phase 3b optional: poll fleet-digest on an interval (operator-started only — not a default systemd surface).
# GATE3: HTTP GET only; compact JSON; no NATS jsonl bulk.
# Env: FUSION_SOVEREIGN_UI_URL (default http://127.0.0.1:8910), FUSION_FLEET_DIGEST_INTERVAL_SEC (default 3600).
set -euo pipefail
BASE="${FUSION_SOVEREIGN_UI_URL:-http://127.0.0.1:8910}"
BASE="${BASE%/}"
INT="${FUSION_FLEET_DIGEST_INTERVAL_SEC:-3600}"
echo "[fusion_fleet_digest_loop] polling $BASE/api/fusion/fleet-digest every ${INT}s (Ctrl+C to stop)"
while true; do
  if command -v curl >/dev/null 2>&1; then
    tmp="$(mktemp)" || exit 2
    code="000"
    code="$(curl -sS -o "$tmp" -w "%{http_code}" "$BASE/api/fusion/fleet-digest" 2>/dev/null || echo "000")"
    echo "[fusion_fleet_digest_loop] HTTP $code bytes $(wc -c <"$tmp" 2>/dev/null | tr -d " ")"
    head -c 8192 "$tmp" 2>/dev/null || true
    echo ""
    rm -f "$tmp"
  else
    echo "REFUSED: curl required"
    exit 2
  fi
  sleep "$INT"
done
