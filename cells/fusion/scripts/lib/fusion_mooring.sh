# GaiaFTCL — Fusion plant mesh mooring + payment eligibility (S4 / ops; settlement on gateway).
# Source after PROJ is set if you use fusion_payment_projection_json.
# Requires: jq. Optional: python3 for ISO8601 age (fallback: mesh considered stale if python missing).

GAIA_CLAIM="${GAIA_CLAIM:-${HOME}/.gaiaftcl}"
MOOR_STATE="${FUSION_MOORING_STATE_JSON:-$GAIA_CLAIM/fusion_mesh_mooring_state.json}"
MOOR_MAX="${FUSION_MESH_HEARTBEAT_MAX_SEC:-86400}"
LIVE_HW_JSON="${FUSION_LIVE_HARDWARE_JSON:-$GAIA_CLAIM/fusion_live_hardware.json}"

fusion_mooring_identity_ok() {
  [[ -f "$GAIA_CLAIM/cell_identity.json" ]] &&
    jq -e '.wallet and (.wallet | test("^0x[a-fA-F0-9]{40}$"))' "$GAIA_CLAIM/cell_identity.json" >/dev/null 2>&1
}

fusion_mooring_mount_ok() {
  [[ -f "$GAIA_CLAIM/mount_receipt.json" ]]
}

fusion_mooring_mesh_epoch_ok() {
  [[ -f "$MOOR_STATE" ]] || return 1
  local last
  last="$(jq -r '.last_mesh_ok_utc // empty' "$MOOR_STATE" 2>/dev/null)"
  [[ -n "$last" ]] || return 1
  local now line
  now="$(date +%s)"
  if command -v python3 >/dev/null 2>&1; then
    line="$(python3 -c "from datetime import datetime; import sys; d=datetime.fromisoformat(sys.argv[1].replace('Z','+00:00')); print(int(d.timestamp()))" "$last" 2>/dev/null)" || return 1
  else
    return 1
  fi
  local diff=$((now - line))
  [[ "$diff" -ge 0 ]] && [[ "$diff" -le "$MOOR_MAX" ]]
}

fusion_mooring_mesh_fresh() {
  fusion_mooring_mesh_epoch_ok
}

fusion_mooring_live_hardware_ok() {
  [[ "${FUSION_LIVE_HARDWARE_ATTESTED:-}" == "1" ]] && return 0
  [[ -f "$LIVE_HW_JSON" ]] && jq -e '.attested == true' "$LIVE_HW_JSON" >/dev/null 2>&1
}

fusion_payment_eligible() {
  fusion_mooring_identity_ok && fusion_mooring_mount_ok && fusion_mooring_mesh_fresh && fusion_mooring_live_hardware_ok
}

fusion_mesh_mooring_required_strict() {
  [[ "${FUSION_MESH_MOORING_REQUIRED:-0}" == "1" ]]
}

fusion_mooring_status_json() {
  local maxage="${MOOR_MAX:-86400}"
  [[ "$maxage" =~ ^[0-9]+$ ]] || maxage=86400
  jq -n \
    --arg moorfile "$MOOR_STATE" \
    --argjson maxage "$maxage" \
    --argjson identity_ok "$(fusion_mooring_identity_ok && echo true || echo false)" \
    --argjson mount_ok "$(fusion_mooring_mount_ok && echo true || echo false)" \
    --argjson mesh_fresh "$(fusion_mooring_mesh_fresh && echo true || echo false)" \
    --argjson live_hardware_ok "$(fusion_mooring_live_hardware_ok && echo true || echo false)" \
    --argjson payment_eligible "$(fusion_payment_eligible && echo true || echo false)" \
    '{
      mooring: {
        identity_ok: $identity_ok,
        mount_ok: $mount_ok,
        mesh_fresh: $mesh_fresh,
        live_hardware_ok: $live_hardware_ok,
        payment_eligible: $payment_eligible,
        mesh_state_file: $moorfile,
        mesh_max_age_sec: $maxage
      }
    }'
}

fusion_payment_projection_json() {
  local p="${PROJ:-}"
  [[ -n "$p" && -f "$p" ]] && jq -c '.payment_projection // {}' "$p" 2>/dev/null || echo "{}"
}
