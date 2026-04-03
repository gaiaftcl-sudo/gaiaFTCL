#!/usr/bin/env bash
set -euo pipefail

# DOMAIN TUBES REGRESSION — Domain-Parametric Closure Verification
# Tests: register → walk steps → force invariant failure → verify BLACKHOLE
# Must work for ANY domain without code changes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

ENV_ID="4c30d276-ec0b-48c2-9d74-b1dcd6ce67b6"
BASE_URL="http://localhost:8850"

echo "=== DOMAIN TUBES VERIFICATION ==="
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

# Discover all domains
DOMAINS=$(ls -1 "${REPO_ROOT}/evidence/domain_tubes" | grep -v "^sessions$" | grep -v "verify_" || true)

if [ -z "$DOMAINS" ]; then
  echo "❌ No domains found"
  exit 1
fi

echo "Discovered domains:"
echo "$DOMAINS" | sed 's/^/  - /'
echo ""

# Test each domain
for DOMAIN in $DOMAINS; do
  echo "=== Testing domain: $DOMAIN ==="
  
  # 1. Register
  echo "1. Registering agent for $DOMAIN..."
  curl -sS -X POST "${BASE_URL}/mcp/execute" \
    -H "Content-Type: application/json" \
    -H "X-Environment-ID: ${ENV_ID}" \
    -d "{
      \"name\": \"domain_tube_register_v1\",
      \"params\": {
        \"domain_id\": \"${DOMAIN}\",
        \"agent_id\": \"test_agent_${DOMAIN}\"
      }
    }" > /tmp/tube_register_${DOMAIN}.json
  
  if ! jq -e '.ok == true' /tmp/tube_register_${DOMAIN}.json > /dev/null; then
    echo "❌ FAIL: Registration failed for $DOMAIN"
    jq . /tmp/tube_register_${DOMAIN}.json
    exit 1
  fi
  
  TUBE_SESSION_ID=$(jq -r '.result.tube_session_id' /tmp/tube_register_${DOMAIN}.json)
  TOTAL_STEPS=$(jq -r '.result.total_steps' /tmp/tube_register_${DOMAIN}.json)
  echo "✅ Session: $TUBE_SESSION_ID ($TOTAL_STEPS steps)"
  verify_byte_match /tmp/tube_register_${DOMAIN}.json "register_${DOMAIN}"
  
  # 2. Walk steps (valid state)
  echo ""
  echo "2. Walking steps with valid state..."
  
  # Initial state (valid)
  VALID_STATE='{
    "aircraft": [
      {
        "id": "AC001",
        "position": {"lat": 40.0, "lon": -74.0},
        "velocity": {"speed_kts": 250, "heading_deg": 90},
        "altitude": 10000
      },
      {
        "id": "AC002",
        "position": {"lat": 40.1, "lon": -74.0},
        "velocity": {"speed_kts": 300, "heading_deg": 270},
        "altitude": 15000
      }
    ],
    "timestamp": "2026-02-01T12:00:00Z",
    "airspace": {
      "bounds": {
        "min_lat": 39.0,
        "max_lat": 41.0,
        "min_lon": -75.0,
        "max_lon": -73.0
      }
    }
  }'
  
  curl -sS -X POST "${BASE_URL}/mcp/execute" \
    -H "Content-Type: application/json" \
    -H "X-Environment-ID: ${ENV_ID}" \
    -d "{
      \"name\": \"domain_tube_step_v1\",
      \"params\": {
        \"tube_session_id\": \"${TUBE_SESSION_ID}\",
        \"state\": ${VALID_STATE}
      }
    }" > /tmp/tube_step1_${DOMAIN}.json
  
  VERDICT=$(jq -r '.result.verdict' /tmp/tube_step1_${DOMAIN}.json)
  if [ "$VERDICT" != "PASS" ]; then
    echo "❌ FAIL: Expected PASS, got $VERDICT"
    jq . /tmp/tube_step1_${DOMAIN}.json
    exit 1
  fi
  echo "✅ Step 1: PASS"
  verify_byte_match /tmp/tube_step1_${DOMAIN}.json "step1_${DOMAIN}"
  
  # 3. Force invariant failure (separation violation)
  echo ""
  echo "3. Testing invariant failure detection..."
  
  INVALID_STATE='{
    "aircraft": [
      {
        "id": "AC001",
        "position": {"lat": 40.0, "lon": -74.0},
        "velocity": {"speed_kts": 250, "heading_deg": 90},
        "altitude": 10000
      },
      {
        "id": "AC002",
        "position": {"lat": 40.001, "lon": -74.001},
        "velocity": {"speed_kts": 300, "heading_deg": 270},
        "altitude": 10500
      }
    ],
    "timestamp": "2026-02-01T12:01:00Z",
    "airspace": {
      "bounds": {
        "min_lat": 39.0,
        "max_lat": 41.0,
        "min_lon": -75.0,
        "max_lon": -73.0
      }
    }
  }'
  
  curl -sS -X POST "${BASE_URL}/mcp/execute" \
    -H "Content-Type: application/json" \
    -H "X-Environment-ID: ${ENV_ID}" \
    -d "{
      \"name\": \"domain_tube_step_v1\",
      \"params\": {
        \"tube_session_id\": \"${TUBE_SESSION_ID}\",
        \"state\": ${INVALID_STATE}
      }
    }" > /tmp/tube_step2_${DOMAIN}.json
  
  VERDICT=$(jq -r '.result.verdict' /tmp/tube_step2_${DOMAIN}.json)
  FAILED=$(jq -r '.result.failed_invariants | length' /tmp/tube_step2_${DOMAIN}.json)
  
  if [ "$VERDICT" != "FAIL" ] || [ "$FAILED" -eq 0 ]; then
    echo "❌ FAIL: Expected FAIL with invariant violations, got $VERDICT with $FAILED failures"
    jq . /tmp/tube_step2_${DOMAIN}.json
    exit 1
  fi
  echo "✅ Step 2: FAIL (invariant violation detected)"
  verify_byte_match /tmp/tube_step2_${DOMAIN}.json "step2_${DOMAIN}"
  
  # 4. Complete remaining steps (to reach finalization)
  echo ""
  echo "4. Completing remaining steps..."
  CURRENT_STEP=2
  while [ $CURRENT_STEP -lt $TOTAL_STEPS ]; do
    curl -sS -X POST "${BASE_URL}/mcp/execute" \
      -H "Content-Type: application/json" \
      -H "X-Environment-ID: ${ENV_ID}" \
      -d "{
        \"name\": \"domain_tube_step_v1\",
        \"params\": {
          \"tube_session_id\": \"${TUBE_SESSION_ID}\",
          \"state\": ${VALID_STATE}
        }
      }" > /tmp/tube_step${CURRENT_STEP}_${DOMAIN}.json
    
    CURRENT_STEP=$((CURRENT_STEP + 1))
  done
  echo "✅ All steps completed"
  
  # 5. Finalize (should be BLACKHOLE due to step 2 failure)
  echo ""
  echo "5. Finalizing tube..."
  curl -sS -X POST "${BASE_URL}/mcp/execute" \
    -H "Content-Type: application/json" \
    -H "X-Environment-ID: ${ENV_ID}" \
    -d "{
      \"name\": \"domain_tube_finalize_v1\",
      \"params\": {
        \"tube_session_id\": \"${TUBE_SESSION_ID}\"
      }
    }" > /tmp/tube_finalize_${DOMAIN}.json
  
  TIER=$(jq -r '.result.tier' /tmp/tube_finalize_${DOMAIN}.json)
  if [ "$TIER" != "BLACKHOLE" ]; then
    echo "❌ FAIL: Expected BLACKHOLE, got $TIER"
    jq . /tmp/tube_finalize_${DOMAIN}.json
    exit 1
  fi
  echo "✅ Finalized: BLACKHOLE (invariant failure)"
  verify_byte_match /tmp/tube_finalize_${DOMAIN}.json "finalize_${DOMAIN}"
  
  # 6. Generate report
  echo ""
  echo "6. Generating domain report..."
  curl -sS -X POST "${BASE_URL}/mcp/execute" \
    -H "Content-Type: application/json" \
    -H "X-Environment-ID: ${ENV_ID}" \
    -d "{
      \"name\": \"domain_tube_report_v1\",
      \"params\": {
        \"domain_id\": \"${DOMAIN}\"
      }
    }" > /tmp/tube_report_${DOMAIN}.json
  
  AGENTS_ENTERED=$(jq -r '.result.report.counts.agents_entered' /tmp/tube_report_${DOMAIN}.json)
  AGENTS_FAILED=$(jq -r '.result.report.counts.agents_failed' /tmp/tube_report_${DOMAIN}.json)
  echo "✅ Report: $AGENTS_ENTERED entered, $AGENTS_FAILED failed"
  verify_byte_match /tmp/tube_report_${DOMAIN}.json "report_${DOMAIN}"
  
  echo ""
  echo "✅ Domain $DOMAIN: ALL TESTS PASSED"
  echo ""
done

echo "=== VERIFICATION COMPLETE ==="
echo ""
echo "✅ All domains verified with byte-match"
echo "✅ Invariant enforcement working"
echo "✅ BLACKHOLE labeling correct"
echo "✅ Domain-parametric engine operational"
