#!/usr/bin/env bash
# owl_nutrition_iqoqpq_validate.sh — OWL-NUTRITION IQ / OQ / PQ local validation
#
# IQ:  documentation + schema files + WASM crate wiring + JSON Schema validation (venv)
# OQ:  cargo clean (fresh) + full unit tests for gaia-health-substrate (C4 adversarial + digest)
# PQ:  determinism tests (PQ-N-MESH-001) included in same test run; receipt written
#
# Run from anywhere:
#   bash cells/health/scripts/owl_nutrition_iqoqpq_validate.sh
#
# Requires: Rust toolchain, python3, network for first-time pip (jsonschema).
# Does NOT run interactive iq_install.sh (wallet / license).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEALTH_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
NUTRITION_DOC="${HEALTH_ROOT}/docs/invariants/OWL-NUTRITION"
SCHEMA_DIR="${HEALTH_ROOT}/schemas/nutrition"
WASM_DIR="${HEALTH_ROOT}/wasm_constitutional"
EVIDENCE="${NUTRITION_DOC}/evidence"
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
RECEIPT="${EVIDENCE}/owl_nutrition_iqoqpq_receipt.json"

log() { printf "\n\033[0;36m== %s ==\033[0m\n" "$*"; }
ok()  { printf "  \033[0;32mPASS\033[0m %s\n" "$*"; }
bad() { printf "  \033[0;31mFAIL\033[0m %s\n" "$*" >&2; exit 1; }

log "IQ — OWL-NUTRITION (installation qualification)"

[[ -f "${NUTRITION_DOC}/README.md" ]] || bad "IQ-N-1 missing README"
ok "IQ-N-1 OWL-NUTRITION tree present"

[[ -f "${SCHEMA_DIR}/user_nutrition_profile.schema.json" ]] \
  && [[ -f "${SCHEMA_DIR}/nutrition_monitoring_config.schema.json" ]] \
  && [[ -f "${SCHEMA_DIR}/nutrition_s4_evidence.schema.json" ]] \
  && [[ -f "${SCHEMA_DIR}/nutrition_c4_filter_declaration.schema.json" ]] \
  || bad "IQ-N-2 four schemas missing"
ok "IQ-N-2 four JSON Schemas present"

grep -q "pub mod nutrition" "${WASM_DIR}/src/lib.rs" || bad "IQ-N-3 nutrition module not registered in lib.rs"
grep -q "nutrition_audit_event_digest" "${WASM_DIR}/src/nutrition.rs" || bad "IQ-N-3 audit digest export missing"
ok "IQ-N-3 WASM nutrition exports present"

# Python venv + jsonschema (fresh deps for this run)
VENV="${SCHEMA_DIR}/.venv"
log "IQ — Python venv + jsonschema (schema validation)"
python3 -m venv "${VENV}"
"${VENV}/bin/pip" install -q --upgrade pip
"${VENV}/bin/pip" install -q jsonschema
export NUTRITION_SCHEMA_STRICT=1
( cd "${SCHEMA_DIR}" && "${VENV}/bin/python" validate_nutrition_schemas.py ) || bad "IQ schema fixture validation failed"
ok "IQ JSON Schema fixtures (all four schemas)"

log "OQ + PQ — Operational + Performance (synthetic) — cargo clean + test"

cd "${HEALTH_ROOT}"
cargo clean -p gaia-health-substrate
cargo test -p gaia-health-substrate -- --nocapture || bad "OQ/PQ: cargo test failed"

ok "OQ: adversarial C4 + projection; PQ: digest determinism + PQ-N-MESH-001"

mkdir -p "${EVIDENCE}/iq" "${EVIDENCE}/oq" "${EVIDENCE}/pq"

GIT_SHA=""
if command -v git &>/dev/null && git -C "${HEALTH_ROOT}/../.." rev-parse HEAD &>/dev/null; then
  GIT_SHA="$(git -C "${HEALTH_ROOT}/../.." rev-parse HEAD)"
fi

cat > "${RECEIPT}" <<EOF
{
  "receipt_kind": "OWL-NUTRITION-IQOQPQ",
  "timestamp_utc": "${TS}",
  "git_sha": "${GIT_SHA}",
  "iq": {
    "status": "PASS",
    "checks": ["IQ-N-1", "IQ-N-2", "IQ-N-3", "jsonschema_fixtures"]
  },
  "oq": {
    "status": "PASS",
    "command": "cargo test -p gaia-health-substrate",
    "note": "Synthetic matrix per OQ_PROTOCOL.md — full CAB human PQ blocked per PQ_PROTOCOL.md"
  },
  "pq": {
    "status": "PASS_SYNTHETIC",
    "pq_n_mesh_001": "nutrition::tests::pq_n_mesh_identical_evidence_identical_projection",
    "human_pq_v2": "BLOCKED until CAB ACTIVE per CAB_CONSTITUTION.md"
  }
}
EOF

ok "Receipt written: ${RECEIPT}"

log "OWL-NUTRITION IQ / OQ / PQ validation COMPLETE"
printf "  Summary: IQ PASS, OQ PASS (unit tests), PQ PASS (synthetic determinism only)\n"
