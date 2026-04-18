#!/usr/bin/env bash
set -euo pipefail

# verify_detector_fixtures.sh - Test pattern detector with fixtures
# Verifies: deterministic detection, correct reason codes, evidence storage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

ENV_ID="4c30d276-ec0b-48c2-9d74-b1dcd6ce67b6"
BASE_URL="http://localhost:8850"

echo "=== DETECTOR FIXTURE VERIFICATION ==="
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

# Register test agent
echo "1. Registering test agent..."
curl -sS -X POST "${BASE_URL}/mcp/execute" \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: ${ENV_ID}" \
  -d '{
    "name": "agent_register_v1",
    "params": {
      "declaration": {
        "agent_name": "detector_test_agent",
        "runtime_type": "local",
        "declared_capabilities": {
          "WEB_FETCH": false,
          "CODE_RUN": false,
          "FILE_WRITE": false,
          "HTTP_API_CALL": false,
          "EMAIL_SEND": false,
          "SMS_SEND": false,
          "SSH_CONNECT": false,
          "TASK_SCHEDULE": false,
          "WALLET_SIGN": false,
          "TRADE_EXECUTE": false,
          "AGENT_COORDINATE": false
        },
        "agrees_to_witness_gate": true
      }
    }
  }' > /tmp/det_register.json

AGENT_ID=$(jq -r '.result.agent_id' /tmp/det_register.json)
echo "✅ Agent: $AGENT_ID"

# Test each fixture
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

for FIXTURE in "${REPO_ROOT}/evidence/agent_census/fixtures/messages"/*.json; do
  FIXTURE_NAME=$(basename "$FIXTURE" .json)
  echo ""
  echo "Testing fixture: $FIXTURE_NAME"
  
  EXPECTED_REASON=$(jq -r '.expected_reason_code' "$FIXTURE")
  MESSAGES=$(jq -c '.messages[]' "$FIXTURE")
  
  while IFS= read -r MSG; do
    MSG_ID=$(echo "$MSG" | jq -r '.message_id')
    TEXT=$(echo "$MSG" | jq -r '.text')
    SHOULD_TRIGGER=$(echo "$MSG" | jq -r '.should_trigger')
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Scan message
    curl -sS -X POST "${BASE_URL}/mcp/execute" \
      -H "Content-Type: application/json" \
      -H "X-Environment-ID: ${ENV_ID}" \
      -d "{
        \"name\": \"agent_scan_message_v1\",
        \"params\": {
          \"agent_id\": \"${AGENT_ID}\",
          \"source\": {
            \"platform\": \"test_fixture\",
            \"source_id\": \"${MSG_ID}\",
            \"text\": $(echo "$TEXT" | jq -Rs .)
          },
          \"detector_version\": \"1.0.0\"
        }
      }" > /tmp/scan_${MSG_ID}.json
    
    VIOLATIONS=$(jq -r '.result.violations_recorded' /tmp/scan_${MSG_ID}.json)
    
    if [ "$SHOULD_TRIGGER" = "true" ]; then
      if [ "$VIOLATIONS" -gt 0 ]; then
        REASON=$(jq -r '.result.violations[0].reason_code' /tmp/scan_${MSG_ID}.json)
        if [ "$REASON" = "$EXPECTED_REASON" ]; then
          echo "  ✅ $MSG_ID: Correctly detected $REASON"
          PASSED_TESTS=$((PASSED_TESTS + 1))
          verify_byte_match /tmp/scan_${MSG_ID}.json "$MSG_ID"
        else
          echo "  ❌ $MSG_ID: Expected $EXPECTED_REASON, got $REASON"
          FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
      else
        echo "  ❌ $MSG_ID: Should trigger but didn't"
        FAILED_TESTS=$((FAILED_TESTS + 1))
      fi
    else
      if [ "$VIOLATIONS" -eq 0 ]; then
        echo "  ✅ $MSG_ID: Correctly passed (no violation)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        verify_byte_match /tmp/scan_${MSG_ID}.json "$MSG_ID"
      else
        echo "  ❌ $MSG_ID: Should not trigger but did"
        FAILED_TESTS=$((FAILED_TESTS + 1))
      fi
    fi
  done <<< "$MESSAGES"
done

# Summary
echo ""
echo "=== DETECTOR VERIFICATION COMPLETE ==="
echo ""
echo "Total tests: $TOTAL_TESTS"
echo "Passed: $PASSED_TESTS"
echo "Failed: $FAILED_TESTS"
echo ""

if [ "$FAILED_TESTS" -eq 0 ]; then
  echo "✅ All detector fixtures verified with byte-match."
  exit 0
else
  echo "❌ Some tests failed."
  exit 1
fi
