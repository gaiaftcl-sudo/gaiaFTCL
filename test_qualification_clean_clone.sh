#!/usr/bin/env zsh
# ═══════════════════════════════════════════════════════════════
# Test Mac Qualification — Clean Clone (Using Canonical Bash Scripts)
# Creates test folder, clones repo, runs IQ/OQ/PQ via scripts/gamp5_*.sh
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
banner "Step 1/6: Create test directory"
mkdir -p "${TEST_DIR}" || fail "Failed to create test directory"
cd "${TEST_DIR}"
ok "Test directory: ${TEST_DIR}"

# ═══════════════════════════════════════════════════════════════
# 2. Clone repository
# ═══════════════════════════════════════════════════════════════

banner "Step 2/6: Clone repository"
REPO_PATH="$(cd ~/Documents/FoT8D && pwd)"
echo -e "  Cloning from: ${REPO_PATH}"
git clone "${REPO_PATH}" FoT8D || fail "Git clone failed"
cd FoT8D
git checkout feat/mac-qualification-swift-only || fail "Branch checkout failed"
ok "Repository cloned"

# ═══════════════════════════════════════════════════════════════
# 3. Build TestRobot (Swift - PQ only)
# ═══════════════════════════════════════════════════════════════

banner "Step 3/6: Build TestRobot"
cd GAIAOS/macos/TestRobot
swift build 2>&1 | tail -3
[[ -f .build/debug/TestRobot ]] || fail "TestRobot executable missing"
ok "TestRobot built"
cd "${TEST_DIR}/FoT8D"

# ═══════════════════════════════════════════════════════════════
# 4. Run IQ (Installation Qualification) — bash
# ═══════════════════════════════════════════════════════════════

banner "Step 4/6: IQ (Installation Qualification)"
echo "  Running: scripts/gamp5_iq.sh --cell both"
zsh scripts/gamp5_iq.sh --cell both || fail "IQ failed"
ok "IQ: PASS (both cells)"

# ═══════════════════════════════════════════════════════════════
# 5. Run OQ (Operational Qualification) — bash
# ═══════════════════════════════════════════════════════════════

banner "Step 5/6: OQ (Operational Qualification)"
echo "  Running: scripts/gamp5_oq.sh --cell both"
zsh scripts/gamp5_oq.sh --cell both || fail "OQ failed"
ok "OQ: PASS (both cells)"

# ═══════════════════════════════════════════════════════════════
# 6. Run PQ (Performance Qualification) — bash + TestRobot
# ═══════════════════════════════════════════════════════════════

banner "Step 6/6: PQ (Performance Qualification)"
echo "  Running: scripts/gamp5_pq.sh --cell both"
zsh scripts/gamp5_pq.sh --cell both || fail "PQ failed"
ok "PQ: PASS (both cells + TestRobot)"

# ═══════════════════════════════════════════════════════════════
# Verify receipts
# ═══════════════════════════════════════════════════════════════

banner "Verifying All Receipts"

RECEIPTS=(
    "GAIAOS/macos/GaiaFusion/evidence/iq/iq_receipt.json"
    "GAIAOS/macos/GaiaFusion/evidence/oq/oq_receipt.json"
    "GAIAOS/macos/GaiaFusion/evidence/pq/pq_receipt.json"
    "GAIAOS/macos/MacHealth/evidence/iq/iq_receipt.json"
    "GAIAOS/macos/MacHealth/evidence/oq/oq_receipt.json"
    "GAIAOS/macos/MacHealth/evidence/pq/pq_receipt.json"
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
echo -e "${GRN}  ✅ IQ: PASS (scripts/gamp5_iq.sh)${NC}"
echo -e "${GRN}  ✅ OQ: PASS (scripts/gamp5_oq.sh)${NC}"
echo -e "${GRN}  ✅ PQ: PASS (scripts/gamp5_pq.sh + TestRobot)${NC}"
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
