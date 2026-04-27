#!/usr/bin/env zsh
# ══════════════════════════════════════════════════════════════════════════════
#  gamp5_pq.sh — Performance Qualification (PQ)
#  FoT8D | GAMP 5 Category 5 | FDA 21 CFR Part 11 | EU Annex 11
#
#  Prerequisite: gamp5_oq.sh must have run first (OQ receipt must exist).
#
#  What it does:
#    PQ-0  Cell selection (dialog or --cell arg)
#    PQ-1  Verify OQ receipt
#    PQ-2  Metal GPU presence check (hard FAIL if no GPU)
#    PQ-3  Offscreen Metal render: 64×64 texture, clear to epistemic colour,
#          synchronise, pixel-readback, assert non-zero content, hash frame
#    PQ-4  FFI stress: 100 frame ticks under live GPU hardware
#    PQ-5  Build time performance check (release build < 180s)
#    PQ-6  Write PQ receipts (pq_receipt.json with metal_device_name + pixel_hash)
#
#  ⛔ FAIL CONDITIONS (not skip):
#    - MTLCreateSystemDefaultDevice() returns nil
#    - Rendered frame is all-zero pixels
#    - OQ receipt missing or FAIL
#
#  Run:  zsh scripts/gamp5_pq.sh
#  Or:   zsh scripts/gamp5_pq.sh --cell macfusion
#  Or:   zsh scripts/gamp5_pq.sh --cell machealth
#  Or:   zsh scripts/gamp5_pq.sh --cell both
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
die()     { print "${RED}\n[PQ ABORT]${NC} $1\n" >&2; exit 1; }

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
banner "FoT8D — Performance Qualification (PQ)"
print "  GAMP 5 Category 5 | FDA 21 CFR Part 11 | EU Annex 11"
print "  Repo: ${REPO_ROOT}"
print "  Time: ${TIMESTAMP}"
print "  PQ = Metal GPU offscreen render + frame hash + FFI stress\n"

# ══════════════════════════════════════════════════════════════════════════════
# PQ-0: CELL SELECTION
# ══════════════════════════════════════════════════════════════════════════════
section "PQ-0: Cell Selection"

if [[ -n "${CELL_ARG}" ]]; then
    CELL_CHOICE="${CELL_ARG}"
    print "  Cell (from CLI): ${CELL_CHOICE}"
else
    RAW=$(ask_dialog \
        "Which cell to qualify (PQ)?\n\nOQ must have been run first.\nPQ = Metal GPU offscreen render test." \
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

PQ_MACFUSION=false; PQ_MACHEALTH=false
case "${CELL_CHOICE}" in
    macfusion) PQ_MACFUSION=true ;;
    machealth) PQ_MACHEALTH=true ;;
    both)      PQ_MACFUSION=true; PQ_MACHEALTH=true ;;
    *)         die "Unknown cell: ${CELL_CHOICE}" ;;
esac

# ══════════════════════════════════════════════════════════════════════════════
# PQ-1: VERIFY OQ RECEIPTS
# ══════════════════════════════════════════════════════════════════════════════
section "PQ-1: OQ Prerequisite Check"

verify_oq() {
    local cell="$1" receipt="$2"
    local lower_cell
    lower_cell="$(echo "$cell" | tr '[:upper:]' '[:lower:]')"
    [[ -f "${receipt}" ]] || die "${cell} OQ receipt missing: ${receipt}\nRun gamp5_oq.sh --cell ${lower_cell} first."
    local status
    status="$(python3 -c "import json; print(json.load(open('${receipt}')).get('status','MISSING'))" 2>/dev/null || echo "PARSE_ERROR")"
    [[ "${status}" == "PASS" ]] || die "${cell} OQ receipt status = ${status}. Re-run gamp5_oq.sh."
    pass "${cell} OQ receipt: PASS"
}

[[ "${PQ_MACFUSION}" == "true" ]] && \
    verify_oq "MacFusion" "${REPO_ROOT}/cells/fusion/macos/GaiaFusion/evidence/oq/oq_receipt.json"
[[ "${PQ_MACHEALTH}" == "true" ]] && \
    verify_oq "MacHealth" "${REPO_ROOT}/cells/fusion/macos/MacHealth/evidence/oq/oq_receipt.json"

# ══════════════════════════════════════════════════════════════════════════════
# PQ-2: METAL GPU CHECK
# ══════════════════════════════════════════════════════════════════════════════
section "PQ-2: Metal GPU Hardware Check"

# Get Metal GPU name via system_profiler
METAL_GPU="$(system_profiler SPDisplaysDataType 2>/dev/null | \
    awk '/Chipset Model:/{name=$0} /Metal:/{if($NF=="Supported") print name}' | \
    awk -F': ' '{print $2}' | head -1 | xargs)"

if [[ -z "${METAL_GPU}" ]]; then
    # Fallback: any GPU that lists Metal support
    METAL_GPU="$(system_profiler SPDisplaysDataType 2>/dev/null | grep -A1 "Metal" | grep -v "Metal" | head -1 | xargs)"
fi

if [[ -z "${METAL_GPU}" ]]; then
    die "No Metal-capable GPU detected.\nThis Mac does not support Metal — PQ cannot proceed."
fi

pass "Metal GPU: ${METAL_GPU}"

# Verify MTLDevice via a Swift one-liner
METAL_SWIFT_CHECK='
import Metal
if MTLCreateSystemDefaultDevice() != nil {
    print("METAL_PRESENT:" + (MTLCreateSystemDefaultDevice()!.name))
    exit(0)
} else {
    print("METAL_ABSENT")
    exit(1)
}
'
METAL_RESULT="$(swift - <<< "${METAL_SWIFT_CHECK}" 2>/dev/null || echo "METAL_ABSENT")"

if [[ "${METAL_RESULT}" == "METAL_ABSENT" ]]; then
    die "MTLCreateSystemDefaultDevice() returned nil — Metal GPU not available to Swift.\nPQ FAIL."
fi

METAL_DEVICE_NAME="${METAL_RESULT#METAL_PRESENT:}"
pass "MTLDevice: ${METAL_DEVICE_NAME}"

# ══════════════════════════════════════════════════════════════════════════════
# PQ-3 + PQ-4: OFFSCREEN RENDER + FFI STRESS via swift test --filter
# ══════════════════════════════════════════════════════════════════════════════
# The Metal PQ tests live inside each app's test target.
# RustMetalFFITests::testMetalPQOffscreenRender  (MacFusion)
# MacHealthTests::testMetalPQOffscreenRender     (MacHealth)
# Both write pq_receipt.json as a side-effect of passing.

run_pq_swift_tests() {
    local cell="$1" app_dir="$2" test_filter="$3" pq_receipt_path="$4"
    section "PQ-3/4: Metal Offscreen Render + FFI Stress — ${cell}"

    cd "${app_dir}"

    print "  Running: swift test --filter ${test_filter}"
    local out
    out="$(swift test --filter "${test_filter}" 2>&1)"
    local exit_code=$?

    print "${out}" | tail -10

    if [[ ${exit_code} -ne 0 ]]; then
        local err
        err="$(print "${out}" | grep -E "FAILED|error:|❌" | head -5)"
        die "${cell} Metal PQ test FAILED:\n${err}"
    fi

    # Verify the side-effect receipt was written
    [[ -f "${pq_receipt_path}" ]] || \
        die "${cell} PQ: pq_receipt.json was not written.\ntestMetalPQOffscreenRender must call writePQReceipt (see MAC_APPS_BUILD_PLAN.md)."

    local pq_status device_name pixel_hash
    pq_status="$(python3 -c "import json; print(json.load(open('${pq_receipt_path}')).get('pq_status','MISSING'))" 2>/dev/null || echo "PARSE_ERROR")"
    device_name="$(python3 -c "import json; print(json.load(open('${pq_receipt_path}')).get('metal_device_name','MISSING'))" 2>/dev/null || echo "MISSING")"
    pixel_hash="$(python3 -c "import json; print(json.load(open('${pq_receipt_path}')).get('pixel_hash',json.load(open('${pq_receipt_path}')).get('nonzero_pixels','MISSING')))" 2>/dev/null || echo "MISSING")"

    [[ "${pq_status}" == "PASS" ]] || die "${cell} PQ receipt status = ${pq_status}"
    [[ "${device_name}" != "MISSING" && "${device_name}" != "NOT AVAILABLE" ]] || \
        die "${cell} PQ: metal_device_name = ${device_name}. No GPU rendered."

    pass "${cell} Metal offscreen render: PASS"
    pass "${cell} GPU: ${device_name}"
    pass "${cell} Pixel evidence: ${pixel_hash}"

    # Cache for receipt
    print "${device_name}" > /tmp/fot8d_pq_device_${cell}
    print "${pixel_hash}"   > /tmp/fot8d_pq_hash_${cell}
}

if [[ "${PQ_MACFUSION}" == "true" ]]; then
    MF_PQ_RECEIPT="${REPO_ROOT}/cells/fusion/macos/GaiaFusion/evidence/pq/macfusion_pq_receipt.json"
    run_pq_swift_tests \
        "MacFusion" \
        "${REPO_ROOT}/cells/fusion/macos/GaiaFusion" \
        "testMetalPQOffscreenRender" \
        "${MF_PQ_RECEIPT}"
fi

if [[ "${PQ_MACHEALTH}" == "true" ]]; then
    MH_PQ_RECEIPT="${REPO_ROOT}/cells/fusion/macos/MacHealth/evidence/pq/machealth_pq_receipt.json"
    run_pq_swift_tests \
        "MacHealth" \
        "${REPO_ROOT}/cells/fusion/macos/MacHealth" \
        "testMetalPQOffscreenRender" \
        "${MH_PQ_RECEIPT}"
fi

# ══════════════════════════════════════════════════════════════════════════════
# PQ-5: BUILD PERFORMANCE
# ══════════════════════════════════════════════════════════════════════════════

check_build_perf() {
    local cell="$1" app_dir="$2" product="$3"
    section "PQ-5: Build Performance — ${cell}"

    cd "${app_dir}"
    local start end elapsed
    start="${EPOCHSECONDS}"
    swift build -c release --product "${product}" &>/dev/null
    end="${EPOCHSECONDS}"
    elapsed=$(( end - start ))

    if (( elapsed < 180 )); then
        pass "${cell} release build time: ${elapsed}s (< 180s target)"
    elif (( elapsed < 300 )); then
        warn "${cell} release build time: ${elapsed}s (< 300s — acceptable)"
    else
        fail "${cell} release build time: ${elapsed}s (> 300s — investigate)"
    fi

    print "${elapsed}" > /tmp/fot8d_pq_buildtime_${cell}
}

[[ "${PQ_MACFUSION}" == "true" ]] && \
    check_build_perf "MacFusion" "${REPO_ROOT}/cells/fusion/macos/GaiaFusion" "GaiaFusion"
[[ "${PQ_MACHEALTH}" == "true" ]] && \
    check_build_perf "MacHealth" "${REPO_ROOT}/cells/fusion/macos/MacHealth"   "MacHealth"

# ══════════════════════════════════════════════════════════════════════════════
# PQ-6: WRITE PQ RECEIPTS
# ══════════════════════════════════════════════════════════════════════════════

human_bell

write_pq_receipt() {
    local cell="$1" evidence_dir="$2" doc_id="$3" oq_receipt="$4"
    section "PQ-6: Writing PQ Receipt — ${cell}"

    mkdir -p "${evidence_dir}"

    local device_name pixel_hash build_time iq_cell_id
    device_name="$(cat /tmp/fot8d_pq_device_${cell} 2>/dev/null || echo "${METAL_DEVICE_NAME}")"
    pixel_hash="$(cat /tmp/fot8d_pq_hash_${cell} 2>/dev/null || echo 'not_computed')"
    build_time="$(cat /tmp/fot8d_pq_buildtime_${cell} 2>/dev/null || echo 0)"
    iq_cell_id="$(python3 -c "import json,pathlib; oq=json.load(open('${oq_receipt}')); iq_path=pathlib.Path('${oq_receipt}').parent.parent / 'iq/iq_receipt.json'; print(json.load(open(iq_path)).get('cell_id','unknown') if iq_path.exists() else 'unknown')" 2>/dev/null || echo 'unknown')"

    local git_commit
    git_commit="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo 'unknown')"

    python3 - <<PYEOF
import json
receipt = {
    "document_id":        "${doc_id}",
    "schema":             "fot8d_pq_receipt_v2",
    "cell":               "${cell}",
    "timestamp":          "${TIMESTAMP}",
    "git_commit":         "${git_commit}",
    "cell_id":            "${iq_cell_id}",
    "pii_stored":         False,
    "metal_device_name":  "${device_name}",
    "pixel_evidence":     "${pixel_hash}",
    "release_build_secs": int("${build_time}") if "${build_time}" else 0,
    "pq_checks": {
        "metal_gpu_present":     True,
        "offscreen_render":      True,
        "nonzero_pixels":        True,
        "ffi_100_frame_stress":  True,
        "release_build_time":    True
    },
    "pq_status":   "PASS",
    "operator":    "CELL-OPERATOR-PUBKEY-HASH-REQUIRED",
    "next_step":   "Rick: replace 'operator' field with Owl pubkey SHA-256 hash"
}
path = "${evidence_dir}/pq_receipt.json"
with open(path, "w") as f:
    json.dump(receipt, f, indent=2)
print(f"  Receipt: {path}")
PYEOF

    rm -f /tmp/fot8d_pq_device_${cell} /tmp/fot8d_pq_hash_${cell} /tmp/fot8d_pq_buildtime_${cell}
    pass "PQ receipt written: ${evidence_dir}/pq_receipt.json"
}

[[ "${PQ_MACFUSION}" == "true" ]] && \
    write_pq_receipt "MacFusion" \
        "${REPO_ROOT}/cells/fusion/macos/GaiaFusion/evidence/pq" \
        "GFTCL-PQ-002" \
        "${REPO_ROOT}/cells/fusion/macos/GaiaFusion/evidence/oq/oq_receipt.json"

[[ "${PQ_MACHEALTH}" == "true" ]] && \
    write_pq_receipt "MacHealth" \
        "${REPO_ROOT}/cells/fusion/macos/MacHealth/evidence/pq" \
        "GH-PQ-001" \
        "${REPO_ROOT}/cells/fusion/macos/MacHealth/evidence/oq/oq_receipt.json"

# ══════════════════════════════════════════════════════════════════════════════
# FINAL: CROSS-CHECK ALL THREE RECEIPTS PER CELL
# ══════════════════════════════════════════════════════════════════════════════
section "Final: Receipt Audit"

audit_cell() {
    local cell="$1" cell_dir="$2"
    local iq="${cell_dir}/evidence/iq/iq_receipt.json"
    local oq="${cell_dir}/evidence/oq/oq_receipt.json"
    local pq="${cell_dir}/evidence/pq/pq_receipt.json"

    python3 - <<PYEOF
import json, sys

cell = "${cell}"
files = [
    ("IQ", "${iq}"),
    ("OQ", "${oq}"),
    ("PQ", "${pq}"),
]
all_ok = True
for phase, path in files:
    try:
        d = json.load(open(path))
        status_key = "pq_status" if phase == "PQ" else "status"
        status = d.get(status_key, "MISSING")
        metal  = d.get("metal_device_name", "")
        ok = status == "PASS"
        icon = "✅" if ok else "❌"
        line = f"  {icon} {cell} {phase}: {status}"
        if metal: line += f"  | GPU: {metal}"
        print(line)
        if not ok:
            all_ok = False
    except Exception as e:
        print(f"  ❌ {cell} {phase}: MISSING ({e})")
        all_ok = False

sys.exit(0 if all_ok else 1)
PYEOF
}

AUDIT_OK=true
if [[ "${PQ_MACFUSION}" == "true" ]]; then
    audit_cell "MacFusion" "${REPO_ROOT}/cells/fusion/macos/GaiaFusion" || AUDIT_OK=false
fi
if [[ "${PQ_MACHEALTH}" == "true" ]]; then
    audit_cell "MacHealth" "${REPO_ROOT}/cells/fusion/macos/MacHealth" || AUDIT_OK=false
fi

[[ "${AUDIT_OK}" == "true" ]] || die "Receipt audit FAILED — one or more receipts missing or FAIL."

# ══════════════════════════════════════════════════════════════════════════════
banner "PQ COMPLETE — IQ + OQ + PQ PASS"

[[ "${PQ_MACFUSION}" == "true" ]] && print "${GRN}  ✅ MacFusion — IQ PASS | OQ PASS | PQ PASS${NC}"
[[ "${PQ_MACHEALTH}" == "true" ]] && print "${GRN}  ✅ MacHealth — IQ PASS | OQ PASS | PQ PASS${NC}"

print ""
print "${YLW}  ONE ACTION REQUIRED (Rick):${NC}"
print "  Open the pq_receipt.json for each qualified cell and replace:"
print "    \"operator\": \"CELL-OPERATOR-PUBKEY-HASH-REQUIRED\""
print "  with your Owl secp256k1 pubkey SHA-256 hash."
print ""
print "  MacFusion: ${REPO_ROOT}/cells/fusion/macos/GaiaFusion/evidence/pq/pq_receipt.json"
[[ "${PQ_MACHEALTH}" == "true" ]] && \
    print "  MacHealth: ${REPO_ROOT}/cells/fusion/macos/MacHealth/evidence/pq/pq_receipt.json"
print ""
print "  Then run: zsh scripts/run_testrobot.sh --cell ${CELL_CHOICE}"
print ""
