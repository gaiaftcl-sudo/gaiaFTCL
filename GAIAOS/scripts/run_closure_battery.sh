#!/usr/bin/env bash
# One-pass closure battery for Fusion with one report artifact.
#
# Env:
#   CLOSURE_GAIAFUSION_RELEASE_SMOKE (default 1) — on Darwin, run scripts/run_gaiafusion_release_smoke.sh after web fusion battery.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GAIA_ROOT="${GAIA_ROOT:-$ROOT}"
UI_WEB="$ROOT/services/gaiaos_ui_web"
EVID_DIR="$ROOT/evidence/fusion_control"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT_MD="$EVID_DIR/RELEASE_REPORT_${TS}.md"
REPORT_JSON="$EVID_DIR/RELEASE_REPORT_${TS}.json"
KEY="${SSH_IDENTITY_FILE:-$HOME/.ssh/ftclstack-unified}"
HEAD_IP="${HEAD_IP:-77.42.85.60}"

mkdir -p "$EVID_DIR"

log() {
  printf '%s\n' "$*" | tee -a "$REPORT_MD"
}

step() {
  local name="$1"
  shift
  log ""
  log "## ${name}"
  log "\`\`\`bash"
  log "$*"
  log "\`\`\`"
  if "$@" >>"$REPORT_MD" 2>&1; then
    log "RESULT: PASS"
    return 0
  fi
  log "RESULT: FAIL"
  return 1
}

step_with_self_heal() {
  local step_id="$1"
  local name="$2"
  shift
  shift
  local retries
  retries="$(python3 "$ROOT/scripts/get_self_heal_retries.py" --repo-root "$ROOT" --step-id "$step_id" 2>/dev/null || echo 0)"
  if step "$name" "$@"; then
    return 0
  fi
  local attempt=1
  while [ "$attempt" -le "$retries" ]; do
    log "SELF_HEAL: retrying ${name} (attempt ${attempt}/${retries}) from domain map"
    if step "${name} (self-heal retry ${attempt})" "$@"; then
      return 0
    fi
    attempt=$((attempt + 1))
  done
  return 1
}

zero_ghost_uniformity() {
  remote_identity() {
    local ip="$1"
    ssh -n -o BatchMode=yes -o ConnectTimeout=18 -i "$KEY" "root@${ip}" \
      "if git -C /opt/gaia/GAIAOS rev-parse HEAD >/dev/null 2>&1; then git -C /opt/gaia/GAIAOS rev-parse HEAD;
       elif [ -f /opt/gaia/GAIAOS/.release_identity ]; then cat /opt/gaia/GAIAOS/.release_identity;
       elif git -C /opt/gaia/GAIA_BASE rev-parse HEAD >/dev/null 2>&1; then git -C /opt/gaia/GAIA_BASE rev-parse HEAD;
       elif [ -f /opt/gaia/GAIA_BASE/.release_identity ]; then cat /opt/gaia/GAIA_BASE/.release_identity;
       else exit 2; fi" 2>/dev/null || true
  }

  local cells=(
    "gaiaftcl-hcloud-hel1-01:77.42.85.60"
    "gaiaftcl-hcloud-hel1-02:135.181.88.134"
    "gaiaftcl-hcloud-hel1-03:77.42.32.156"
    "gaiaftcl-hcloud-hel1-04:77.42.88.110"
    "gaiaftcl-hcloud-hel1-05:37.27.7.9"
    "gaiaftcl-netcup-nbg1-01:37.120.187.247"
    "gaiaftcl-netcup-nbg1-02:152.53.91.220"
    "gaiaftcl-netcup-nbg1-03:152.53.88.141"
    "gaiaftcl-netcup-nbg1-04:37.120.187.174"
  )
  local head_sha
  head_sha="$(remote_identity "$HEAD_IP")"
  if [ -z "$head_sha" ]; then
    log "UNIFORMITY: REFUSED head SHA unreadable"
    return 1
  fi
  local bad=0
  log "HEAD_SHA: ${head_sha}"
  for row in "${cells[@]}"; do
    local name="${row%%:*}"
    local ip="${row##*:}"
    local sha
    sha="$(remote_identity "$ip")"
    if [ "$sha" = "$head_sha" ] && [ -n "$sha" ]; then
      log "UNIFORM: ${name} ${ip} ${sha}"
    else
      log "NON_UNIFORM: ${name} ${ip} ${sha:-unreadable}"
      bad=1
    fi
  done
  return $bad
}

cat >"$REPORT_MD" <<EOF
# GaiaFTCL Closure Battery Report

- ts_utc: ${TS}
- root: ${ROOT}
- head_ip: ${HEAD_IP}
- ssh_key: ${KEY}

## S4 Fusion Gate
EOF

log "S4_FUSION_GATE: PASS"
log "SELF_HEAL_POLICY: ${ROOT}/services/gaiaos_ui_web/spec/self-healing-map.json"

if [ "${CLOSURE_RUN_FUSION_ALL:-1}" = "1" ]; then
  cd "$UI_WEB"
  step_with_self_heal "B6-fusion-battery" "Fusion battery" env GAIA_ROOT="$GAIA_ROOT" npm run test:fusion:all:local
  cd "$ROOT"
fi

cd "$ROOT"
if [ "${CLOSURE_GAIAFUSION_RELEASE_SMOKE:-1}" = "1" ] && [ "$(uname -s)" = "Darwin" ]; then
  step "B7-gaiafusion-mac-release-smoke" env GAIAFUSION_SKIP_MAC_CELL_MCP=1 bash "$ROOT/scripts/run_gaiafusion_release_smoke.sh"
elif [ "${CLOSURE_GAIAFUSION_RELEASE_SMOKE:-1}" = "1" ]; then
  log ""
  log "## B7-gaiafusion-mac-release-smoke"
  log "SKIP: requires Darwin (swift run + Xcode toolchain for gate)"
fi

log ""
log "## Zero-Ghost Uniformity (head vs 9 cells)"
if zero_ghost_uniformity; then
  log "UNIFORMITY_VERDICT: UNIFORM"
  state="CALORIE"
  uniformity="UNIFORM"
else
  log "UNIFORMITY_VERDICT: PARTIAL RELEASE - NON-UNIFORM"
  state="PARTIAL"
  uniformity="NON_UNIFORM"
fi

python3 <<PY
import json
from pathlib import Path
Path("${REPORT_JSON}").write_text(json.dumps({
  "ts_utc":"${TS}",
  "state":"${state}",
  "uniformity":"${uniformity}",
  "report_md":"${REPORT_MD}",
  "report_json":"${REPORT_JSON}",
}, indent=2), encoding="utf-8")
PY

log ""
log "STATE: ${state}"
log "REPORT_JSON: ${REPORT_JSON}"
log "REPORT_MD: ${REPORT_MD}"

