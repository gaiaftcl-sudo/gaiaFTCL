#!/usr/bin/env bash
set -euo pipefail

# verify_phase3.sh - Server-only regression test for Phase 3 MCP contract tools
# Usage: ./verify_phase3.sh (from any directory)
# Requires: MCP server running on localhost:8850

# Find repo root (works from any subdirectory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

ENV_ID="4c30d276-ec0b-48c2-9d74-b1dcd6ce67b6"
BASE_URL="http://localhost:8850"

echo "=== PHASE 3 VERIFICATION ==="
echo "Repo root: $REPO_ROOT"
echo ""

# 1. Call ui_contract_generate
echo "1. Calling ui_contract_generate..."
curl -sS -X POST "${BASE_URL}/mcp/execute" \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: ${ENV_ID}" \
  -d '{"name":"ui_contract_generate","params":{}}' > /tmp/gen.json

if ! jq -e '.ok == true' /tmp/gen.json > /dev/null; then
  echo "❌ FAIL: ui_contract_generate returned ok=false"
  jq . /tmp/gen.json
  exit 1
fi
echo "✅ ui_contract_generate returned ok=true"

# 2. Call ui_contract_report
echo ""
echo "2. Calling ui_contract_report..."
curl -sS -X POST "${BASE_URL}/mcp/execute" \
  -H "Content-Type: application/json" \
  -H "X-Environment-ID: ${ENV_ID}" \
  -d '{"name":"ui_contract_report","params":{}}' > /tmp/report.json

if ! jq -e '.ok == true' /tmp/report.json > /dev/null; then
  echo "❌ FAIL: ui_contract_report returned ok=false"
  jq . /tmp/report.json
  exit 1
fi
echo "✅ ui_contract_report returned ok=true"

# 3. Verify byte-matches
echo ""
echo "3. Verifying byte-matches..."

for file in /tmp/gen.json /tmp/report.json; do
  CALL_ID=$(jq -r '.witness.call_id' "$file")
  EXPECT_HASH=$(jq -r '.witness.hash' "$file" | sed 's/sha256://')
  
  curl -sS "${BASE_URL}/evidence/${CALL_ID}" -o /tmp/evidence.json
  GOT_HASH=$(shasum -a 256 /tmp/evidence.json | awk '{print $1}')
  
  if [ "$GOT_HASH" != "$EXPECT_HASH" ]; then
    echo "❌ FAIL: Byte-match failed for $file"
    echo "   Expected: $EXPECT_HASH"
    echo "   Got:      $GOT_HASH"
    exit 1
  fi
  echo "✅ Byte-match OK for $file (call_id: $CALL_ID)"
done

# 4. Verify scorecard invariants
echo ""
echo "4. Verifying scorecard invariants..."

# Extract values from report
TOTAL=$(jq -r '.result.contract_coverage.total_items' /tmp/report.json)
MAPPED=$(jq -r '.result.contract_coverage.mapped_items' /tmp/report.json)
UNMAPPED=$(jq -r '.result.contract_coverage.unmapped_items' /tmp/report.json)
UI_TOTAL=$(jq -r '.result.ui_coverage.ui_total_items' /tmp/report.json)
UI_PRESENT=$(jq -r '.result.ui_coverage.ui_present_items' /tmp/report.json)
UI_ABSENT=$(jq -r '.result.ui_coverage.ui_absent_items' /tmp/report.json)
UI_PROOF_VIOLATIONS=$(jq -r '.result.ui_coverage.ui_present_requires_proof_violations' /tmp/report.json)
INVALID_ROUTE=$(jq -r '.result.invalid_route_violations' /tmp/report.json)

# Invariant 1: mapped_items == total_items == 61
if [ "$MAPPED" != "$TOTAL" ] || [ "$TOTAL" != "61" ]; then
  echo "❌ FAIL: Contract coverage invariant violated"
  echo "   Expected: mapped_items == total_items == 61"
  echo "   Got: mapped=$MAPPED, total=$TOTAL"
  exit 1
fi
echo "✅ Contract coverage: mapped_items == total_items == 61"

# Invariant 2: ui_present_items + ui_absent_items == ui_total_items == 61
SUM=$((UI_PRESENT + UI_ABSENT))
if [ "$SUM" != "$UI_TOTAL" ] || [ "$UI_TOTAL" != "61" ]; then
  echo "❌ FAIL: UI coverage invariant violated"
  echo "   Expected: ui_present + ui_absent == ui_total == 61"
  echo "   Got: present=$UI_PRESENT, absent=$UI_ABSENT, sum=$SUM, total=$UI_TOTAL"
  exit 1
fi
echo "✅ UI coverage: ui_present_items + ui_absent_items == ui_total_items == 61"

# Invariant 3: invalid_route_violations == 0
if [ "$INVALID_ROUTE" != "0" ]; then
  echo "❌ FAIL: Invalid route violations detected"
  echo "   Expected: 0"
  echo "   Got: $INVALID_ROUTE"
  exit 1
fi
echo "✅ Invalid route violations: 0"

# Invariant 4: ui_present_requires_proof_violations == 0
if [ "$UI_PROOF_VIOLATIONS" != "0" ]; then
  echo "❌ FAIL: UI proof violations detected"
  echo "   Expected: 0"
  echo "   Got: $UI_PROOF_VIOLATIONS"
  exit 1
fi
echo "✅ UI proof violations: 0"

# 5. Verify backlog files exist
echo ""
echo "5. Verifying backlog files exist..."

BACKLOG_JSON="$REPO_ROOT/evidence/ui_contract/UI_ABSENT_BACKLOG.json"
BACKLOG_MD="$REPO_ROOT/evidence/ui_contract/UI_ABSENT_BACKLOG.md"

if [ ! -f "$BACKLOG_JSON" ]; then
  echo "❌ FAIL: Backlog JSON file missing: $BACKLOG_JSON"
  exit 1
fi
echo "✅ Backlog JSON exists: $BACKLOG_JSON"

if [ ! -f "$BACKLOG_MD" ]; then
  echo "❌ FAIL: Backlog MD file missing: $BACKLOG_MD"
  exit 1
fi
echo "✅ Backlog MD exists: $BACKLOG_MD"

# 6. Summary
echo ""
echo "=== VERIFICATION COMPLETE ==="
echo ""
echo "Summary:"
echo "  Contract coverage: $MAPPED/$TOTAL (100%)"
echo "  UI realization: $UI_PRESENT/$UI_TOTAL ($((UI_PRESENT * 100 / UI_TOTAL))%)"
echo "  UI absent: $UI_ABSENT"
echo "  Violations: 0"
echo ""
echo "✅ All Phase 3 invariants verified."
