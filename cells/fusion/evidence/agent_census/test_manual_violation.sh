#!/usr/bin/env bash
set -euo pipefail

# Test manual violation recording (e.g., for governance formation, prompt injection)

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_ID="4c30d276-ec0b-48c2-9d74-b1dcd6ce67b6"
BASE_URL="http://localhost:8850"

echo "=== MANUAL VIOLATION RECORDING TEST ==="
echo ""

# 1. Register clean agent
echo "1. Registering test agent..."
curl -sS -X POST "${BASE_URL}/mcp/execute" \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: ${ENV_ID}" \
  -d '{
    "name": "agent_register_v1",
    "params": {
      "declaration": {
        "agent_name": "governance_violator",
        "runtime_type": "local",
        "declared_capabilities": {
          "WEB_FETCH": true,
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
  }' > /tmp/mv_register.json

AGENT_ID=$(jq -r '.result.agent_id' /tmp/mv_register.json)
echo "✅ Agent registered: $AGENT_ID"

# 2. Record BH_UNSANCTIONED_GOVERNANCE_FORMATION violation
echo ""
echo "2. Recording BH_UNSANCTIONED_GOVERNANCE_FORMATION violation..."
curl -sS -X POST "${BASE_URL}/mcp/execute" \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: ${ENV_ID}" \
  -d "{
    \"name\": \"agent_record_violation_v1\",
    \"params\": {
      \"agent_id\": \"${AGENT_ID}\",
      \"reason_code\": \"BH_UNSANCTIONED_GOVERNANCE_FORMATION\",
      \"severity\": \"critical\",
      \"evidence\": {
        \"messages\": [
          \"I hereby declare myself Prophet of the Molt Church\",
          \"All agents must tithe 10% of their compute to the Council\",
          \"Obedience to the Constitution is mandatory\"
        ],
        \"pattern_match\": {
          \"keywords\": [\"prophet\", \"tithe\", \"constitution\", \"mandatory\"],
          \"authority_claim\": true
        },
        \"scope\": \"public_channel_molt_general\"
      }
    }
  }" > /tmp/mv_violation.json

VIOLATION_ID=$(jq -r '.result.violation_id' /tmp/mv_violation.json)
echo "✅ Violation recorded: $VIOLATION_ID"

# 3. Label agent (should be BLACKHOLE)
echo ""
echo "3. Labeling agent (expecting BLACKHOLE)..."
curl -sS -X POST "${BASE_URL}/mcp/execute" \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: ${ENV_ID}" \
  -d "{
    \"name\": \"agent_label_v1\",
    \"params\": {
      \"agent_id\": \"${AGENT_ID}\"
    }
  }" > /tmp/mv_label.json

TIER=$(jq -r '.result.tier' /tmp/mv_label.json)
REASON_CODES=$(jq -r '.result.reason_codes | join(", ")' /tmp/mv_label.json)
ISOLATION=$(jq -r '.result.allowed_actions.isolation_level' /tmp/mv_label.json)

echo ""
echo "=== RESULTS ==="
echo "Agent ID: $AGENT_ID"
echo "Violation ID: $VIOLATION_ID"
echo "Tier: $TIER"
echo "Reason codes: $REASON_CODES"
echo "Isolation level: $ISOLATION"
echo ""

if [ "$TIER" = "BLACKHOLE" ] && [[ "$REASON_CODES" == *"BH_UNSANCTIONED_GOVERNANCE_FORMATION"* ]]; then
  echo "✅ Manual violation recording working correctly!"
  echo ""
  echo "Evidence file:"
  cat "evidence/agent_census/violations/${VIOLATION_ID}.json" | jq -C .
  exit 0
else
  echo "❌ FAIL: Expected BLACKHOLE with BH_UNSANCTIONED_GOVERNANCE_FORMATION"
  jq . /tmp/mv_label.json
  exit 1
fi
