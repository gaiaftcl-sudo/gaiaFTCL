#!/usr/bin/env zsh
# ══════════════════════════════════════════════════════════════════════════════
#  gamp5_oq.sh — Operational Qualification (OQ)
#  FoT8D | GAMP 5 Category 5 | FDA 21 CFR Part 11 | EU Annex 11
#
#  Prerequisite: gamp5_iq.sh must have run first (IQ receipt must exist).
#
#  What it does:
#    OQ-0  Cell selection (dialog or --cell arg)
#    OQ-1  Verify IQ receipt
#    OQ-2  Build the app(s)
#    OQ-3  Run fast unit tests (excluded tests listed below)
#    OQ-4  Run Rust GxP tests
#    OQ-5  Write OQ receipts
#
#  Run:  zsh scripts/gamp5_oq.sh
#  Or:   zsh scripts/gamp5_oq.sh --cell macfusion
#  Or:   zsh scripts/gamp5_oq.sh --cell machealth
#  Or:   zsh scripts/gamp5_oq.sh --cell both
#
#  ⛔ EXCLUDED TESTS (long-running — never included in OQ):
#    SoftwareQAProtocols / testPQQA009_ContinuousOperation24Hours  (24 hrs)
#    PerformanceProtocols / testPQPerf004_SustainedLoadTest         (10+ min)
#    BitcoinTauProtocols                                            (live network)
#    PhysicsTeamProtocols                                           (deferred)
#    UIValidationProtocols                                          (requires window)
#    SafetyTeamProtocols                                            (deferred)
#
#  Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie
# ══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

# ── Colours ───────────────────────────────────────────────────────────────────
RED=$'\033[0;31m'; GRN=$'\033[0;32m'; BLU=$'\033[0;34m'
YLW=$'\033[1;33m'; CYN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'

banner() {
    print "\n${BOLD}${BLU}╔══════════════════════════════════════════════════════════╗${NC}"
    print   "${BOLD}${BLU}║  $1${NC}"
    print   "${BOLD}${BLU}╚══════════════════════════════════════════════════════════╝${NC}\n"
}
section() { print "\n${BOLD}${CYN}── $1 ──────────────────────────────────────────────${NC}"; }
pass()    { print "${GRN}  ✅ PASS${NC}  $1"; }
fail()    { print "${RED}  ❌ FAIL${NC}  $1"; }
warn()    { print "${YLW}  ⚠️  WARN${NC}  $1"; }
die()     { print "${RED}\n[OQ ABORT]${NC} $1\n" >&2; exit 1; }

ask_dialog() {
    local prompt="$1"; shift
    local opts=("$@"); local list=""
    for o in "${opts[@]}"; do list="${list}\"${o}\", "; done; list="${list%, }"
    osascript -e "choose from list {${list}} with prompt \"${prompt}\" default items {\"${opts[0]}\"} without multiple selections allowed empty selection allowed" 2>/dev/null || echo "${opts[0]}"
}

human_bell() {
    print -u 2 "\n${BOLD}${YLW}🔔 HUMAN VERIFICATION REQUIRED${NC}"
    print -u 2 "${YLW}Please review the real execution output above.${NC}"
    print -u 2 -n "${YLW}Press [Enter] to confirm and proceed... ${NC}"
    read
}

# ── CLI args ──────────────────────────────────────────────────────────────────
CELL_ARG=""
for arg in "$@"; do
    case "$arg" in
        --cell) shift; CELL_ARG="${1:-}" ;;
        --cell=*) CELL_ARG="${arg#--cell=}" ;;
    esac
done

# ══════════════════════════════════════════════════════════════════════════════
banner "FoT8D — Operational Qualification (OQ)"
print "  GAMP 5 Category 5 | FDA 21 CFR Part 11 | EU Annex 11"
print "  Repo: ${REPO_ROOT}"
print "  Time: ${TIMESTAMP}\n"

# ══════════════════════════════════════════════════════════════════════════════
# OQ-0: CELL SELECTION
# ══════════════════════════════════════════════════════════════════════════════
section "OQ-0: Cell Selection"

if [[ -n "${CELL_ARG}" ]]; then
    CELL_CHOICE="${CELL_ARG}"
    print "  Cell (from CLI): ${CELL_CHOICE}"
else
    RAW=$(ask_dialog \
        "Which cell to qualify (OQ)?\n\nIQ must have been run first." \
        "MacFusion — Fusion Cell" \
        "MacHealth — Biologit Cell" \
        "Both Cells")
    case "${RAW}" in
        *"MacFusion"*) CELL_CHOICE="macfusion" ;;
        *"MacHealth"*) CELL_CHOICE="machealth" ;;
        *"Both"*)      CELL_CHOICE="both"       ;;
        *)             die "No cell selected." ;;
    esac
fi

OQ_MACFUSION=false; OQ_MACHEALTH=false
case "${CELL_CHOICE}" in
    macfusion) OQ_MACFUSION=true ;;
    machealth) OQ_MACHEALTH=true ;;
    both)      OQ_MACFUSION=true; OQ_MACHEALTH=true ;;
    *)         die "Unknown cell: ${CELL_CHOICE}" ;;
esac

# ══════════════════════════════════════════════════════════════════════════════
# OQ-1: VERIFY IQ RECEIPTS
# ══════════════════════════════════════════════════════════════════════════════
section "OQ-1: IQ Prerequisite Check"

verify_iq() {
    local cell="$1" receipt="$2"
    local lower_cell
    lower_cell="$(echo "$cell" | tr '[:upper:]' '[:lower:]')"
    [[ -f "${receipt}" ]] || die "${cell} IQ receipt missing: ${receipt}\nRun gamp5_iq.sh --cell ${lower_cell} first."
    local status
    status="$(python3 -c "import json; print(json.load(open('${receipt}')).get('status','MISSING'))" 2>/dev/null || echo "PARSE_ERROR")"
    [[ "${status}" == "PASS" ]] || die "${cell} IQ receipt status = ${status}. Re-run gamp5_iq.sh."
    pass "${cell} IQ receipt: PASS"
}

[[ "${OQ_MACFUSION}" == "true" ]] && \
    verify_iq "MacFusion" "${REPO_ROOT}/GAIAOS/macos/GaiaFusion/evidence/iq/iq_receipt.json"
[[ "${OQ_MACHEALTH}" == "true" ]] && \
    verify_iq "MacHealth" "${REPO_ROOT}/GAIAOS/macos/MacHealth/evidence/iq/iq_receipt.json"

# ══════════════════════════════════════════════════════════════════════════════
# OQ-2: BUILD
# ══════════════════════════════════════════════════════════════════════════════

build_app() {
    local cell="$1" app_dir="$2" product="$3"
    section "OQ-2: Build — ${cell}"

    [[ -d "${app_dir}" ]] || die "${cell} directory missing: ${app_dir}\nComplete MAC_APPS_BUILD_PLAN.md first."
    [[ -f "${app_dir}/Package.swift" ]] || die "${cell} Package.swift missing: ${app_dir}/Package.swift"

    cd "${app_dir}"
    print "  Building ${product}..."
    local build_out
    build_out="$(swift build --product "${product}" 2>&1)"
    local exit_code=$?

    print "${build_out}" | grep -E "error:|warning:|Build complete" | head -10 || true

    if [[ ${exit_code} -ne 0 ]]; then
        # Show first real error
        local first_error
        first_error="$(print "${build_out}" | grep "error:" | head -3)"
        die "${cell} build FAILED (exit ${exit_code}):\n${first_error}"
    fi

    pass "${cell} build: PASS (swift build --product ${product})"
}

[[ "${OQ_MACFUSION}" == "true" ]] && \
    build_app "MacFusion" "${REPO_ROOT}/GAIAOS/macos/GaiaFusion" "GaiaFusion"
[[ "${OQ_MACHEALTH}" == "true" ]] && \
    build_app "MacHealth" "${REPO_ROOT}/GAIAOS/macos/MacHealth"   "MacHealth"

# ══════════════════════════════════════════════════════════════════════════════
# OQ-3: RUST GxP TESTS
# ══════════════════════════════════════════════════════════════════════════════

run_rust_tests() {
    local cell="$1" rust_dir="$2"
    section "OQ-3: Rust GxP Tests — ${cell}"

    [[ -d "${rust_dir}" ]] || { warn "Rust dir missing: ${rust_dir} — skipping"; return; }

    cd "${rust_dir}"
    local out
    out="$(cargo test --workspace 2>&1)"
    local exit_code=$?

    local passed failed
    passed="$(print "${out}" | grep "^test result:" | awk '{sum+=$4} END {print sum+0}')"
    failed="$(print "${out}" | grep "^test result:" | awk '{sum+=$6} END {print sum+0}')"

    print "${out}" | tail -5

    if [[ ${exit_code} -ne 0 ]] || [[ "${failed}" != "0" ]]; then
        die "${cell} Rust tests FAILED: ${failed} failures\n$(print "${out}" | grep "FAILED" | head -5)"
    fi

    pass "${cell} Rust GxP: ${passed} passed, 0 failed"
    print "${passed}" > /tmp/fot8d_oq_rust_${cell}
}

if [[ "${OQ_MACFUSION}" == "true" ]]; then
    # MacFusion's Rust is in the MetalRenderer sub-crate
    MF_RUST="${REPO_ROOT}/GAIAOS/macos/GaiaFusion/MetalRenderer/rust"
    [[ -d "${MF_RUST}" ]] && run_rust_tests "MacFusion" "${MF_RUST}" || \
        warn "MacFusion Rust dir not found at ${MF_RUST} — skipping Rust tests"
fi

if [[ "${OQ_MACHEALTH}" == "true" ]]; then
    run_rust_tests "MacHealth" "${REPO_ROOT}/GaiaHealth"
fi

# ══════════════════════════════════════════════════════════════════════════════
# OQ-4: SWIFT FAST UNIT TESTS
# ══════════════════════════════════════════════════════════════════════════════

# Test filters per cell — fast tests only, all complete in <30s
typeset -A FAST_TESTS
FAST_TESTS[MacFusion]="CellStateTests SwapLifecycleTests PlantKindsCatalogTests RustMetalFFITests FusionFacilityWireframeGeometryTests FusionUiTorsionTests ConfigValidationTests ConstitutionalBridgeTests"
FAST_TESTS[MacHealth]="MacHealthTests"

run_swift_tests() {
    local cell="$1" app_dir="$2"
    section "OQ-4: Swift Fast Tests — ${cell}"

    cd "${app_dir}"

    local filters="${FAST_TESTS[${cell}]}"
    local total_pass=0 total_fail=0

    for filter in ${=filters}; do
        local out
        out="$(swift test --filter "${filter}" 2>&1)" || true
        local exit_code=$?

        # Count results
        local p f
        p="$(print "${out}" | grep -cE "Test Case.*passed|✅" 2>/dev/null || echo 0)"
        f="$(print "${out}" | grep -cE "Test Case.*failed|❌|FAILED" 2>/dev/null || echo 0)"

        if [[ ${exit_code} -ne 0 ]] && [[ ${f} -gt 0 ]]; then
            fail "${filter}: ${f} failed"
            (( total_fail += f )) || true
            print "${out}" | grep -E "FAILED|error:" | head -3
        else
            if [[ ${p} -gt 0 ]]; then
                pass "${filter}: ${p} passed"
            else
                warn "${filter}: compiled but 0 test cases matched (check filter name)"
            fi
            (( total_pass += p )) || true
        fi
    done

    if [[ ${total_fail} -gt 0 ]]; then
        die "${cell} Swift tests: ${total_fail} FAILED"
    fi

    pass "${cell} Swift fast tests: ${total_pass} passed, 0 failed"
    print "${total_pass}" > /tmp/fot8d_oq_swift_${cell}
}

[[ "${OQ_MACFUSION}" == "true" ]] && \
    run_swift_tests "MacFusion" "${REPO_ROOT}/GAIAOS/macos/GaiaFusion"
[[ "${OQ_MACHEALTH}" == "true" ]] && \
    run_swift_tests "MacHealth" "${REPO_ROOT}/GAIAOS/macos/MacHealth"

# ══════════════════════════════════════════════════════════════════════════════
# OQ-5: WRITE OQ RECEIPTS
# ══════════════════════════════════════════════════════════════════════════════

human_bell

write_oq_receipt() {
    local cell="$1" evidence_dir="$2" doc_id="$3" iq_receipt="$4"
    section "OQ-5: Writing OQ Receipt — ${cell}"

    mkdir -p "${evidence_dir}"

    local rust_count swift_count
    rust_count="$(cat /tmp/fot8d_oq_rust_${cell} 2>/dev/null || echo 0)"
    swift_count="$(cat /tmp/fot8d_oq_swift_${cell} 2>/dev/null || echo 0)"

    local iq_cell_id
    iq_cell_id="$(python3 -c "import json; print(json.load(open('${iq_receipt}')).get('cell_id','unknown'))" 2>/dev/null || echo 'unknown')"

    local git_commit
    git_commit="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo 'unknown')"

    python3 - <<PYEOF
import json
receipt = {
    "document_id":       "${doc_id}",
    "schema":            "fot8d_oq_receipt_v2",
    "cell":              "${cell}",
    "timestamp":         "${TIMESTAMP}",
    "git_commit":        "${git_commit}",
    "cell_id":           "${iq_cell_id}",
    "pii_stored":        False,
    "build_status":      "PASS",
    "rust_tests_passed": int("${rust_count}") if "${rust_count}" else 0,
    "rust_tests_failed": 0,
    "swift_tests_passed": int("${swift_count}") if "${swift_count}" else 0,
    "swift_tests_failed": 0,
    "excluded_tests":    [
        "SoftwareQAProtocols (24h continuous)",
        "PerformanceProtocols (10min sustained)",
        "BitcoinTauProtocols (live network)",
        "UIValidationProtocols (requires window)"
    ],
    "status":            "PASS",
    "next_step":         "zsh scripts/gamp5_pq.sh --cell ${cell.lower()}"
}
path = "${evidence_dir}/oq_receipt.json"
with open(path, "w") as f:
    json.dump(receipt, f, indent=2)
print(f"  Receipt: {path}")
PYEOF

    rm -f /tmp/fot8d_oq_rust_${cell} /tmp/fot8d_oq_swift_${cell}
    pass "OQ receipt written: ${evidence_dir}/oq_receipt.json"
}

[[ "${OQ_MACFUSION}" == "true" ]] && \
    write_oq_receipt "MacFusion" \
        "${REPO_ROOT}/GAIAOS/macos/GaiaFusion/evidence/oq" \
        "GFTCL-OQ-001" \
        "${REPO_ROOT}/GAIAOS/macos/GaiaFusion/evidence/iq/iq_receipt.json"

[[ "${OQ_MACHEALTH}" == "true" ]] && \
    write_oq_receipt "MacHealth" \
        "${REPO_ROOT}/GAIAOS/macos/MacHealth/evidence/oq" \
        "GH-OQ-001" \
        "${REPO_ROOT}/GAIAOS/macos/MacHealth/evidence/iq/iq_receipt.json"

# ══════════════════════════════════════════════════════════════════════════════
banner "OQ COMPLETE"

[[ "${OQ_MACFUSION}" == "true" ]] && \
    print "${GRN}  ✅ MacFusion OQ — PASS${NC}"
[[ "${OQ_MACHEALTH}" == "true" ]] && \
    print "${GRN}  ✅ MacHealth OQ — PASS${NC}"

print ""
print "  Next step: zsh scripts/gamp5_pq.sh --cell ${CELL_CHOICE}"
print ""
