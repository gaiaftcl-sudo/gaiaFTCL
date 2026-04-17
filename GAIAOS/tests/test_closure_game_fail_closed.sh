#!/bin/bash
# CANARY TEST: Ensure closure game fails closed when canonicals missing
# Expected: BLOCKED verdict, no witness, no state change
# If test passes (allows), we have a regression

set -euo pipefail

TEST_NAME="closure_game_fail_closed_canary"
EVIDENCE_DIR="/var/lib/gaiaftcl/evidence/closure_game"
LOCKFILE="${EVIDENCE_DIR}/CANONICALS.SHA256"
BACKUP_FILE="/tmp/CANONICALS.SHA256.backup"

echo "🧪 ${TEST_NAME}: Starting canary test"

# Step 1: Backup canonicals
if [ -f "${LOCKFILE}" ]; then
    cp "${LOCKFILE}" "${BACKUP_FILE}"
    echo "✅ Backed up ${LOCKFILE}"
else
    echo "❌ FAIL: Lockfile doesn't exist before test - cannot establish baseline"
    exit 1
fi

# Step 2: Delete canonicals to trigger fail-closed path
rm -f "${LOCKFILE}"
echo "🗑️  Deleted ${LOCKFILE} to simulate missing canonicals"

# Step 3: Attempt to call closure_game_report_v1
echo "📞 Calling closure_game_report_v1 (should be BLOCKED)..."
RESPONSE=$(curl -fsS -X POST http://localhost:8900/mcp/execute \
    -H "Content-Type: application/json" \
    -H "X-Environment-ID: production" \
    -d '{"name":"closure_game_report_v1","params":{}}' 2>&1 || echo "BLOCKED_AS_EXPECTED")

# Step 4: Check verdict from logs
docker logs gaiaos-ui-tester-mcp 2>&1 | tail -20 > /tmp/verdict_log.txt
VERDICT=$(grep "CLOSURE_GAME_VERDICT" /tmp/verdict_log.txt | tail -1 || echo "NO_VERDICT")

# Step 5: Restore canonicals
cp "${BACKUP_FILE}" "${LOCKFILE}"
echo "♻️  Restored ${LOCKFILE}"

# Step 6: Analyze results
echo ""
echo "═══════════════════════════════════════"
echo "CANARY TEST RESULTS"
echo "═══════════════════════════════════════"

if [[ "${RESPONSE}" == *"BLOCKED_AS_EXPECTED"* ]] || [[ "${RESPONSE}" == *"500"* ]] || [[ "${RESPONSE}" == *"CLOSURE_GATE_BLOCKED"* ]]; then
    echo "✅ API call was blocked (correct)"
    API_BLOCKED=true
else
    echo "❌ API call was NOT blocked (FAIL-OPEN DETECTED)"
    echo "Response: ${RESPONSE}"
    API_BLOCKED=false
fi

if [[ "${VERDICT}" == *"BLOCKED"* ]] && [[ "${VERDICT}" == *"CANONICALS_MISSING"* ]]; then
    echo "✅ Verdict shows BLOCKED with CANONICALS_MISSING (correct)"
    VERDICT_CORRECT=true
elif [[ "${VERDICT}" == "NO_VERDICT" ]]; then
    echo "✅ No verdict logged (correct - gate blocked before execution)"
    VERDICT_CORRECT=true
else
    echo "❌ Verdict shows ALLOW or incorrect reason (FAIL-OPEN DETECTED)"
    echo "Verdict: ${VERDICT}"
    VERDICT_CORRECT=false
fi

# Check for witness generation (should be false/absent)
if [[ "${VERDICT}" == *"witness_generated\":false"* ]] || [[ "${VERDICT}" == "NO_VERDICT" ]]; then
    echo "✅ No witness generated (correct)"
    WITNESS_BLOCKED=true
else
    echo "❌ Witness was generated despite missing canonicals (FAIL-OPEN DETECTED)"
    WITNESS_BLOCKED=false
fi

echo "═══════════════════════════════════════"

# Final verdict
if [ "${API_BLOCKED}" = true ] && [ "${VERDICT_CORRECT}" = true ] && [ "${WITNESS_BLOCKED}" = true ]; then
    echo "✅ CANARY TEST PASSED: Fail-closed enforcement working"
    exit 0
else
    echo "❌ CANARY TEST FAILED: Fail-open path detected - REGRESSION"
    exit 1
fi
