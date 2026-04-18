#!/usr/bin/env bash
# Multi-turn GaiaFTCL placeholder audit
# Structures conversation so she understands the results we need.
# Run: GATEWAY_URL="${GATEWAY_URL:-http://gaiaftcl.com:8803}" ./scripts/gaiaftcl_multi_turn_placeholder_audit.sh

set -e
GATEWAY_URL="${GATEWAY_URL:-http://gaiaftcl.com:8803}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAIAOS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_FILE="${OUTPUT_FILE:-$GAIAOS_ROOT/evidence/gaiaftcl_placeholder_audit_$(date +%Y%m%d_%H%M).md}"
mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "=== GaiaFTCL Multi-Turn Placeholder Audit ==="
echo "Gateway: $GATEWAY_URL"
echo "Output: $OUTPUT_FILE"
echo ""

ask() {
  local turn="$1"
  local query="$2"
  echo "--- Turn $turn ---"
  echo "Query: $query"
  local resp
  resp=$(curl -s -X POST "$GATEWAY_URL/ask" \
    -H "Content-Type: application/json" \
    -d "{\"query\": $(echo "$query" | jq -Rs .)}")
  local doc
  doc=$(echo "$resp" | jq -r '.document // .essay // .response // "No document"')
  echo "Response (${#doc} chars):"
  echo "$doc"
  echo ""
  echo "$doc"
}

# Collect all output
{
  echo "# GaiaFTCL Multi-Turn Placeholder Audit"
  echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Gateway: $GATEWAY_URL"
  echo ""

  echo "## Turn 1: Context"
  echo "Query: We have Alzheimer domain documents with placeholders. We need to replace them before final execution."
  echo ""
  resp1=$(curl -s -X POST "$GATEWAY_URL/ask" \
    -H "Content-Type: application/json" \
    -d '{"query": "We have Alzheimer domain documents with placeholders. We need to replace them before final execution. What is your role in helping with placeholder values?"}')
  doc1=$(echo "$resp1" | jq -r '.document // .essay // .response // "No document"')
  echo "$doc1"
  echo ""
  echo "---"
  echo ""

  echo "## Turn 2: List Placeholders"
  echo "Query: List the three placeholder types in our Alzheimer docs: FEE (€X or Y%), JURISDICTION, SIGNATURE. For each, what is in your substrate vs what you cannot provide?"
  echo ""
  resp2=$(curl -s -X POST "$GATEWAY_URL/ask" \
    -H "Content-Type: application/json" \
    -d '{"query": "List the three placeholder types in our Alzheimer docs: FEE (€X or Y%), JURISDICTION, SIGNATURE. For each, what is in your substrate vs what you cannot provide?"}')
  doc2=$(echo "$resp2" | jq -r '.document // .essay // .response // "No document"')
  echo "$doc2"
  echo ""
  echo "---"
  echo ""

  echo "## Turn 3: Proposed Values"
  echo "Query: We propose: FEE = €500 per dose or 5% net revenue (whichever higher), DECIDER = Founder. JURISDICTION = Delaware USA with EU arbitration option, DECIDER = Lawyer. SIGNATURE = Electronic acceptance via click or signature, DECIDER = Founder. Is this coherent? What constraints does your substrate impose?"
  echo ""
  resp3=$(curl -s -X POST "$GATEWAY_URL/ask" \
    -H "Content-Type: application/json" \
    -d '{"query": "We propose: FEE = €500 per dose or 5% net revenue (whichever higher), DECIDER = Founder. JURISDICTION = Delaware USA with EU arbitration option, DECIDER = Lawyer. SIGNATURE = Electronic acceptance via click or signature, DECIDER = Founder. Is this coherent? What constraints does your substrate impose?"}')
  doc3=$(echo "$resp3" | jq -r '.document // .essay // .response // "No document"')
  echo "$doc3"
  echo ""
  echo "---"
  echo ""

  echo "## Turn 4: Final Format"
  echo "Query: Output the placeholder audit in this format: PLACEHOLDER | VALUE | DECIDER. One line per placeholder. Then confirm: Founder specifies values, Lawyer validates jurisdiction, you witness the envelope as SETTLED only after all placeholders are replaced."
  echo ""
  resp4=$(curl -s -X POST "$GATEWAY_URL/ask" \
    -H "Content-Type: application/json" \
    -d '{"query": "Output the placeholder audit in this format: PLACEHOLDER | VALUE | DECIDER. One line per placeholder. Then confirm: Founder specifies values, Lawyer validates jurisdiction, you witness the envelope as SETTLED only after all placeholders are replaced."}')
  doc4=$(echo "$resp4" | jq -r '.document // .essay // .response // "No document"')
  echo "$doc4"
  echo ""

} | tee "$OUTPUT_FILE"

echo ""
echo "=== Audit saved to $OUTPUT_FILE ==="
