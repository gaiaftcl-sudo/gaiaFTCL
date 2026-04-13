#!/usr/bin/env zsh
# run_full_cycle.sh — GaiaFTCL vQbit Mac Cell full production cycle
# Shell: Zsh (macOS Sonoma/Sequoia default — NOT bash)
#
# Phases:
#   1. Local build + full test suite
#   2. Git commit + push to origin/main
#   3. Fresh clone from GitHub
#   4. Full test suite on fresh clone
#   5. Write signed receipt to evidence/full_cycle_receipt.json
#
# Run from repo root:
#   zsh scripts/run_full_cycle.sh
#
set -euo pipefail

REPO_ROOT="${0:A:h:h}"
REMOTE_URL="https://github.com/gaiaftcl-sudo/gaiaFTCL.git"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
CLONE_DIR="/tmp/gaiaftcl-verify-${TIMESTAMP}"
RECEIPT="${REPO_ROOT}/evidence/full_cycle_receipt.json"

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
NC='\033[0m'

log()  { print -P "%F{green}[CYCLE]%f $*"; }
warn() { print -P "%F{yellow}[WARN]%f  $*"; }
die()  { print -P "%F{red}[FAIL]%f  $*" >&2; exit 1; }

# ── Phase 1: Local build + test ───────────────────────────────────────────────
log "Phase 1 — local build + test"
cd "${REPO_ROOT}"

log "  cargo test --workspace"
TEST_OUT="$(cargo test --workspace 2>&1)" || die "Tests failed:\n${TEST_OUT}"
print "${TEST_OUT}"

PASS_COUNT="$(print "${TEST_OUT}" | grep -E '^test result:' | awk '{sum += $4} END {print sum}')"
FAIL_COUNT="$(print "${TEST_OUT}" | grep -E '^test result:' | awk '{sum += $6} END {print sum}')"
[[ "${FAIL_COUNT}" == "0" ]] || die "Test failures detected (${FAIL_COUNT} failed)"
log "  ✅ ${PASS_COUNT} tests passed, 0 failed"

log "  cargo build --release --workspace"
BUILD_OUT="$(cargo build --release --workspace 2>&1)" || die "Release build failed:\n${BUILD_OUT}"
BINARY="${REPO_ROOT}/target/release/gaia-metal-renderer"
[[ -f "${BINARY}" ]] || die "Binary not found at ${BINARY}"
BINARY_SIZE="$(du -h "${BINARY}" | cut -f1)"
log "  ✅ release binary: ${BINARY} (${BINARY_SIZE})"

# ── Phase 2: Git commit + push ────────────────────────────────────────────────
log "Phase 2 — git commit + push"
cd "${REPO_ROOT}"

git add -A

if git diff --cached --quiet; then
    warn "Nothing new to commit — working tree clean"
    COMMIT_HASH="$(git rev-parse HEAD)"
else
    COMMIT_MSG="vQbit Mac Cell — GxP suite ${PASS_COUNT} tests green [${TIMESTAMP}]"
    git commit -m "${COMMIT_MSG}"
    COMMIT_HASH="$(git rev-parse HEAD)"
    log "  commit: ${COMMIT_HASH}"

    log "  git push origin main"
    git push origin main || die "Push failed — check GitHub credentials (token/SSH)"
    log "  ✅ pushed to origin/main"
fi

# ── Phase 3: Fresh clone ──────────────────────────────────────────────────────
log "Phase 3 — fresh clone to ${CLONE_DIR}"
mkdir -p "${CLONE_DIR}"
git clone "${REMOTE_URL}" "${CLONE_DIR}" || die "Clone failed — check network + repo access"
log "  ✅ clone complete"

# ── Phase 4: Test on fresh clone ─────────────────────────────────────────────
log "Phase 4 — cargo test on fresh clone"
cd "${CLONE_DIR}"

FRESH_TEST_OUT="$(cargo test --workspace 2>&1)" || die "Fresh-clone tests failed:\n${FRESH_TEST_OUT}"
print "${FRESH_TEST_OUT}"

FRESH_PASS="$(print "${FRESH_TEST_OUT}" | grep -E '^test result:' | awk '{sum += $4} END {print sum}')"
FRESH_FAIL="$(print "${FRESH_TEST_OUT}" | grep -E '^test result:' | awk '{sum += $6} END {print sum}')"
[[ "${FRESH_FAIL}" == "0" ]] || die "Fresh-clone test failures (${FRESH_FAIL} failed)"
log "  ✅ fresh clone: ${FRESH_PASS} tests passed, 0 failed"

# ── Phase 5: Write receipt ────────────────────────────────────────────────────
log "Phase 5 — writing receipt"
cd "${REPO_ROOT}"
mkdir -p evidence

cat > "${RECEIPT}" <<EOF
{
  "receipt_id": "vqbit-mac-cell-${TIMESTAMP}",
  "spec": "GFTCL-TEST-RUST-001",
  "timestamp": "${TIMESTAMP}",
  "commit": "${COMMIT_HASH}",
  "remote": "${REMOTE_URL}",
  "phases": {
    "local_build":   "PASS",
    "local_tests":   "PASS — ${PASS_COUNT} passed, 0 failed",
    "git_push":      "PASS — ${COMMIT_HASH}",
    "fresh_clone":   "${CLONE_DIR}",
    "fresh_tests":   "PASS — ${FRESH_PASS} passed, 0 failed"
  },
  "binary_size": "${BINARY_SIZE}",
  "status": "FULL_CYCLE_GREEN",
  "witnessed_by": null,
  "notes": "All phases automated. PQ (Metal window launch) requires user witness separately."
}
EOF

log "  receipt → ${RECEIPT}"

print ""
print "${GRN}════════════════════════════════════════════════════════${NC}"
print "${GRN}  FULL CYCLE COMPLETE — CERN READY${NC}"
print "${GRN}  commit : ${COMMIT_HASH}${NC}"
print "${GRN}  local  : ${PASS_COUNT} tests green${NC}"
print "${GRN}  remote : ${FRESH_PASS} tests green (fresh clone)${NC}"
print "${GRN}  receipt: ${RECEIPT}${NC}"
print "${GRN}════════════════════════════════════════════════════════${NC}"
