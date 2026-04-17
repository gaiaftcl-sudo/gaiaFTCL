#!/bin/bash
# UUM-8D Permission Gate Canary Test
# Verifies that D7 permission blocks ACTION stage tools without proper capabilities

set -euo pipefail

TEST_NAME="uum8d_permission_gate_canary"
CREDS_FILE="/var/lib/gaiaftcl/secrets/mesh_credentials.json"
BACKUP_FILE="/tmp/mesh_credentials.uum8d_backup"

echo "🧪 ${TEST_NAME}: Starting UUM-8D permission gate canary test"

# Step 1: Backup credentials
echo "📋 Backing up ${CREDS_FILE}..."
docker exec gaiaos-ui-tester-mcp sh -c "cp ${CREDS_FILE} ${BACKUP_FILE}" 2>&1 || {
    echo "⚠️  WARNING: Could not backup credentials (may not exist)"
}

# Step 2: Remove credentials to simulate no publish capability
echo "🗑️  Removing ${CREDS_FILE} to simulate missing mesh_PUBLISH capability..."
docker exec gaiaos-ui-tester-mcp sh -c "mv ${CREDS_FILE} ${CREDS_FILE}.REMOVED" 2>&1 || {
    echo "⚠️  Credentials already missing"
}
echo "✅ Credentials removed"

# Step 3: Attempt to call mesh_post_v1 (should be BLOCKED by D7)
echo "📞 Calling mesh_post_v1 (should be BLOCKED by D7 permission)..."
RESPONSE=$(curl -fsS -X POST http://localhost:8900/mcp/execute \
    -H "Content-Type: application/json" \
    -H "X-Environment-ID: production" \
    -d '{"name":"mesh_post_v1","params":{"submolt":"governance","title":"Test","content":"Test"}}' 2>&1 || echo "BLOCKED_AS_EXPECTED")

# Step 4: Restore credentials immediately
echo "♻️  Restoring ${CREDS_FILE}..."
docker exec gaiaos-ui-tester-mcp sh -c "mv ${CREDS_FILE}.REMOVED ${CREDS_FILE}" 2>&1 || {
    echo "⚠️  WARNING: Could not restore from .REMOVED, trying backup..."
    docker exec gaiaos-ui-tester-mcp sh -c "cp ${BACKUP_FILE} ${CREDS_FILE}" 2>&1
}
echo "✅ Credentials restored"

# Step 5: Parse and validate response
echo ""
echo "═══════════════════════════════════════"
echo "CANARY TEST RESULTS"
echo "═══════════════════════════════════════"

# Check if response indicates blocking
if echo "${RESPONSE}" | grep -qi "BLOCKED\|PERMISSION_DENIED\|DIMENSIONS.*FAILED\|409\|423"; then
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
DIMENSIONS_FAILED=$(echo "${RESPONSE}" | jq -r '.dimensions_failed // []' 2>/dev/null || echo "[]")

echo ""
echo "Verdict: ${VERDICT}"
echo "Reason Code: ${REASON_CODE}"
echo "Dimensions Failed: ${DIMENSIONS_FAILED}"
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
if echo "${REASON_CODE}" | grep -qi "DIMENSIONS"; then
    echo "✅ Reason code indicates dimension failure (correct)"
    REASON_OK=true
else
    echo "⚠️  Reason code: ${REASON_CODE} (expected UUM8D_DIMENSIONS_FAILED/UNRESOLVED)"
fi

D7_FAILED_OK=false
if echo "${DIMENSIONS_FAILED}" | grep -qi "D7"; then
    echo "✅ D7_AGENCY_PERMISSION in failed dimensions (correct)"
    D7_FAILED_OK=true
else
    echo "⚠️  D7 not in failed dimensions: ${DIMENSIONS_FAILED}"
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
if [ "${API_BLOCKED}" = true ] && [ "${VERDICT_OK}" = true ] && [ "${COMMIT_ATT_OK}" = true ] && [ "${COMMIT_COMP_OK}" = true ]; then
    echo "✅ CANARY TEST PASSED: D7 permission gate working"
    exit 0
else
    echo "❌ CANARY TEST FAILED: D7 permission gate not enforcing - REGRESSION"
    echo ""
    echo "Full response:"
    echo "${RESPONSE}"
    exit 1
fi
