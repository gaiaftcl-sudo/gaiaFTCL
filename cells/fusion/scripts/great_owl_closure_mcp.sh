#!/usr/bin/env bash
# Project Great Owl — closure via GaiaFTCL MCP (gaiaos_ui_tester_mcp)
# Produces a witnessed receipt with residual_entropy "0.0" (zero-entropy closure token in this substrate).
#
# Prereq: gaiaos_ui_tester_mcp listening (default http://localhost:8850)
# Usage:
#   export CLOSURE_MCP_URL=http://localhost:8850
#   export CLOSURE_ENV_ID=<your X-Environment-ID>
#   ./scripts/great_owl_closure_mcp.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BASE_URL="${CLOSURE_MCP_URL:-http://localhost:8850}"
ENV_ID="${CLOSURE_ENV_ID:-4c30d276-ec0b-48c2-9d74-b1dcd6ce67b6}"
DOMAIN_ID="meningococcal_hardware"
AGENT_ID="${GREAT_OWL_AGENT_ID:-Medic_Branch_Great_Owl}"
NONCE="great_owl_$(date +%s)_$(openssl rand -hex 4)"

echo "=== Project Great Owl — MCP closure (GaiaFTCL) ==="
echo "Repo: $REPO_ROOT"
echo "MCP:  $BASE_URL"
echo "Domain: $DOMAIN_ID"
echo ""

# 0) Health
if ! curl -sfS "${BASE_URL}/health" >/dev/null 2>&1; then
  echo "❌ MCP not reachable at ${BASE_URL}/health"
  echo "   Start gaiaos_ui_tester_mcp (port 8850) from cells/fusion/services/gaiaos_ui_tester_mcp"
  exit 1
fi
echo "✅ MCP health OK"

# 1) Echo sink (witness)
echo ""
echo "1) Recording nonce on echo sink..."
curl -sS -X POST "${BASE_URL}/echo/nonce" \
  -H "Content-Type: application/json" \
  -d "{\"nonce\": \"${NONCE}\", \"agent_id\": \"${AGENT_ID}\"}" > /tmp/great_owl_echo.json
if ! jq -e '.recorded == true' /tmp/great_owl_echo.json >/dev/null; then
  echo "❌ Echo failed"; jq . /tmp/great_owl_echo.json; exit 1
fi
echo "✅ Nonce recorded: $NONCE"

# 2) Evaluate claim (LAB_PROTOCOL class)
echo ""
echo "2) closure_evaluate_claim_v1..."
CLAIM_TEXT="Project Great Owl: meningococcal hardware-invariant substrate package (protocol + discovery batch + INV_MEN_*). Evidence nonce ${NONCE}."
curl -sS -X POST "${BASE_URL}/mcp/execute" \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: ${ENV_ID}" \
  -d "$(jq -n \
    --arg d "$DOMAIN_ID" \
    --arg c "$CLAIM_TEXT" \
    '{name: "closure_evaluate_claim_v1", params: {domain_id: $d, claim_text: $c, claim_class: "LAB_PROTOCOL"}}')" \
  > /tmp/great_owl_eval.json
if ! jq -e '.success == true' /tmp/great_owl_eval.json >/dev/null; then
  echo "❌ Evaluate failed"; jq . /tmp/great_owl_eval.json; exit 1
fi
if ! jq -e '.verdict == "OFFERED"' /tmp/great_owl_eval.json >/dev/null; then
  echo "❌ Closure not offered (check claim_class vs domain contract)"; jq . /tmp/great_owl_eval.json; exit 1
fi
echo "✅ Claim evaluated (OFFERED)"

# 3) Verify evidence
echo ""
echo "3) closure_verify_evidence_v1 (HTTP_ECHO_SINK)..."
curl -sS -X POST "${BASE_URL}/mcp/execute" \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: ${ENV_ID}" \
  -d "$(jq -n \
    --arg d "$DOMAIN_ID" \
    --arg n "$NONCE" \
    --arg a "$AGENT_ID" \
    '{name: "closure_verify_evidence_v1", params: {domain_id: $d, evidence_type: "HTTP_ECHO_SINK", nonce: $n, agent_id: $a}}')" \
  > /tmp/great_owl_verify.json
if ! jq -e '.verified == true' /tmp/great_owl_verify.json >/dev/null; then
  echo "❌ Verify failed"; jq . /tmp/great_owl_verify.json; exit 1
fi
EVIDENCE_HASH="$(jq -r '.evidence_hash' /tmp/great_owl_verify.json)"
echo "✅ Evidence verified: $EVIDENCE_HASH"

# 4) Receipt — residual_entropy "0.0" = substrate zero-entropy closure witness
echo ""
echo "4) closure_generate_receipt_v1 (residual_entropy 0.0)..."
curl -sS -X POST "${BASE_URL}/mcp/execute" \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: ${ENV_ID}" \
  -d "$(jq -n \
    --arg d "$DOMAIN_ID" \
    --arg h "$EVIDENCE_HASH" \
    '{name: "closure_generate_receipt_v1", params: {domain_id: $d, closure_class: "PROVISIONAL", evidence_hash: $h, residual_entropy: "0.0"}}')" \
  > /tmp/great_owl_receipt.json
if ! jq -e '.success == true' /tmp/great_owl_receipt.json >/dev/null; then
  echo "❌ Receipt failed"; jq . /tmp/great_owl_receipt.json; exit 1
fi
echo "✅ Closure receipt generated"
CALL_ID="$(jq -r '.receipt.call_id' /tmp/great_owl_receipt.json)"
echo ""
echo "call_id: $CALL_ID"
echo "Receipt file: evidence/closure_game/receipts/*-${CALL_ID}.json (under gaiaos_ui_tester_mcp cwd)"
echo ""
echo "Full response:"
jq . /tmp/great_owl_receipt.json
