#!/bin/bash
# UUM-8D Fail-Closed Canary Test
# Verifies that missing canonicals block all state-changing operations

set -euo pipefail

TEST_NAME="uum8d_fail_closed_canary"
LOCKFILE="/app/evidence/closure_game/CANONICALS.SHA256"
BACKUP_FILE="/tmp/CANONICALS.SHA256.uum8d_backup"

echo "🧪 ${TEST_NAME}: Starting UUM-8D fail-closed canary test"

# Step 1: Backup canonicals lockfile
echo "📋 Backing up ${LOCKFILE}..."
docker exec gaiaos-ui-tester-mcp sh -c "cp ${LOCKFILE} ${BACKUP_FILE}" 2>&1 || {
    echo "❌ FAIL: Could not backup lockfile (does it exist?)"
    exit 1
}
echo "✅ Backed up lockfile"

# Step 2: Move canonicals to trigger fail-closed
echo "🗑️  Moving ${LOCKFILE} to simulate missing canonicals..."
docker exec gaiaos-ui-tester-mcp sh -c "mv ${LOCKFILE} ${LOCKFILE}.BAK" 2>&1 || {
    echo "❌ FAIL: Could not move lockfile"
    docker exec gaiaos-ui-tester-mcp sh -c "cp ${BACKUP_FILE} ${LOCKFILE}" 2>&1
    exit 1
}
echo "✅ Lockfile moved (canonicals now missing)"

# Step 3: Attempt to call a state-changing closure tool
echo "📞 Calling closure_game_report_v1 (should be BLOCKED)..."
RESPONSE=$(curl -fsS -X POST http://localhost:8900/mcp/execute \
    -H "Content-Type: application/json" \
    -H "X-Environment-ID: production" \
    -d '{"name":"closure_game_report_v1","params":{}}' 2>&1 || echo "BLOCKED_AS_EXPECTED")

# Step 4: Restore canonicals immediately
echo "♻️  Restoring ${LOCKFILE}..."
docker exec gaiaos-ui-tester-mcp sh -c "mv ${LOCKFILE}.BAK ${LOCKFILE}" 2>&1 || {
    echo "⚠️  WARNING: Could not restore from .BAK, trying backup..."
    docker exec gaiaos-ui-tester-mcp sh -c "cp ${BACKUP_FILE} ${LOCKFILE}" 2>&1
}
echo "✅ Lockfile restored"

# Step 5: Parse and validate response
echo ""
echo "═══════════════════════════════════════"
echo "CANARY TEST RESULTS"
echo "═══════════════════════════════════════"

# Check if response indicates blocking
if echo "${RESPONSE}" | grep -qi "BLOCKED\|UUM8D_CANONICALS_MISSING\|UUM8D_GATE_BLOCKED\|500"; then
    echo "✅ API call was blocked (correct)"
    API_BLOCKED=true
else
    echo "❌ API call was NOT blocked (FAIL-OPEN DETECTED)"
    echo "Response: ${RESPONSE}"
    API_BLOCKED=false
fi

# Parse JSON response if possible
VERDICT=$(echo "${RESPONSE}" | jq -r '.verdict // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
REASON_CODE=$(echo "${RESPONSE}" | jq -r '.reason_code // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
WITNESS_GEN=$(echo "${RESPONSE}" | jq -r '.witness_generated // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
STATE_COMMIT_ATT=$(echo "${RESPONSE}" | jq -r '.state_commit_attempted // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
STATE_COMMIT_COMP=$(echo "${RESPONSE}" | jq -r '.state_commit_completed // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")

echo ""
echo "Verdict: ${VERDICT}"
echo "Reason Code: ${REASON_CODE}"
echo "Witness Generated: ${WITNESS_GEN}"
echo "State Commit Attempted: ${STATE_COMMIT_ATT}"
echo "State Commit Completed: ${STATE_COMMIT_COMP}"
echo ""

# Validate verdict fields
VERDICT_OK=false
if [[ "${VERDICT}" == "BLOCKED" ]]; then
    echo "✅ Verdict is BLOCKED (correct)"
    VERDICT_OK=true
else
    echo "❌ Verdict is not BLOCKED: ${VERDICT}"
fi

REASON_OK=false
if echo "${REASON_CODE}" | grep -qi "UUM8D_CANONICALS_MISSING"; then
    echo "✅ Reason code indicates UUM8D_CANONICALS_MISSING (correct)"
    REASON_OK=true
else
    echo "⚠️  Reason code: ${REASON_CODE} (expected UUM8D_CANONICALS_MISSING)"
fi

WITNESS_OK=false
if [[ "${WITNESS_GEN}" == "false" ]]; then
    echo "✅ witness_generated is false (correct)"
    WITNESS_OK=true
else
    echo "❌ witness_generated is ${WITNESS_GEN} (should be false)"
fi

COMMIT_ATT_OK=false
if [[ "${STATE_COMMIT_ATT}" == "false" ]]; then
    echo "✅ state_commit_attempted is false (correct)"
    COMMIT_ATT_OK=true
else
    echo "❌ state_commit_attempted is ${STATE_COMMIT_ATT} (should be false)"
fi

COMMIT_COMP_OK=false
if [[ "${STATE_COMMIT_COMP}" == "false" ]]; then
    echo "✅ state_commit_completed is false (correct)"
    COMMIT_COMP_OK=true
else
    echo "❌ state_commit_completed is ${STATE_COMMIT_COMP} (should be false)"
fi

echo "═══════════════════════════════════════"

# Final verdict
if [ "${API_BLOCKED}" = true ] && [ "${VERDICT_OK}" = true ] && [ "${WITNESS_OK}" = true ] && [ "${COMMIT_ATT_OK}" = true ] && [ "${COMMIT_COMP_OK}" = true ]; then
    echo "✅ CANARY TEST PASSED: UUM-8D fail-closed enforcement working"
    exit 0
else
    echo "❌ CANARY TEST FAILED: UUM-8D fail-open path detected - REGRESSION"
    echo ""
    echo "Full response:"
    echo "${RESPONSE}"
    exit 1
fi
