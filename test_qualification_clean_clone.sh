#!/usr/bin/env zsh
# ═══════════════════════════════════════════════════════════════
# Test Mac Qualification — Clean Clone
# Creates test folder, clones repo, runs full IQ/OQ/PQ
# Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

GRN='\033[0;32m'; RED='\033[0;31m'; BLU='\033[0;34m'; YLW='\033[1;33m'; NC='\033[0m'

banner() {
    echo -e "\n${BLU}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLU}  $1${NC}"
    echo -e "${BLU}═══════════════════════════════════════════════════════════${NC}"
}

ok() { echo -e "${GRN}  ✅ $1${NC}"; }
fail() { echo -e "${RED}  ❌ BLOCKED: $1${NC}" >&2; exit 1; }

banner "Mac Qualification — Clean Clone Test"

# ═══════════════════════════════════════════════════════════════
# 1. Create clean test directory
# ═══════════════════════════════════════════════════════════════

TEST_DIR="${HOME}/FoT8D_qualification_test_$(date +%Y%m%d_%H%M%S)"
banner "Step 1/7: Create test directory"
mkdir -p "${TEST_DIR}" || fail "Failed to create test directory"
cd "${TEST_DIR}"
ok "Test directory: ${TEST_DIR}"

# ═══════════════════════════════════════════════════════════════
# 2. Clone repository
# ═══════════════════════════════════════════════════════════════

banner "Step 2/7: Clone repository"
REPO_PATH="$(cd ~/Documents/FoT8D && pwd)"
echo -e "  Cloning from: ${REPO_PATH}"
git clone "${REPO_PATH}" FoT8D || fail "Git clone failed"
cd FoT8D
git checkout feat/mac-qualification-swift-only || fail "Branch checkout failed"
ok "Repository cloned"

# ═══════════════════════════════════════════════════════════════
# 3. Build MacFusion app
# ═══════════════════════════════════════════════════════════════

banner "Step 3/7: Build MacFusion"
cd GAIAOS/macos/GaiaFusion
swift build --product GaiaFusion 2>&1 | tail -3
[[ -f .build/debug/GaiaFusion ]] || fail "MacFusion executable missing"
ok "MacFusion built"
cd "${TEST_DIR}/FoT8D"

# ═══════════════════════════════════════════════════════════════
# 4. Build MacHealth app
# ═══════════════════════════════════════════════════════════════

banner "Step 4/7: Build MacHealth"
cd GAIAOS/macos/MacHealth
swift build --product MacHealth 2>&1 | tail -3
[[ -f .build/debug/MacHealth ]] || fail "MacHealth executable missing"
ok "MacHealth built"
cd "${TEST_DIR}/FoT8D"

# ═══════════════════════════════════════════════════════════════
# 5. Build qualification executables
# ═══════════════════════════════════════════════════════════════

banner "Step 5/7: Build qualification executables"

echo "  Building MacFusionQualification..."
cd GAIAOS/macos/MacFusionQualification
swift build 2>&1 | tail -3
[[ -f .build/debug/MacFusionQualification ]] || fail "MacFusionQualification missing"
ok "MacFusionQualification built"

echo "  Building MacHealthQualification..."
cd ../MacHealthQualification
swift build 2>&1 | tail -3
[[ -f .build/debug/MacHealthQualification ]] || fail "MacHealthQualification missing"
ok "MacHealthQualification built"

echo "  Building TestRobot..."
cd ../TestRobot
swift build 2>&1 | tail -3
[[ -f .build/debug/TestRobot ]] || fail "TestRobot missing"
ok "TestRobot built"

echo "  Building QualificationRunner..."
cd ../QualificationRunner
swift build 2>&1 | tail -3
[[ -f .build/debug/QualificationRunner ]] || fail "QualificationRunner missing"
ok "QualificationRunner built"

cd "${TEST_DIR}/FoT8D"

# ═══════════════════════════════════════════════════════════════
# 6. Run full qualification
# ═══════════════════════════════════════════════════════════════

banner "Step 6/7: Run qualification (IQ/OQ/PQ + TestRobot)"
GAIAOS/macos/QualificationRunner/.build/debug/QualificationRunner || fail "Qualification failed"
ok "All qualification complete"

# ═══════════════════════════════════════════════════════════════
# 7. Verify receipts
# ═══════════════════════════════════════════════════════════════

banner "Step 7/7: Verify receipts"

RECEIPTS=(
    "GAIAOS/macos/GaiaFusion/evidence/iq/macfusion_iq_receipt.json"
    "GAIAOS/macos/GaiaFusion/evidence/oq/macfusion_oq_receipt.json"
    "GAIAOS/macos/GaiaFusion/evidence/pq/macfusion_pq_receipt.json"
    "GAIAOS/macos/MacHealth/evidence/iq/machealth_iq_receipt.json"
    "GAIAOS/macos/MacHealth/evidence/oq/machealth_oq_receipt.json"
    "GAIAOS/macos/MacHealth/evidence/pq/machealth_pq_receipt.json"
    "evidence/TESTROBOT_RECEIPT.json"
)

for RECEIPT in "${RECEIPTS[@]}"; do
    if [[ ! -f "${RECEIPT}" ]]; then
        fail "Receipt missing: ${RECEIPT}"
    fi
    python3 -c "import json; json.load(open('${RECEIPT}'))" 2>/dev/null || fail "Invalid JSON: ${RECEIPT}"
    ok "$(basename ${RECEIPT})"
done

# ═══════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════

banner "STATE: CALORIE — Clean Clone Test PASS"

echo -e ""
echo -e "${GRN}  ✅ MacFusion: IQ/OQ/PQ verified${NC}"
echo -e "${GRN}  ✅ MacHealth: IQ/OQ/PQ verified${NC}"
echo -e "${GRN}  ✅ TestRobot: Live test verified${NC}"
echo -e "${GRN}  ✅ All receipts: Present and valid (7/7)${NC}"
echo -e ""
echo -e "  Test directory: ${TEST_DIR}"
echo -e "  Receipts:"
for RECEIPT in "${RECEIPTS[@]}"; do
    echo -e "    ${TEST_DIR}/FoT8D/${RECEIPT}"
done
echo -e ""
echo -e "${YLW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YLW}  To clean up: rm -rf ${TEST_DIR}${NC}"
echo -e "${YLW}═══════════════════════════════════════════════════════════${NC}"
echo -e ""
