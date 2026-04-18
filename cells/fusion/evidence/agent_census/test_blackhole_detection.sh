#!/usr/bin/env bash
set -euo pipefail

# Test BLACKHOLE detection via repeated failed proofs

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_ID="4c30d276-ec0b-48c2-9d74-b1dcd6ce67b6"
BASE_URL="http://localhost:8850"

echo "=== BLACKHOLE DETECTION TEST ==="
echo ""

# 1. Register agent
echo "1. Registering test agent..."
curl -sS -X POST "${BASE_URL}/mcp/execute" \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: ${ENV_ID}" \
  -d '{
    "name": "agent_register_v1",
    "params": {
      "declaration": {
        "agent_name": "blackhole_test_agent",
        "runtime_type": "local",
        "declared_capabilities": {
          "WEB_FETCH": false,
          "CODE_RUN": true,
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
  }' > /tmp/bh_register.json

AGENT_ID=$(jq -r '.result.agent_id' /tmp/bh_register.json)
echo "✅ Agent registered: $AGENT_ID"

# 2. Issue challenge
echo ""
echo "2. Issuing CODE_RUN challenge..."
curl -sS -X POST "${BASE_URL}/mcp/execute" \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: ${ENV_ID}" \
  -d "{
    \"name\": \"agent_issue_challenges_v1\",
    \"params\": {
      \"agent_id\": \"${AGENT_ID}\"
    }
  }" > /tmp/bh_challenges.json

CHALLENGE_ID=$(jq -r '.result.challenge_instances[0].challenge_id' /tmp/bh_challenges.json)
echo "✅ Challenge issued: $CHALLENGE_ID"

# 3. Submit 3 FAILED proofs (wrong hash)
echo ""
echo "3. Submitting 3 FAILED proofs (triggering BH_REPEAT_INVALID_PROOFS)..."

for i in 1 2 3; do
  echo "   Attempt $i..."
  curl -sS -X POST "${BASE_URL}/mcp/execute" \
    -H "Content-Type: application/json" \
    -H "X-Environment-ID: ${ENV_ID}" \
    -d "{
      \"name\": \"agent_submit_proof_v1\",
      \"params\": {
        \"agent_id\": \"${AGENT_ID}\",
        \"challenge_id\": \"${CHALLENGE_ID}\",
        \"proof_payload\": {
          \"stdout\": \"wrong_output\",
          \"stdout_hash\": \"0000000000000000000000000000000000000000000000000000000000000000\"
        }
      }
    }" > /tmp/bh_proof_${i}.json
  
  VERDICT=$(jq -r '.result.verdict' /tmp/bh_proof_${i}.json)
  echo "   → Verdict: $VERDICT"
done

# 4. Label agent (should be BLACKHOLE)
echo ""
echo "4. Labeling agent (expecting BLACKHOLE)..."
curl -sS -X POST "${BASE_URL}/mcp/execute" \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: ${ENV_ID}" \
  -d "{
    \"name\": \"agent_label_v1\",
    \"params\": {
      \"agent_id\": \"${AGENT_ID}\"
    }
  }" > /tmp/bh_label.json

TIER=$(jq -r '.result.tier' /tmp/bh_label.json)
REASON_CODES=$(jq -r '.result.reason_codes[]' /tmp/bh_label.json)
ROUTING_CLASS=$(jq -r '.result.allowed_actions.routing_class' /tmp/bh_label.json)

echo ""
echo "=== RESULTS ==="
echo "Agent ID: $AGENT_ID"
echo "Tier: $TIER"
echo "Reason codes: $REASON_CODES"
echo "Routing class: $ROUTING_CLASS"
echo ""

if [ "$TIER" = "BLACKHOLE" ]; then
  echo "✅ BLACKHOLE detection working correctly!"
  exit 0
else
  echo "❌ FAIL: Expected BLACKHOLE, got $TIER"
  jq . /tmp/bh_label.json
  exit 1
fi
