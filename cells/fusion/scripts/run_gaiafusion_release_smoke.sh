#!/usr/bin/env bash
# GaiaFusion Mac app — release smoke: swift build/test (compile hygiene) then canonical working-app verify.
# The verify script (not XCTest alone) is operator truth: composite → gate → self-probe → /_next → Mac :8803 → WAN mesh MCP.
#
# Env (passed through to verify_gaiafusion_working_app.sh): e.g. GAIAFUSION_SKIP_MESH_MCP=1 or
# GAIAFUSION_SKIP_MAC_CELL_MCP=1 for sandbox/CI without local gateway or WAN; production loop expects both phases CURE.
#
# Optional preflight (repo artifacts + docker compose config, no Xcode):
#   GAIAFUSION_RELEASE_PREFLIGHT_SIDECAR_BUNDLE=1 bash scripts/run_gaiafusion_release_smoke.sh
#
# CI / compile-only spine (native USD + Swift compile; no Playwright / mesh):
#   GAIAFUSION_SKIP_XCTEST=1 GAIAFUSION_SKIP_WORKING_APP_VERIFY=1 bash scripts/run_gaiafusion_release_smoke.sh
#
# UsdProbeCLI may SIGKILL (rc 137) in some IDE/sandbox hosts — not host-Mac C4:
#   GAIAFUSION_USD_PROBE_SIGKILL_OK=1 … continues after probe with receipt note (PARTIAL for pxr load).
# Or skip the binary entirely:
#   GAIAFUSION_SKIP_USD_PROBE_CLI=1 …
#
# Host Mac (arm64, non-CI): GAIAFUSION_SKIP_* cleared — see scripts/lib/gaiafusion_host_c4_lock.sh
# Override: GAIAFUSION_ALLOW_SKIP_ON_HOST=1
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=/dev/null
source "${ROOT}/scripts/lib/gaiafusion_host_c4_lock.sh"
gaiafusion_host_strip_skip_leak

if [[ "${GAIAFUSION_RELEASE_PREFLIGHT_SIDECAR_BUNDLE:-0}" == "1" ]]; then
  echo "━━ Preflight: verify_fusion_sidecar_bundle.sh ━━"
  bash "$ROOT/scripts/verify_fusion_sidecar_bundle.sh"
fi
EV="$ROOT/evidence/fusion_control"
mkdir -p "$EV"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RECEIPT="$EV/gaiafusion_release_smoke_receipt.json"

echo "━━ GaiaFusion release smoke (GAIAOS=$ROOT) ━━"

SWIFT_LOG="$(mktemp "${TMPDIR:-/tmp}/gaiafusion_swift_test.XXXXXX")"
cleanup() { rm -f "$SWIFT_LOG"; }
trap cleanup EXIT

if ! (cd "$ROOT/macos/GaiaFusion" && swift build); then
  jq -n \
    --arg ts "$TS" \
    '{schema: "gaiaftcl_gaiafusion_release_smoke_v2", ts_utc: $ts, terminal: "REFUSED", step: "swift_build", rc: 1}' >"$RECEIPT"
  echo "REFUSED: swift build failed — receipt $RECEIPT"
  exit 1
fi

echo "━━ USD_Core @rpath + on-disk framework (production linkage witness) ━━"
bash "${ROOT}/scripts/verify_gaiafusion_usd_runtime_link.sh" || {
  jq -n \
    --arg ts "$TS" \
    '{schema: "gaiaftcl_gaiafusion_release_smoke_v2", ts_utc: $ts, terminal: "REFUSED", step: "usd_runtime_link_verify", rc: 1}' >"$RECEIPT"
  echo "REFUSED: verify_gaiafusion_usd_runtime_link.sh — receipt $RECEIPT"
  exit 1
}

echo "━━ USD monolithic probe (UsdProbeCLI → pxr in-memory stage) ━━"
USD_PROBE_RC=0
USD_PROBE_OUT=""
USD_PROBE_SKIPPED=0
USD_PROBE_SIGKILL_OK=0
if [[ "${GAIAFUSION_SKIP_USD_PROBE_CLI:-0}" == "1" ]]; then
  echo "Skipping UsdProbeCLI (GAIAFUSION_SKIP_USD_PROBE_CLI=1)"
  USD_PROBE_SKIPPED=1
  usd_probe_rc=0
elif USD_PROBE_OUT="$(cd "$ROOT/macos/GaiaFusion" && BIN="$(swift build --show-bin-path)" && DYLD_FRAMEWORK_PATH="$BIN" "$BIN/UsdProbeCLI" 2>&1)"; then
  usd_probe_rc=0
else
  usd_probe_rc=$?
fi
USD_PROBE_RC="$usd_probe_rc"
echo "$USD_PROBE_OUT"
if [[ "$usd_probe_rc" -ne 0 ]]; then
  if [[ "$usd_probe_rc" -eq 137 && "${GAIAFUSION_USD_PROBE_SIGKILL_OK:-0}" == "1" ]]; then
    echo "PARTIAL: UsdProbeCLI rc=137 (SIGKILL) — continuing (GAIAFUSION_USD_PROBE_SIGKILL_OK=1); run on a full Mac for pxr load witness."
    USD_PROBE_SIGKILL_OK=1
  else
    jq -n \
      --arg ts "$TS" \
      --argjson rc "$usd_probe_rc" \
      --arg out "${USD_PROBE_OUT}" \
      '{schema: "gaiaftcl_gaiafusion_release_smoke_v2", ts_utc: $ts, terminal: "REFUSED", step: "usd_probe_cli", rc: $rc, usd_probe_output: $out}' >"$RECEIPT"
    echo "REFUSED: UsdProbeCLI failed (rc=$usd_probe_rc) — receipt $RECEIPT"
    exit "$usd_probe_rc"
  fi
fi

# XCTest: use --disable-sandbox so subprocess can load USD-linked test bundles on some hosts.
# GAIAFUSION_SKIP_XCTEST=1 — skip tests (e.g. CI that cannot execute native USD); build + USD probe must still pass.
swift_rc=0
XCTEST_TOTAL=""
if [[ "${GAIAFUSION_SKIP_XCTEST:-0}" == "1" ]]; then
  echo "━━ Skipping swift test (GAIAFUSION_SKIP_XCTEST=1) ━━"
else
  if (cd "$ROOT/macos/GaiaFusion" && swift test --disable-sandbox 2>&1 | tee "$SWIFT_LOG"); then
    swift_rc=0
  else
    swift_rc=$?
  fi
  XCTEST_TOTAL="$(grep -E 'Executed [0-9]+ tests' "$SWIFT_LOG" 2>/dev/null | tail -1 | sed -n 's/.*Executed \([0-9][0-9]*\) tests.*/\1/p' || true)"
fi

if [[ "$swift_rc" -ne 0 ]]; then
  jq -n \
    --arg ts "$TS" \
    --argjson rc "$swift_rc" \
    --arg xraw "${XCTEST_TOTAL}" \
    --argjson usd_probe_rc "$USD_PROBE_RC" \
    --argjson usd_skipped "$USD_PROBE_SKIPPED" \
    --argjson usd_sigkill_ok "$USD_PROBE_SIGKILL_OK" \
    '{schema: "gaiaftcl_gaiafusion_release_smoke_v2", ts_utc: $ts, terminal: "REFUSED", step: "swift_test", rc: $rc, usd_probe_cli_rc: $usd_probe_rc, usd_probe_cli_skipped: ($usd_skipped == 1), usd_probe_sigkill_continued: ($usd_sigkill_ok == 1), swift_xctest_executed: (if ($xraw|length) == 0 then null else ($xraw|tonumber) end)}' >"$RECEIPT"
  echo "REFUSED: swift test failed (rc=$swift_rc) — receipt $RECEIPT"
  exit "$swift_rc"
fi

VERIFY_REL="scripts/verify_gaiafusion_working_app.sh"
VERIFY_RECEIPT_REL="evidence/fusion_control/gaiafusion_working_app_verify_receipt.json"
GATE_REL="evidence/fusion_control/fusion_mac_app_gate_receipt.json"

if [[ "${GAIAFUSION_SKIP_WORKING_APP_VERIFY:-0}" == "1" ]]; then
  echo "━━ Skipping verify_gaiafusion_working_app.sh (GAIAFUSION_SKIP_WORKING_APP_VERIFY=1) ━━"
  verify_rc=0
  jq -n \
    --arg ts "$TS" \
    --arg verify_script "$VERIFY_REL" \
    --arg verify_receipt "$VERIFY_RECEIPT_REL" \
    --arg gate_path "$GATE_REL" \
    --arg xraw "${XCTEST_TOTAL}" \
    --argjson usd_probe_rc "$USD_PROBE_RC" \
    --argjson usd_skipped "$USD_PROBE_SKIPPED" \
    --argjson usd_sigkill_ok "$USD_PROBE_SIGKILL_OK" \
    '{
      schema: "gaiaftcl_gaiafusion_release_smoke_v2",
      ts_utc: $ts,
      terminal: "PARTIAL",
      swift_build_test_rc: 0,
      usd_probe_cli_rc: $usd_probe_rc,
      usd_probe_cli_skipped: ($usd_skipped == 1),
      usd_probe_sigkill_continued: ($usd_sigkill_ok == 1),
      swift_xctest_executed: (if ($xraw|length) == 0 then null else ($xraw|tonumber) end),
      working_app_verify_script: $verify_script,
      working_app_verify_rc: null,
      working_app_verify_receipt: $verify_receipt,
      fusion_mac_app_gate_receipt: $gate_path,
      working_app_verify: "SKIPPED"
    }' >"$RECEIPT"
  echo "PARTIAL: release smoke stopped before working-app verify — $RECEIPT"
  exit 0
fi

if bash "$ROOT/$VERIFY_REL"; then
  verify_rc=0
else
  verify_rc=$?
fi

jq -n \
  --arg ts "$TS" \
  --argjson verify_rc "$verify_rc" \
  --arg verify_script "$VERIFY_REL" \
  --arg verify_receipt "$VERIFY_RECEIPT_REL" \
  --arg gate_path "$GATE_REL" \
  --arg xraw "${XCTEST_TOTAL}" \
  --argjson usd_probe_rc "$USD_PROBE_RC" \
  --argjson usd_skipped "$USD_PROBE_SKIPPED" \
  --argjson usd_sigkill_ok "$USD_PROBE_SIGKILL_OK" \
  '{
    schema: "gaiaftcl_gaiafusion_release_smoke_v2",
    ts_utc: $ts,
    terminal: (if $verify_rc == 0 then "CURE" else "REFUSED" end),
    swift_build_test_rc: 0,
    usd_probe_cli_rc: $usd_probe_rc,
    usd_probe_cli_skipped: ($usd_skipped == 1),
    usd_probe_sigkill_continued: ($usd_sigkill_ok == 1),
    swift_xctest_executed: (if ($xraw|length) == 0 then null else ($xraw|tonumber) end),
    working_app_verify_script: $verify_script,
    working_app_verify_rc: $verify_rc,
    working_app_verify_receipt: $verify_receipt,
    fusion_mac_app_gate_receipt: $gate_path
  }' >"$RECEIPT"

if [[ "$verify_rc" -ne 0 ]]; then
  echo "REFUSED: verify_gaiafusion_working_app.sh rc=$verify_rc — $RECEIPT"
  exit "$verify_rc"
fi

echo "CURE: GaiaFusion release smoke — $RECEIPT"
exit 0
