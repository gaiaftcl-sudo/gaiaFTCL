#!/usr/bin/env bash
# Fusion plant stack — one orchestrator with receipts (no false "all green").
# After a run (especially with Next on :8910), capture catalog + live S4 proof:
#   bash scripts/fusion_plant_forensic.sh
#   FUSION_FORENSIC_SKIP_LIVE=1 …  # cold / no UI
# Tier 1: static (mesh mooring, Vitest fusion, optional sidecar verify, optional compose build).
# Tier 2: docker-compose.fusion-sidecar.yml up — gateway /health; /claims skipped unless substrate.
# Tier 3: optional Playwright (FUSION_PLANT_PLAYWRIGHT=1).
#
# Env:
#   FUSION_PLANT_BUILD=1           — docker compose build (slow).
#   VERIFY_FUSION_SIDECAR_XCODE=1  — xcodebuild FusionSidecarHost.
#   FUSION_PLANT_PLAYWRIGHT=1      — npm run test:e2e:fusion (needs dev stack / ports).
#   FUSION_PLANT_SKIP_COMPOSE=1    — skip Tier 2 (no Docker up/down).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EVIDENCE_DIR="$ROOT/evidence/fusion_control"
mkdir -p "$EVIDENCE_DIR"
REPORT_JSON="$EVIDENCE_DIR/FUSION_PLANT_STACK_VALIDATION.json"
pass=0
fail=0
steps_json="[]"

step_ok() {
  local name="$1"
  echo "PASS $name"
  pass=$((pass + 1))
  steps_json="$(jq -c --arg n "$name" --arg t "$TS" '. + [{step: $n, status: "PASS", at: $t}]' <<<"$steps_json")"
}

step_fail() {
  local name="$1"
  local detail="${2:-}"
  echo "FAIL $name ${detail:+$detail }"
  fail=$((fail + 1))
  steps_json="$(jq -c --arg n "$name" --arg t "$TS" --arg d "$detail" '. + [{step: $n, status: "FAIL", at: $t, detail: $d}]' <<<"$steps_json")"
}

echo "━━ Fusion plant stack orchestrator (GAIA_ROOT=$ROOT) ━━"

if [[ "${FUSION_PLANT_BUILD:-}" == "1" ]]; then
  if docker compose -f docker-compose.fusion-sidecar.yml build; then
    step_ok "docker_compose_fusion_sidecar_build"
  else
    step_fail "docker_compose_fusion_sidecar_build"
    exit 1
  fi
else
  step_ok "docker_compose_fusion_sidecar_build_skipped"
fi

if [[ "${VERIFY_FUSION_SIDECAR_XCODE:-}" == "1" ]]; then
  if VERIFY_FUSION_SIDECAR_XCODE=1 bash "$ROOT/scripts/verify_fusion_sidecar_bundle.sh"; then
    step_ok "verify_fusion_sidecar_bundle_xcode"
  else
    step_fail "verify_fusion_sidecar_bundle_xcode"
  fi
else
  if bash "$ROOT/scripts/verify_fusion_sidecar_bundle.sh"; then
    step_ok "verify_fusion_sidecar_bundle"
  else
    step_fail "verify_fusion_sidecar_bundle"
  fi
fi

if bash "$ROOT/scripts/test_fusion_mesh_mooring_stack.sh"; then
  step_ok "test_fusion_mesh_mooring_stack"
else
  step_fail "test_fusion_mesh_mooring_stack"
  exit 1
fi

if (cd "$ROOT/services/gaiaos_ui_web" && npm run test:unit:fusion); then
  step_ok "npm_test_unit_fusion"
else
  step_fail "npm_test_unit_fusion"
  exit 1
fi

cleanup_compose() {
  docker compose -f "$ROOT/docker-compose.fusion-sidecar.yml" down >/dev/null 2>&1 || true
}

if [[ "${FUSION_PLANT_SKIP_COMPOSE:-}" != "1" ]]; then
  cleanup_compose
  if docker compose -f "$ROOT/docker-compose.fusion-sidecar.yml" up -d; then
    step_ok "docker_compose_fusion_sidecar_up"
  else
    step_fail "docker_compose_fusion_sidecar_up"
    exit 1
  fi
  sleep 3
  if bash "$ROOT/scripts/preflight_mcp_gateway.sh"; then
    step_ok "preflight_mcp_gateway_live"
  else
    step_fail "preflight_mcp_gateway_live"
  fi
  export FUSION_PLANT_SKIP_CLAIMS_CURL=1
  if bash "$ROOT/scripts/test_fusion_discord_tier_a.sh"; then
    step_ok "test_fusion_discord_tier_a_gateway_slice"
  else
    step_fail "test_fusion_discord_tier_a_gateway_slice"
  fi
  unset FUSION_PLANT_SKIP_CLAIMS_CURL
  cleanup_compose
  step_ok "docker_compose_fusion_sidecar_down"
else
  step_ok "compose_tier_skipped"
fi

if [[ "${FUSION_PLANT_PLAYWRIGHT:-}" == "1" ]]; then
  if (cd "$ROOT/services/gaiaos_ui_web" && npm run test:e2e:fusion); then
    step_ok "npm_test_e2e_fusion"
  else
    step_fail "npm_test_e2e_fusion"
  fi
else
  step_ok "playwright_fusion_skipped"
fi

jq -n \
  --arg at "$TS" \
  --argjson p "$pass" \
  --argjson f "$fail" \
  --argjson steps "$steps_json" \
  '{
    generated_at_utc: $at,
    passed: $p,
    failed: $f,
    steps: $steps,
    notes: [
      "Tier A /claims with full JSON array requires live Arango (mesh tunnel or cell). FUSION_PLANT_SKIP_CLAIMS_CURL=1 used during compose tier.",
      "test:fusion:all in gaiaos_ui_web still enforces /claims; use mesh MCP_BASE_URL for full green."
    ]
  }' >"$REPORT_JSON"

echo "Wrote $REPORT_JSON"
echo "--- PASSED=$pass FAILED=$fail ---"
[[ "$fail" -eq 0 ]]
