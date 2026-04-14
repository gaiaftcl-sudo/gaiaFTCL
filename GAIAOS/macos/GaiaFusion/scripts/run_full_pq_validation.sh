#!/usr/bin/env zsh
# GaiaFusion GFTCL-PQ-002: Master PQ Validation Script
# GAMP 5 Performance Qualification - Full Automated Test Suite
# Runs all 41 test protocols (PHY, CSE, QA, SAF, TAU)

set -e

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="$SCRIPT_DIR/.."
EVIDENCE_ROOT="$PROJECT_ROOT/evidence/pq_validation"
LOG_FILE="$EVIDENCE_ROOT/master_pq_run_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$EVIDENCE_ROOT"/{screenshots,telemetry,swap,geometry,tau,receipts,logs}

echo "═══════════════════════════════════════════════════════════════"
echo "GaiaFusion GFTCL-PQ-002 Master PQ Validation"
echo "GAMP 5 Performance Qualification - Full Test Suite"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Start Time: $(date)"
echo "Log File: $LOG_FILE"
echo "" | tee "$LOG_FILE"

# Track overall status — Zsh: use typeset not bash declare
typeset -i TOTAL_TESTS=0
typeset -i PASSED_TESTS=0
typeset -i FAILED_TESTS=0
typeset -A TEST_RESULTS

# ANSI colors — Zsh: use $'\033[...]' for actual escape character
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

function print_header() {
    print "" | tee -a "$LOG_FILE"
    print "═══════════════════════════════════════════════════════════════" | tee -a "$LOG_FILE"
    print " $1" | tee -a "$LOG_FILE"
    print "═══════════════════════════════════════════════════════════════" | tee -a "$LOG_FILE"
    print "" | tee -a "$LOG_FILE"
}

function print_step() {
    print "${BLUE}▶${NC} $1" | tee -a "$LOG_FILE"
}

function print_success() {
    print "${GREEN}✓${NC} $1" | tee -a "$LOG_FILE"
}

function print_error() {
    print "${RED}✗${NC} $1" | tee -a "$LOG_FILE"
}

function print_warning() {
    print "${YELLOW}⚠${NC} $1" | tee -a "$LOG_FILE"
}

function run_test_suite() {
    local suite_name=$1
    local test_class=$2
    
    print_step "Running $suite_name..."
    
    if swift test --filter "$test_class" 2>&1 | tee -a "$LOG_FILE"; then
        print_success "$suite_name PASSED"
        TEST_RESULTS[$suite_name]="PASS"
        return 0
    else
        print_error "$suite_name FAILED"
        TEST_RESULTS[$suite_name]="FAIL"
        print ""
        print "${RED}[PQ ABORT]${NC} $suite_name FAILED — STOP."
        print "Fix the issue and restart from IQ: scripts/iq_install.sh"
        exit 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# PHASE 0: Prerequisites Verification
# ═══════════════════════════════════════════════════════════════

print_header "PHASE 0: Prerequisites Verification"

# Verify IQ and OQ receipts exist
print_step "Verifying IQ/OQ receipts..."
IQ_RECEIPT="$PROJECT_ROOT/evidence/iq/iq_receipt.json"
OQ_RECEIPT="$PROJECT_ROOT/evidence/oq/oq_receipt.json"

if [[ ! -f "$IQ_RECEIPT" ]]; then
    print_error "IQ receipt missing — run scripts/iq_install.sh first"
    exit 1
fi

if [[ ! -f "$OQ_RECEIPT" ]]; then
    print_error "OQ receipt missing — run scripts/oq_validate.sh first"
    exit 1
fi

print_success "IQ/OQ receipts verified"

print_step "Checking Rust Metal renderer compilation..."
cd "$PROJECT_ROOT/MetalRenderer/rust"
if cargo build --release --target aarch64-apple-darwin 2>&1 | tee -a "$LOG_FILE"; then
    print_success "Rust Metal renderer compiled"
else
    print_error "Rust compilation FAILED"
    exit 1
fi
cd "$PROJECT_ROOT"

print_step "Checking Swift build..."
if swift build 2>&1 | tee -a "$LOG_FILE"; then
    print_success "Swift build succeeded"
else
    print_error "Swift build FAILED"
    exit 1
fi

print_step "Verifying Bitcoin heartbeat on mesh cells..."
if zsh "$SCRIPT_DIR/verify_mesh_bitcoin_heartbeat.sh" 2>&1 | tee -a "$LOG_FILE"; then
    print_success "All mesh cells synchronized"
else
    print_error "NATS/Bitcoin heartbeat verification FAILED"
    print_error "PQ-TAU tests require mesh synchronization — cannot proceed"
    print ""
    print "Fix: Deploy bitcoin-heartbeat service to mesh cells"
    print "Then restart from IQ: scripts/iq_install.sh"
    exit 1
fi

# ═══════════════════════════════════════════════════════════════
# PHASE 1: Physics Team Protocols (PQ-PHY-001 to PQ-PHY-008)
# ═══════════════════════════════════════════════════════════════

print_header "PHASE 1: Physics Team Protocols (8 tests)"

run_test_suite "PQ-PHY: Physics Team" "PhysicsTeamProtocols"
if [ $? -eq 0 ]; then
    ((PASSED_TESTS += 8))
else
    ((FAILED_TESTS += 8))
fi
((TOTAL_TESTS += 8))

# ═══════════════════════════════════════════════════════════════
# PHASE 2: Control Systems Engineering (PQ-CSE-001 to PQ-CSE-012)
# ═══════════════════════════════════════════════════════════════

print_header "PHASE 2: Control Systems Engineering (12 tests)"

run_test_suite "PQ-CSE: Control Systems" "ControlSystemsProtocols"
if [ $? -eq 0 ]; then
    ((PASSED_TESTS += 12))
else
    ((FAILED_TESTS += 12))
fi
((TOTAL_TESTS += 12))

# ═══════════════════════════════════════════════════════════════
# PHASE 3: Software QA (PQ-QA-001 to PQ-QA-010)
# ═══════════════════════════════════════════════════════════════

print_header "PHASE 3: Software QA (10 tests)"

run_test_suite "PQ-QA: Software Quality" "SoftwareQAProtocols"
if [ $? -eq 0 ]; then
    ((PASSED_TESTS += 10))
else
    ((FAILED_TESTS += 10))
fi
((TOTAL_TESTS += 10))

# ═══════════════════════════════════════════════════════════════
# PHASE 4: Safety Team (PQ-SAF-001 to PQ-SAF-008)
# ═══════════════════════════════════════════════════════════════

print_header "PHASE 4: Safety Team (8 tests)"

run_test_suite "PQ-SAF: Safety Systems" "SafetyTeamProtocols"
if [ $? -eq 0 ]; then
    ((PASSED_TESTS += 8))
else
    ((FAILED_TESTS += 8))
fi
((TOTAL_TESTS += 8))

# ═══════════════════════════════════════════════════════════════
# PHASE 5: Bitcoin τ Synchronization (PQ-TAU-001 to PQ-TAU-003)
# ═══════════════════════════════════════════════════════════════

print_header "PHASE 5: Bitcoin τ Synchronization (3 tests) - CRITICAL"

run_test_suite "PQ-TAU: Bitcoin Tau" "BitcoinTauProtocols"
if [ $? -eq 0 ]; then
    ((PASSED_TESTS += 3))
else
    ((FAILED_TESTS += 3))
    print_error "CRITICAL: Bitcoin τ synchronization failed - Mac cell not sovereign"
fi
((TOTAL_TESTS += 3))

# ═══════════════════════════════════════════════════════════════
# PHASE 6: Evidence Collection
# ═══════════════════════════════════════════════════════════════

print_header "PHASE 6: Evidence Collection"

print_step "Running evidence collection script..."
if zsh "$SCRIPT_DIR/generate_pq_evidence.sh" 2>&1 | tee -a "$LOG_FILE"; then
    print_success "Evidence collection complete"
else
    print_warning "Evidence collection had issues (proceeding)"
fi

# ═══════════════════════════════════════════════════════════════
# PHASE 7: Master Receipt Generation
# ═══════════════════════════════════════════════════════════════

print_header "PHASE 7: Master Receipt Generation"

RECEIPT_FILE="$EVIDENCE_ROOT/receipts/master_pq_receipt_$(date +%Y%m%d_%H%M%S).json"

cat > "$RECEIPT_FILE" <<EOF
{
  "document_id": "GFTCL-PQ-002-MASTER-RECEIPT",
  "version": "1.0",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "execution_summary": {
    "total_tests": $TOTAL_TESTS,
    "passed_tests": $PASSED_TESTS,
    "failed_tests": $FAILED_TESTS,
    "pass_rate": $(echo "scale=2; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc)
  },
  "test_suites": {
$(
first=true
for suite in "${(@k)TEST_RESULTS}"; do
    if [ "$first" = true ]; then
        first=false
    else
        echo ","
    fi
    echo "    \"$suite\": \"${TEST_RESULTS[$suite]}\""
done
)
  },
  "evidence_artifacts": {
    "screenshots": "evidence/pq_validation/screenshots/",
    "telemetry": "evidence/pq_validation/telemetry/",
    "swap_matrix": "evidence/pq_validation/swap/",
    "geometry": "evidence/pq_validation/geometry/",
    "tau_sync": "evidence/pq_validation/tau/",
    "logs": "evidence/pq_validation/logs/"
  },
  "regulatory_status": {
    "gamp5_compliant": $([ $FAILED_TESTS -eq 0 ] && echo "true" || echo "false"),
    "cern_ready": $([ $FAILED_TESTS -eq 0 ] && echo "true" || echo "false"),
    "requires_physics_lead_signature": true,
    "requires_safety_officer_signature": true,
    "requires_qa_manager_signature": true
  },
  "git_commit": "$(git rev-parse HEAD 2>/dev/null || echo 'unknown')",
  "execution_environment": {
    "hostname": "$(hostname)",
    "os": "$(uname -s)",
    "os_version": "$(sw_vers -productVersion 2>/dev/null || echo 'unknown')",
    "architecture": "$(uname -m)"
  }
}
EOF

print_success "Master receipt: $RECEIPT_FILE"

# ═══════════════════════════════════════════════════════════════
# PHASE 8: Final Summary
# ═══════════════════════════════════════════════════════════════

print_header "FINAL SUMMARY"

print "" | tee -a "$LOG_FILE"
print "Total Tests: $TOTAL_TESTS" | tee -a "$LOG_FILE"
print "${GREEN}Passed: $PASSED_TESTS${NC}" | tee -a "$LOG_FILE"
print "${RED}Failed: $FAILED_TESTS${NC}" | tee -a "$LOG_FILE"

if [ $FAILED_TESTS -eq 0 ]; then
    print "" | tee -a "$LOG_FILE"
    print "${GREEN}═══════════════════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
    print "${GREEN}✓ ALL TESTS PASSED - GAMP 5 COMPLIANT - CERN READY${NC}" | tee -a "$LOG_FILE"
    print "${GREEN}═══════════════════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
    print "" | tee -a "$LOG_FILE"
    print "Next Steps:" | tee -a "$LOG_FILE"
    print "  1. Physics Lead reviews GFTCL-PQ-002_v1.0.md" | tee -a "$LOG_FILE"
    print "  2. Safety Officer approves PQ-SAF results" | tee -a "$LOG_FILE"
    print "  3. QA Manager signs validation report" | tee -a "$LOG_FILE"
    print "  4. Submit to CERN regulatory review" | tee -a "$LOG_FILE"
    exit 0
else
    print "" | tee -a "$LOG_FILE"
    print "${RED}═══════════════════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
    print "${RED}✗ VALIDATION FAILED - REVIEW REQUIRED${NC}" | tee -a "$LOG_FILE"
    print "${RED}═══════════════════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
    print "" | tee -a "$LOG_FILE"
    print "Failed Test Suites:" | tee -a "$LOG_FILE"
    for suite in "${(@k)TEST_RESULTS}"; do
        if [ "${TEST_RESULTS[$suite]}" = "FAIL" ]; then
            print "  ${RED}✗${NC} $suite" | tee -a "$LOG_FILE"
        fi
    done
    print "" | tee -a "$LOG_FILE"
    print "Review log: $LOG_FILE" | tee -a "$LOG_FILE"
    exit 1
fi
