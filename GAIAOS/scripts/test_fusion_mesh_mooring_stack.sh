#!/usr/bin/env bash
# Regression: fusion projection, mooring lib, bridges, JSONL merge shape, heartbeat REFUSED without NATS/setup.
# Run from repo: bash scripts/test_fusion_mesh_mooring_stack.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PROJ="${FUSION_PROJECTION_JSON:-$ROOT/deploy/fusion_mesh/fusion_projection.json}"

# shellcheck source=/dev/null
source "$ROOT/scripts/lib/fusion_mooring.sh"

pass=0
fail=0
ok() { echo "PASS $1"; pass=$((pass + 1)); }
bad() { echo "FAIL $1"; fail=$((fail + 1)); }

for f in \
  scripts/fusion_turbo_ide.sh \
  scripts/fusion_cell_long_run_runner.sh \
  scripts/best_control_test_ever.sh \
  deploy/mac_cell_mount/bin/fusion_mesh_mooring_heartbeat.sh \
  deploy/mac_cell_mount/bin/mcp_bridge_torax \
  deploy/mac_cell_mount/bin/mcp_bridge_marte2; do
  bash -n "$f" && ok "bash_n ${f##*/}" || bad "bash_n $f"
done

jq -e '.payment_projection.plant_mooring_capital_eur_per_kw == 2500' "$PROJ" >/dev/null && ok projection_payment || bad projection_payment
fusion_payment_projection_json | jq -e '.plant_mooring_capital_eur_per_kw == 2500' >/dev/null && ok payment_proj_fn || bad payment_proj_fn
fusion_mooring_status_json | jq -e '.mooring.payment_eligible == false' >/dev/null && ok mooring_status || bad mooring_status

# Bridges exit 1 on REFUSED — do not let assignment inherit failure under set -e
tx=$(./deploy/mac_cell_mount/bin/mcp_bridge_torax 2>/dev/null) || true
echo "$tx" | jq -e '.reason == "invoke_unset"' >/dev/null && ok torax_refused || bad torax_refused
mt=$(./deploy/mac_cell_mount/bin/mcp_bridge_marte2 2>/dev/null) || true
echo "$mt" | jq -e '.reason == "invoke_unset"' >/dev/null && ok marte2_refused || bad marte2_refused

APP="$ROOT/services/fusion_control_mac/dist/FusionControl.app/Contents/MacOS/fusion_control"
if [[ ! -x "$APP" ]]; then
  bad "fusion_control binary missing (build FusionControl.app first)"
else
  OUT=$("$APP" 2>/dev/null) || true
  mstat=$(fusion_mooring_status_json)
  ppay=$(fusion_payment_projection_json)
  s4=$(jq -c '{plant_flavor: (.plant_flavor // "generic"), dif_profile: (.dif_profile // "default"), benchmark_surface_id: (.benchmark_surface_id // "")}' "$PROJ")
  echo "$OUT" | jq -e . >/dev/null || bad "fusion_control stdout not JSON"
  echo "$OUT" | jq -c --argjson iter 999 --argjson ec 0 --arg ts "2026-01-01T00:00:00Z" --arg mode virtual --arg cid testcell --argjson s4 "$s4" --argjson mstat "$mstat" --argjson payproj "$ppay" '. + {control_signal: "fusion_cell_batch", iter: $iter, ts: $ts, exit_code: $ec, tokamak_mode: $mode, cell_id: $cid} + $s4 + $mstat + {payment_projection: $payproj}' | jq -e '.mooring.payment_eligible == false and .payment_projection.plant_mooring_capital_eur_per_kw == 2500' >/dev/null && ok jsonl_merge || bad jsonl_merge
fi

mstat=$(fusion_mooring_status_json)
ppay=$(fusion_payment_projection_json)
s4=$(jq -c '{plant_flavor: (.plant_flavor // "generic"), dif_profile: (.dif_profile // "default"), benchmark_surface_id: (.benchmark_surface_id // "")}' "$PROJ")
jq -n --argjson iter 1 --arg ts "2026-01-01T00:00:00Z" --argjson s4 "$s4" --argjson mstat "$mstat" --argjson payproj "$ppay" '{control_signal: "fusion_mooring_degraded", reason: "mesh_heartbeat_stale_or_missing", iter: $iter, ts: $ts} + $s4 + $mstat + {payment_projection: $payproj}' | jq -e '.control_signal == "fusion_mooring_degraded"' >/dev/null && ok degraded_shape || bad degraded_shape

out=$(./deploy/mac_cell_mount/bin/fusion_mesh_mooring_heartbeat.sh 2>&1) || true
echo "$out" | grep -q REFUSED && ok heartbeat_refused_no_setup || bad heartbeat_refused_no_setup

bash "$ROOT/scripts/best_control_test_ever.sh" >/dev/null && ok best_control || bad best_control

echo "--- PASSED=$pass FAILED=$fail ---"
[[ "$fail" -eq 0 ]]
