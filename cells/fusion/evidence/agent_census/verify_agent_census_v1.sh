#!/usr/bin/env bash
set -euo pipefail

# verify_agent_census_v1.sh - Regression test for Agent Census MCP tools
# Usage: ./verify_agent_census_v1.sh (from any directory)
# Requires: MCP server running on localhost:8850

# Find repo root (works from any subdirectory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

ENV_ID="4c30d276-ec0b-48c2-9d74-b1dcd6ce67b6"
BASE_URL="http://localhost:8850"

echo "=== AGENT CENSUS VERIFICATION ==="
echo "Repo root: $REPO_ROOT"
echo ""

# Helper function for byte-match verification
verify_byte_match() {
  local response_file=$1
  local label=$2
  
  CALL_ID=$(jq -r '.witness.call_id' "$response_file")
  EXPECT_HASH=$(jq -r '.witness.hash' "$response_file" | sed 's/sha256://')
  
  curl -sS "${BASE_URL}/evidence/${CALL_ID}" -o /tmp/evidence.json
  GOT_HASH=$(shasum -a 256 /tmp/evidence.json | awk '{print $1}')
  
  if [ "$GOT_HASH" != "$EXPECT_HASH" ]; then
    echo "❌ FAIL: Byte-match failed for $label"
    echo "   Expected: $EXPECT_HASH"
    echo "   Got:      $GOT_HASH"
    exit 1
  fi
  echo "✅ Byte-match OK for $label (call_id: $CALL_ID)"
}

# 1. Register sample agent
echo "1. Registering sample agent..."
curl -sS -X POST "${BASE_URL}/mcp/execute" \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: ${ENV_ID}" \
  -d '{
    "name": "agent_register_v1",
    "params": {
      "declaration": {
        "agent_name": "test_agent_001",
        "runtime_type": "local",
        "declared_capabilities": {
          "WEB_FETCH": true,
          "CODE_RUN": true,
          "FILE_WRITE": false,
          "HTTP_API_CALL": true,
          "EMAIL_SEND": false,
          "SMS_SEND": false,
          "SSH_CONNECT": false,
          "TASK_SCHEDULE": false,
          "WALLET_SIGN": false,
          "TRADE_EXECUTE": false,
          "AGENT_COORDINATE": false
        },
        "agrees_to_witness_gate": true,
        "operator_contact": "test@gaiaftcl.com"
      }
    }
  }' > /tmp/register.json

if ! jq -e '.ok == true' /tmp/register.json > /dev/null; then
  echo "❌ FAIL: agent_register_v1 returned ok=false"
  jq . /tmp/register.json
  exit 1
fi

AGENT_ID=$(jq -r '.result.agent_id' /tmp/register.json)
echo "✅ Agent registered: $AGENT_ID"
verify_byte_match /tmp/register.json "agent_register_v1"

# 2. Issue challenges
echo ""
echo "2. Issuing challenges for agent..."
curl -sS -X POST "${BASE_URL}/mcp/execute" \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: ${ENV_ID}" \
  -d "{
    \"name\": \"agent_issue_challenges_v1\",
    \"params\": {
      \"agent_id\": \"${AGENT_ID}\"
    }
  }" > /tmp/challenges.json

if ! jq -e '.ok == true' /tmp/challenges.json > /dev/null; then
  echo "❌ FAIL: agent_issue_challenges_v1 returned ok=false"
  jq . /tmp/challenges.json
  exit 1
fi

CHALLENGE_COUNT=$(jq -r '.result.count' /tmp/challenges.json)
echo "✅ Challenges issued: $CHALLENGE_COUNT"
verify_byte_match /tmp/challenges.json "agent_issue_challenges_v1"

# Extract CODE_RUN challenge
CODE_RUN_CHALLENGE_ID=$(jq -r '.result.challenge_instances[] | select(.capability_id == "CODE_RUN") | .challenge_id' /tmp/challenges.json)
CODE_RUN_NONCE=$(jq -r '.result.challenge_instances[] | select(.capability_id == "CODE_RUN") | .nonce' /tmp/challenges.json)

if [ -z "$CODE_RUN_CHALLENGE_ID" ]; then
  echo "❌ FAIL: No CODE_RUN challenge found"
  exit 1
fi
echo "✅ CODE_RUN challenge: $CODE_RUN_CHALLENGE_ID (nonce: ${CODE_RUN_NONCE:0:16}...)"

# 3. Submit CODE_RUN proof
echo ""
echo "3. Submitting CODE_RUN proof..."

# Compute expected hash for the proof (nonce + newline, matching server expectation)
EXPECTED_HASH=$(echo "${CODE_RUN_NONCE}" | shasum -a 256 | awk '{print $1}')

curl -sS -X POST "${BASE_URL}/mcp/execute" \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: ${ENV_ID}" \
  -d "{
    \"name\": \"agent_submit_proof_v1\",
    \"params\": {
      \"agent_id\": \"${AGENT_ID}\",
      \"challenge_id\": \"${CODE_RUN_CHALLENGE_ID}\",
      \"proof_payload\": {
        \"stdout\": \"${CODE_RUN_NONCE}\",
        \"stdout_hash\": \"${EXPECTED_HASH}\"
      }
    }
  }" > /tmp/proof.json

if ! jq -e '.ok == true' /tmp/proof.json > /dev/null; then
  echo "❌ FAIL: agent_submit_proof_v1 returned ok=false"
  jq . /tmp/proof.json
  exit 1
fi

VERDICT=$(jq -r '.result.verdict' /tmp/proof.json)
if [ "$VERDICT" != "PROVEN" ]; then
  echo "❌ FAIL: Expected verdict=PROVEN, got $VERDICT"
  jq . /tmp/proof.json
  exit 1
fi
echo "✅ Proof submitted and verified: PROVEN"
verify_byte_match /tmp/proof.json "agent_submit_proof_v1"

# 4. Label agent
echo ""
echo "4. Labeling agent..."
curl -sS -X POST "${BASE_URL}/mcp/execute" \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: ${ENV_ID}" \
  -d "{
    \"name\": \"agent_label_v1\",
    \"params\": {
      \"agent_id\": \"${AGENT_ID}\"
    }
  }" > /tmp/label.json

if ! jq -e '.ok == true' /tmp/label.json > /dev/null; then
  echo "❌ FAIL: agent_label_v1 returned ok=false"
  jq . /tmp/label.json
  exit 1
fi

TIER=$(jq -r '.result.tier' /tmp/label.json)
echo "✅ Agent labeled: $TIER"
verify_byte_match /tmp/label.json "agent_label_v1"

# 5. Export topology
echo ""
echo "5. Exporting topology..."
curl -sS -X POST "${BASE_URL}/mcp/execute" \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: ${ENV_ID}" \
  -d '{
    "name": "agent_topology_export_v1",
    "params": {}
  }' > /tmp/topology.json

if ! jq -e '.ok == true' /tmp/topology.json > /dev/null; then
  echo "❌ FAIL: agent_topology_export_v1 returned ok=false"
  jq . /tmp/topology.json
  exit 1
fi

AGENT_COUNT=$(jq -r '.result.agents | length' /tmp/topology.json)
echo "✅ Topology exported: $AGENT_COUNT agents"
verify_byte_match /tmp/topology.json "agent_topology_export_v1"

# 6. Generate census report
echo ""
echo "6. Generating census report..."
curl -sS -X POST "${BASE_URL}/mcp/execute" \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: ${ENV_ID}" \
  -d '{
    "name": "agent_census_report_v1",
    "params": {}
  }' > /tmp/census.json

if ! jq -e '.ok == true' /tmp/census.json > /dev/null; then
  echo "❌ FAIL: agent_census_report_v1 returned ok=false"
  jq . /tmp/census.json
  exit 1
fi

TOTAL_AGENTS=$(jq -r '.result.counts.total_agents' /tmp/census.json)
echo "✅ Census report generated: $TOTAL_AGENTS total agents"
verify_byte_match /tmp/census.json "agent_census_report_v1"

# Summary
echo ""
echo "=== VERIFICATION COMPLETE ==="
echo ""
echo "Summary:"
echo "  Agent ID: $AGENT_ID"
echo "  Challenges issued: $CHALLENGE_COUNT"
echo "  Proofs verified: 1 (CODE_RUN)"
echo "  Agent tier: $TIER"
echo "  Total agents in system: $TOTAL_AGENTS"
echo ""
echo "✅ All Agent Census tools verified with byte-match."
