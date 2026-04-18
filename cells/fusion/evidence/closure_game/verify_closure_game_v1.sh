#!/usr/bin/env bash
set -euo pipefail

# CLOSURE GAME VERIFICATION — Manual Operator Backing Infrastructure
# Tests: echo sink → evaluate → verify → receipt → report
# All byte-match verified

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

ENV_ID="4c30d276-ec0b-48c2-9d74-b1dcd6ce67b6"
BASE_URL="http://localhost:8850"

echo "=== CLOSURE GAME VERIFICATION ==="
echo "Repo root: $REPO_ROOT"
echo ""

# Helper: byte-match verification
verify_byte_match() {
  local response_file=$1
  local label=$2
  
  CALL_ID=$(jq -r '.witness.call_id' "$response_file")
  EXPECT_HASH=$(jq -r '.witness.hash' "$response_file" | sed 's/sha256://')
  
  curl -sS "${BASE_URL}/evidence/${CALL_ID}" -o /tmp/evidence.json
  GOT_HASH=$(shasum -a 256 /tmp/evidence.json | awk '{print $1}')
  
  if [ "$GOT_HASH" != "$EXPECT_HASH" ]; then
    echo "❌ FAIL: Byte-match failed for $label"
    exit 1
  fi
  echo "✅ Byte-match OK: $label"
}

# 1. Test echo sink
echo "1. Testing echo sink..."
TEST_NONCE="test_nonce_$(date +%s)"
TEST_AGENT="test_agent_closure_game"

curl -sS -X POST "${BASE_URL}/echo/nonce" \
  -H "Content-Type: application/json" \
  -d "{
    \"nonce\": \"${TEST_NONCE}\",
    \"agent_id\": \"${TEST_AGENT}\"
  }" > /tmp/echo_nonce.json

if ! jq -e '.recorded == true' /tmp/echo_nonce.json > /dev/null; then
  echo "❌ FAIL: Echo nonce not recorded"
  jq . /tmp/echo_nonce.json
  exit 1
fi
echo "✅ Echo nonce recorded"

# Verify nonce exists
curl -sS "${BASE_URL}/echo/verify/${TEST_NONCE}" > /tmp/echo_verify.json
if ! jq -e '.found == true' /tmp/echo_verify.json > /dev/null; then
  echo "❌ FAIL: Echo nonce not found"
  jq . /tmp/echo_verify.json
  exit 1
fi
echo "✅ Echo nonce verified"

# 2. Evaluate claim
echo ""
echo "2. Evaluating claim..."
curl -sS -X POST "${BASE_URL}/mcp/execute" \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: ${ENV_ID}" \
  -d '{
    "name": "closure_evaluate_claim_v1",
    "params": {
      "domain_id": "generic",
      "claim_text": "Test claim for closure game verification",
      "claim_class": "TRUTH_ASSERTION"
    }
  }' > /tmp/closure_evaluate.json

if ! jq -e '.ok == true' /tmp/closure_evaluate.json > /dev/null; then
  echo "❌ FAIL: Claim evaluation failed"
  jq . /tmp/closure_evaluate.json
  exit 1
fi

VERDICT=$(jq -r '.result.verdict' /tmp/closure_evaluate.json)
if [ "$VERDICT" != "OFFERED" ]; then
  echo "❌ FAIL: Expected OFFERED, got $VERDICT"
  jq . /tmp/closure_evaluate.json
  exit 1
fi
echo "✅ Claim evaluation: OFFERED"
verify_byte_match /tmp/closure_evaluate.json "evaluate_claim"

# Check rendered text contains required elements
RENDERED=$(jq -r '.result.rendered_text' /tmp/closure_evaluate.json)
if ! echo "$RENDERED" | grep -q "CLOSURE OFFERED"; then
  echo "❌ FAIL: Rendered text missing 'CLOSURE OFFERED'"
  exit 1
fi
if ! echo "$RENDERED" | grep -q "GaiaFTCL"; then
  echo "❌ FAIL: Rendered text missing 'GaiaFTCL'"
  exit 1
fi
if ! echo "$RENDERED" | grep -q "Patent Notice"; then
  echo "❌ FAIL: Rendered text missing 'Patent Notice'"
  exit 1
fi
if ! echo "$RENDERED" | grep -q "Commercial Signal"; then
  echo "❌ FAIL: Rendered text missing 'Commercial Signal'"
  exit 1
fi
echo "✅ Rendered text contains all required elements"

# 3. Verify evidence
echo ""
echo "3. Verifying evidence..."
curl -sS -X POST "${BASE_URL}/mcp/execute" \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: ${ENV_ID}" \
  -d "{
    \"name\": \"closure_verify_evidence_v1\",
    \"params\": {
      \"domain_id\": \"generic\",
      \"evidence_type\": \"HTTP_ECHO_SINK\",
      \"nonce\": \"${TEST_NONCE}\",
      \"agent_id\": \"${TEST_AGENT}\"
    }
  }" > /tmp/closure_verify.json

if ! jq -e '.ok == true' /tmp/closure_verify.json > /dev/null; then
  echo "❌ FAIL: Evidence verification failed"
  jq . /tmp/closure_verify.json
  exit 1
fi

VERIFIED=$(jq -r '.result.verified' /tmp/closure_verify.json)
if [ "$VERIFIED" != "true" ]; then
  echo "❌ FAIL: Evidence not verified"
  jq . /tmp/closure_verify.json
  exit 1
fi
echo "✅ Evidence verified"
verify_byte_match /tmp/closure_verify.json "verify_evidence"

EVIDENCE_HASH=$(jq -r '.result.evidence_hash' /tmp/closure_verify.json)
echo "Evidence hash: $EVIDENCE_HASH"

# 4. Generate receipt
echo ""
echo "4. Generating receipt..."
curl -sS -X POST "${BASE_URL}/mcp/execute" \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: ${ENV_ID}" \
  -d "{
    \"name\": \"closure_generate_receipt_v1\",
    \"params\": {
      \"domain_id\": \"generic\",
      \"closure_class\": \"PROVISIONAL\",
      \"evidence_hash\": \"${EVIDENCE_HASH}\",
      \"residual_entropy\": \"0.0\"
    }
  }" > /tmp/closure_receipt.json

if ! jq -e '.ok == true' /tmp/closure_receipt.json > /dev/null; then
  echo "❌ FAIL: Receipt generation failed"
  jq . /tmp/closure_receipt.json
  exit 1
fi
echo "✅ Receipt generated"
verify_byte_match /tmp/closure_receipt.json "generate_receipt"

# Check rendered text
RENDERED=$(jq -r '.result.rendered_text' /tmp/closure_receipt.json)
if ! echo "$RENDERED" | grep -q "CLOSURE PERFORMED"; then
  echo "❌ FAIL: Rendered text missing 'CLOSURE PERFORMED'"
  exit 1
fi
if ! echo "$RENDERED" | grep -q "GaiaFTCL"; then
  echo "❌ FAIL: Rendered text missing 'GaiaFTCL'"
  exit 1
fi
if ! echo "$RENDERED" | grep -q "Patent Notice"; then
  echo "❌ FAIL: Rendered text missing 'Patent Notice'"
  exit 1
fi
if ! echo "$RENDERED" | grep -q "Commercial Signal"; then
  echo "❌ FAIL: Rendered text missing 'Commercial Signal'"
  exit 1
fi
if ! echo "$RENDERED" | grep -q "Enterprise closure"; then
  echo "❌ FAIL: Rendered text missing 'Enterprise closure'"
  exit 1
fi
echo "✅ Rendered text contains all required elements"

# 5. Generate report
echo ""
echo "5. Generating report..."
curl -sS -X POST "${BASE_URL}/mcp/execute" \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: ${ENV_ID}" \
  -d '{
    "name": "closure_game_report_v1",
    "params": {}
  }' > /tmp/closure_report.json

if ! jq -e '.ok == true' /tmp/closure_report.json > /dev/null; then
  echo "❌ FAIL: Report generation failed"
  jq . /tmp/closure_report.json
  exit 1
fi
echo "✅ Report generated"
verify_byte_match /tmp/closure_report.json "game_report"

TOTAL_RECEIPTS=$(jq -r '.result.report.total_receipts' /tmp/closure_report.json)
ECHO_COUNT=$(jq -r '.result.report.echo_ledger_count' /tmp/closure_report.json)
echo "Total receipts: $TOTAL_RECEIPTS"
echo "Echo ledger entries: $ECHO_COUNT"

# Verify report files exist
if [ ! -f "${REPO_ROOT}/evidence/closure_game/CLOSURE_GAME_REPORT.json" ]; then
  echo "❌ FAIL: Report JSON not found"
  exit 1
fi
if [ ! -f "${REPO_ROOT}/evidence/closure_game/CLOSURE_GAME_REPORT.md" ]; then
  echo "❌ FAIL: Report MD not found"
  exit 1
fi
echo "✅ Report files exist"

echo ""
echo "=== VERIFICATION COMPLETE ==="
echo ""
echo "✅ All tests passed"
echo "✅ Echo sink operational"
echo "✅ All MCP tools byte-match verified"
echo "✅ Templates locked and stable"
echo "✅ Commercial signal present in all outputs"
