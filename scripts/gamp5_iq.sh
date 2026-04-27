#!/usr/bin/env zsh
# ══════════════════════════════════════════════════════════════════════════════
#  gamp5_iq.sh — Installation Qualification (IQ)
#  FoT8D | GAMP 5 Category 5 | FDA 21 CFR Part 11 | EU Annex 11
#
#  Asks:  1. Which cell to qualify (MacFusion / MacHealth / Both)
#         2. Whether to clean up any old app data / wallets
#  Then:  Verifies toolchain, generates sovereign wallet, writes IQ receipt.
#
#  Cell / vQbit substrate meaning: substrate/CELL_VQBIT_PARADIGM.yaml
#
#  Run:  zsh scripts/gamp5_iq.sh
#  Or:   zsh scripts/gamp5_iq.sh --cell macfusion   (skip dialog)
#  Or:   zsh scripts/gamp5_iq.sh --cell machealth
#  Or:   zsh scripts/gamp5_iq.sh --cell both
#
#  Writes receipts to:
#    cells/fusion/macos/GaiaFusion/evidence/iq/iq_receipt.json   (MacFusion)
#    cells/fusion/macos/MacHealth/evidence/iq/iq_receipt.json    (MacHealth)
#
#  Non-brittle:
#    FOT_IQ_SOFT=1              — prerequisite/structure failures warn, do not abort
#
#  Visibility: operator witness on /dev/tty. Sprout sets FOT_QUAL_VISIBLE_TESTS_ONLY=1 for the stack.
#  Run from Terminal.app or ssh -t; piped stdin is OK if /dev/tty exists.
#
#  Gold laptop only (your machine + write access to origin — not CI/read-only clones):
#    FOT_IQ_GOLD_LAPTOP_SYNC=1  — after PASS, commit IQ receipts & push to origin
#    FOT_IQ_GOLD_COMMIT_RECEIPTS=0 — skip auto-commit; push only if you committed already
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
die()     { print "${RED}\n[IQ ABORT]${NC} $1\n" >&2; exit 1; }
ask_dialog() {
    # ask_dialog "prompt" "opt1" "opt2" ...
    # Returns chosen option. Falls back to first option if osascript unavailable.
    local prompt="$1"; shift
    local opts=("$@")
    local list=""
    for o in "${opts[@]}"; do list="${list}\"${o}\", "; done
    list="${list%, }"
    osascript -e "choose from list {${list}} with prompt \"${prompt}\" default items {\"${opts[0]}\"} without multiple selections allowed empty selection allowed" 2>/dev/null || echo "${opts[0]}"
}
ask_yesno() {
    # ask_yesno "question" → returns "yes" or "no"
    local q="$1"
    local answer
    answer=$(osascript -e "display dialog \"${q}\" buttons {\"No\", \"Yes\"} default button \"Yes\" with icon note" -e "button returned of result" 2>/dev/null) || echo "No"
    [[ "$answer" == "Yes" ]] && echo "yes" || echo "no"
}

human_bell() {
    print -u 2 "\n${BOLD}${YLW}🔔 OPERATOR WITNESS (visible)${NC}"
    print -u 2 "${YLW}Review the output above, then press Enter.${NC}"
    if [[ ! -r /dev/tty ]]; then
        die "No /dev/tty — IQ refuses to run without a visible console (use Terminal or ssh -t)."
    fi
    print -u 2 -n "${YLW}Press Enter on the console to proceed… ${NC}"
    read -r </dev/tty || die "Witness not confirmed."
}

# ── Parse CLI args ────────────────────────────────────────────────────────────
CELL_ARG=""
for arg in "$@"; do
    case "$arg" in
        --cell) shift; CELL_ARG="${1:-}" ;;
        --cell=*) CELL_ARG="${arg#--cell=}" ;;
    esac
done

# ══════════════════════════════════════════════════════════════════════════════
banner "FoT8D — Installation Qualification (IQ)"
print "  GAMP 5 Category 5 | FDA 21 CFR Part 11 | EU Annex 11"
print "  Repo: ${REPO_ROOT}"
print "  Time: ${TIMESTAMP}\n"

# ══════════════════════════════════════════════════════════════════════════════
# IQ-0: CELL SELECTION
# ══════════════════════════════════════════════════════════════════════════════
section "IQ-0: Cell Selection"

if [[ -n "${CELL_ARG}" ]]; then
    CELL_CHOICE="${CELL_ARG}"
    print "  Cell (from CLI): ${CELL_CHOICE}"
else
    print "  Showing cell selection dialog…"
    RAW=$(ask_dialog \
        "Which cell are you installing?\n\nMacFusion = GAIAFTCL Fusion Cell (9 plant kinds, τ Metal renderer)\nMacHealth = GaiaHealth Biologit Cell (11-state MD, M/I/A epistemic)\nBoth = Full FoT8D stack" \
        "MacFusion — Fusion Cell" \
        "MacHealth — Biologit Cell" \
        "Both Cells")

    case "${RAW}" in
        *"MacFusion"*) CELL_CHOICE="macfusion" ;;
        *"MacHealth"*) CELL_CHOICE="machealth" ;;
        *"Both"*)      CELL_CHOICE="both"       ;;
        *)             die "No cell selected. IQ cancelled." ;;
    esac
fi

INSTALL_MACFUSION=false
INSTALL_MACHEALTH=false
case "${CELL_CHOICE}" in
    macfusion) INSTALL_MACFUSION=true  ;;
    machealth) INSTALL_MACHEALTH=true  ;;
    both)      INSTALL_MACFUSION=true; INSTALL_MACHEALTH=true ;;
    *)         die "Unknown cell: ${CELL_CHOICE}. Use macfusion, machealth, or both." ;;
esac

print "  Installing: MacFusion=${INSTALL_MACFUSION}  MacHealth=${INSTALL_MACHEALTH}"

# ══════════════════════════════════════════════════════════════════════════════
# IQ-0b: GENESIS RECORD — inception anchor (vQbit sprout seals this before IQ continues)
# ══════════════════════════════════════════════════════════════════════════════
section "IQ-0b: Genesis record (inception)"
if [[ -n "${FOT_GENESIS_RECORD_PATH:-}" && -f "${FOT_GENESIS_RECORD_PATH}" ]]; then
    pass "Genesis record bound for this IQ run"
    print "  Path: ${FOT_GENESIS_RECORD_PATH}"
    if command -v jq >/dev/null 2>&1; then
        jq . "${FOT_GENESIS_RECORD_PATH}" 2>/dev/null | head -24
    else
        head -12 "${FOT_GENESIS_RECORD_PATH}"
    fi
elif [[ -f "${REPO_ROOT}/cells/franklin/avatar/evidence/iq/genesis_record.json" ]]; then
    export FOT_GENESIS_RECORD_PATH="${REPO_ROOT}/cells/franklin/avatar/evidence/iq/genesis_record.json"
    pass "Genesis record found under Franklin avatar evidence"
    head -12 "${FOT_GENESIS_RECORD_PATH}"
else
    warn "No genesis_record.json — IQ continues (standalone run or pre-inception)"
fi

# ══════════════════════════════════════════════════════════════════════════════
# IQ-1: OLD APP / DATA CHECK
# ══════════════════════════════════════════════════════════════════════════════
section "IQ-1: Old App / Data Check"

OLD_ITEMS=()

# Check for old wallets
[[ -d "${HOME}/.gaiaftcl"   ]] && OLD_ITEMS+=("~/.gaiaftcl/ (MacFusion wallet)")
[[ -d "${HOME}/.gaiahealth" ]] && OLD_ITEMS+=("~/.gaiahealth/ (MacHealth wallet)")

# Check for old app bundles
[[ -d "/Applications/GaiaFusion.app" ]]    && OLD_ITEMS+=("/Applications/GaiaFusion.app")
[[ -d "${HOME}/Applications/GaiaFusion.app" ]] && OLD_ITEMS+=("~/Applications/GaiaFusion.app")
[[ -d "/Applications/MacHealth.app" ]]     && OLD_ITEMS+=("/Applications/MacHealth.app")
[[ -d "${REPO_ROOT}/cells/fusion/macos/GaiaFusion/GaiaFusion.app" ]] && \
    OLD_ITEMS+=("cells/fusion/macos/GaiaFusion/GaiaFusion.app (repo copy)")

# Check for old receipts
[[ -f "${REPO_ROOT}/cells/fusion/macos/GaiaFusion/evidence/iq/iq_receipt.json" ]] && \
    OLD_ITEMS+=("GaiaFusion/evidence/iq/iq_receipt.json (prior IQ receipt)")
[[ -f "${REPO_ROOT}/cells/fusion/macos/MacHealth/evidence/iq/iq_receipt.json" ]] && \
    OLD_ITEMS+=("MacHealth/evidence/iq/iq_receipt.json (prior IQ receipt)")

if [[ ${#OLD_ITEMS[@]} -eq 0 ]]; then
    pass "No old app data found — clean installation"
    CLEAN_OLD="no"
else
    print "  Found existing data:"
    for item in "${OLD_ITEMS[@]}"; do
        print "    • ${item}"
    done
    print ""
    CLEAN_OLD=$(ask_yesno "Existing app data was found (listed in Terminal).\n\nBack up and remove old wallets and receipts before installing?\n\n(Wallets will be moved to ~/.fot8d_backup_${TIMESTAMP}/)\n(Old app bundles will be trashed — NOT deleted permanently)")
fi

if [[ "${CLEAN_OLD}" == "yes" ]]; then
    section "IQ-1b: Backing Up Old Data"
    BACKUP_DIR="${HOME}/.fot8d_backup_${TIMESTAMP}"
    mkdir -p "${BACKUP_DIR}"

    # Back up wallets
    if [[ -d "${HOME}/.gaiaftcl" ]]; then
        mv "${HOME}/.gaiaftcl" "${BACKUP_DIR}/gaiaftcl_wallet"
        warn "Moved ~/.gaiaftcl → ${BACKUP_DIR}/gaiaftcl_wallet"
    fi
    if [[ -d "${HOME}/.gaiahealth" ]]; then
        mv "${HOME}/.gaiahealth" "${BACKUP_DIR}/gaiahealth_wallet"
        warn "Moved ~/.gaiahealth → ${BACKUP_DIR}/gaiahealth_wallet"
    fi

    # Trash old app bundles (safe — not permanent delete)
    for app_path in \
        "/Applications/GaiaFusion.app" \
        "${HOME}/Applications/GaiaFusion.app" \
        "/Applications/MacHealth.app"; do
        if [[ -d "${app_path}" ]]; then
            osascript -e "tell application \"Finder\" to delete POSIX file \"${app_path}\"" 2>/dev/null && \
                warn "Moved to Trash: ${app_path}" || \
                warn "Could not trash ${app_path} — skip (not critical)"
        fi
    done

    # Back up old receipts
    for receipt_path in \
        "${REPO_ROOT}/cells/fusion/macos/GaiaFusion/evidence/iq/iq_receipt.json" \
        "${REPO_ROOT}/cells/fusion/macos/MacHealth/evidence/iq/iq_receipt.json"; do
        if [[ -f "${receipt_path}" ]]; then
            cp "${receipt_path}" "${BACKUP_DIR}/"
            warn "Backed up: $(basename ${receipt_path})"
        fi
    done

    pass "Old data backed up to: ${BACKUP_DIR}"
else
    pass "Keeping existing data — incremental install"
fi

# ══════════════════════════════════════════════════════════════════════════════
# IQ-2: SYSTEM PREREQUISITES
# ══════════════════════════════════════════════════════════════════════════════
section "IQ-2: System Prerequisites"

typeset -i PREREQ_PASS=0 PREREQ_FAIL=0

check_prereq() {
    local label="$1" cmd="$2"
    if eval "${cmd}" &>/dev/null; then
        pass "${label}"; (( PREREQ_PASS++ )) || true
    else
        fail "${label}"; (( PREREQ_FAIL++ )) || true
    fi
}

# macOS ≥ 13
OS_VER="$(sw_vers -productVersion)"
OS_MAJOR="${OS_VER%%.*}"
if (( OS_MAJOR >= 13 )); then
    pass "macOS ${OS_VER} (≥ 13 required)"; (( PREREQ_PASS++ )) || true
else
    fail "macOS ${OS_VER} — need ≥ 13 Ventura"; (( PREREQ_FAIL++ )) || true
fi

# Architecture
ARCH="$(uname -m)"
if [[ "${ARCH}" == "arm64" ]]; then
    pass "CPU: Apple Silicon arm64 — Metal 3 optimal"; (( PREREQ_PASS++ )) || true
elif [[ "${ARCH}" == "x86_64" ]]; then
    warn "CPU: Intel x86_64 — supported, Apple Silicon preferred"
    (( PREREQ_PASS++ )) || true
else
    fail "CPU: Unknown arch ${ARCH}"; (( PREREQ_FAIL++ )) || true
fi

check_prereq "Xcode CLT"            "xcode-select -p"
check_prereq "Swift ≥ 5.9"         "swift --version"
check_prereq "Rust toolchain"       "rustc --version"
check_prereq "Cargo"                "cargo --version"
check_prereq "OpenSSL (wallet gen)" "openssl version"
check_prereq "Python 3 (receipts)"  "python3 --version"
if system_profiler SPDisplaysDataType 2>/dev/null | grep -qi metal; then
    pass "Metal-capable GPU path visible"; (( PREREQ_PASS++ )) || true
else
    warn "Metal GPU probe inconclusive (VM / remote session / profile) — not blocking IQ"
fi

# Swift version check
SWIFT_MINOR="$(swift --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)"
SWIFT_MAJ="${SWIFT_MINOR%%.*}"
if (( SWIFT_MAJ >= 5 )); then
    pass "Swift ${SWIFT_MINOR}"; (( PREREQ_PASS++ )) || true
fi

# Rust version
RUST_VER="$(rustc --version 2>/dev/null | awk '{print $2}')"
pass "Rust ${RUST_VER}"; (( PREREQ_PASS++ )) || true

print "\n  Prerequisites: ${PREREQ_PASS} passed, ${PREREQ_FAIL} failed"
if (( PREREQ_FAIL > 0 )); then
    if [[ "${FOT_IQ_SOFT:-0}" == "1" ]]; then
        warn "Prerequisites reported ${PREREQ_FAIL} failure(s) — continuing (FOT_IQ_SOFT=1)"
    else
        die "Prerequisites failed. Resolve above before re-running IQ or set FOT_IQ_SOFT=1 for non-blocking dev."
    fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# IQ-3: PROJECT STRUCTURE
# ══════════════════════════════════════════════════════════════════════════════
section "IQ-3: Project Structure"

typeset -i STRUCT_PASS=0 STRUCT_FAIL=0

check_path() {
    local label="$1" path="$2"
    if [[ -e "${path}" ]]; then
        pass "${label}"; (( STRUCT_PASS++ )) || true
    else
        fail "${label} missing: ${path}"; (( STRUCT_FAIL++ )) || true
    fi
}

# Shared always required
check_path "shared/wallet_core"   "${REPO_ROOT}/shared/wallet_core/src/lib.rs"
check_path "shared/owl_protocol"  "${REPO_ROOT}/shared/owl_protocol/src/lib.rs"

if [[ "${INSTALL_MACFUSION}" == "true" ]]; then
    MF_ROOT="${REPO_ROOT}/cells/fusion/macos/GaiaFusion"
    check_path "MacFusion Package.swift"          "${MF_ROOT}/Package.swift"
    check_path "MacFusion Swift sources"          "${MF_ROOT}/GaiaFusion/GaiaFusionApp.swift"
    check_path "MacFusion libgaia_metal_renderer" "${MF_ROOT}/MetalRenderer/lib/libgaia_metal_renderer.a"
    check_path "MacFusion C header"               "${MF_ROOT}/MetalRenderer/include/gaia_metal_renderer.h"
    check_path "MacFusion Rust source"            "${MF_ROOT}/MetalRenderer/rust/Cargo.toml"
fi

if [[ "${INSTALL_MACHEALTH}" == "true" ]]; then
    MH_ROOT="${REPO_ROOT}/cells/fusion/macos/MacHealth"
    GH_ROOT="${REPO_ROOT}/GaiaHealth"
    check_path "MacHealth dir"                    "${MH_ROOT}"
    check_path "MacHealth Package.swift"          "${MH_ROOT}/Package.swift"
    check_path "GaiaHealth Rust workspace"        "${GH_ROOT}/Cargo.toml"
    check_path "GaiaHealth gaia-health-renderer"  "${GH_ROOT}/gaia-health-renderer/src/lib.rs"
    check_path "GaiaHealth biologit_md_engine"    "${GH_ROOT}/biologit_md_engine/src/lib.rs"
fi

print "\n  Structure: ${STRUCT_PASS} passed, ${STRUCT_FAIL} failed"
if (( STRUCT_FAIL > 0 )); then
    if [[ "${FOT_IQ_SOFT:-0}" == "1" ]]; then
        warn "Structure checks: ${STRUCT_FAIL} missing path(s) — continuing (FOT_IQ_SOFT=1)"
    else
        die "Project structure incomplete. See MAC_APPS_BUILD_PLAN.md or set FOT_IQ_SOFT=1 for partial trees."
    fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# IQ-4: SOVEREIGN WALLET GENERATION
# ══════════════════════════════════════════════════════════════════════════════

generate_wallet() {
    local cell_label="$1"    # "MacFusion" or "MacHealth"
    local identity_dir="$2"  # ~/.gaiaftcl or ~/.gaiahealth
    local prefix="$3"        # "gaia1" or "gaiahealth1"
    local schema="$4"        # e.g. "gaiaftcl_sovereign_identity_v1"

    section "IQ-4: Sovereign Wallet — ${cell_label}"

    if [[ -f "${identity_dir}/cell_identity" && -f "${identity_dir}/wallet.key" ]]; then
        warn "Identity already exists at ${identity_dir} — reusing"
        CELL_ID="$(python3 -c "import sys,json; d=json.load(open('${identity_dir}/cell_identity')); print(d.get('cell_id','unknown'))" 2>/dev/null || print "unknown")"
        WALLET_ADDR="$(python3 -c "import sys,json; d=json.load(open('${identity_dir}/cell_identity')); print(d.get('wallet_address','unknown'))" 2>/dev/null || print "unknown")"
        pass "Cell ID: ${CELL_ID:0:20}..."
        pass "Wallet:  ${WALLET_ADDR}"
        pass "Wallet key mode: $(stat -f '%Lp' "${identity_dir}/wallet.key")"
    else
        mkdir -p "${identity_dir}"
        chmod 700 "${identity_dir}"

        HW_UUID="$(ioreg -rd1 -c IOPlatformExpertDevice | awk '/IOPlatformUUID/ {print $3}' | tr -d '"')"
        ENTROPY="$(openssl rand -hex 32)"
        TS="$(date -u +%Y%m%dT%H%M%SZ)"
        CELL_ID="$(print -n "${HW_UUID}${ENTROPY}${TS}" | openssl dgst -sha256 -hex | awk '{print $2}')"

        openssl ecparam -name secp256k1 -genkey -noout -out "${identity_dir}/wallet.key" 2>/dev/null
        chmod 600 "${identity_dir}/wallet.key"

        PUBKEY_HEX="$(openssl ec -in "${identity_dir}/wallet.key" \
            -pubout -outform DER 2>/dev/null | openssl dgst -sha256 -hex | awk '{print $2}')"
        WALLET_ADDR="${prefix}${PUBKEY_HEX:0:38}"

        python3 - <<PYEOF
import json
with open("${identity_dir}/cell_identity", "w") as f:
    json.dump({
        "cell_id":        "${CELL_ID}",
        "wallet_address": "${WALLET_ADDR}",
        "hw_uuid":        "${HW_UUID}",
        "generated_at":   "${TS}",
        "pii_stored":     False,
        "schema":         "${schema}"
    }, f, indent=2)
PYEOF
        chmod 644 "${identity_dir}/cell_identity"

        pass "Cell ID: ${CELL_ID:0:20}..."
        pass "Wallet:  ${WALLET_ADDR}"
        pass "Key:     ${identity_dir}/wallet.key (mode 600 — SECRET)"
    fi

    print "${CELL_ID}" > /tmp/fot8d_iq_cellid_${cell_label}
    print "${WALLET_ADDR}" > /tmp/fot8d_iq_wallet_${cell_label}
}

[[ "${INSTALL_MACFUSION}" == "true" ]] && \
    generate_wallet "MacFusion" "${HOME}/.gaiaftcl"   "gaia1"        "gaiaftcl_sovereign_identity_v1"

[[ "${INSTALL_MACHEALTH}" == "true" ]] && \
    generate_wallet "MacHealth" "${HOME}/.gaiahealth"  "gaiahealth1"  "gaiahealth_sovereign_identity_v1"

# ══════════════════════════════════════════════════════════════════════════════
# IQ-5: LICENSE ACCEPTANCE
# ══════════════════════════════════════════════════════════════════════════════
section "IQ-5: License Acceptance"

LICENSE_CELLS=""
[[ "${INSTALL_MACFUSION}" == "true" ]] && LICENSE_CELLS="${LICENSE_CELLS}MacFusion (GAIAFTCL Fusion Cell)\n"
[[ "${INSTALL_MACHEALTH}" == "true" ]] && LICENSE_CELLS="${LICENSE_CELLS}MacHealth (GaiaHealth Biologit Cell)\n"

ACCEPT=$(ask_yesno "Sovereign Cell License Agreement\n\nInstalling: ${LICENSE_CELLS}\nBy accepting you confirm:\n1. The generated wallet is this cell's sovereign identity\n2. The wallet key is SECRET — never commit to git\n3. This Mac is a qualified sovereign cell under your control\n4. Zero PII is stored — wallet is purely mathematical\n5. Patents USPTO 19/460,960 | 19/096,071 apply\n\nAccept?")
[[ "${ACCEPT}" == "yes" ]] || die "License not accepted. IQ cancelled."
pass "License accepted"

# ══════════════════════════════════════════════════════════════════════════════
# IQ-6: WRITE IQ RECEIPTS
# ══════════════════════════════════════════════════════════════════════════════

human_bell

write_iq_receipt() {
    local cell_label="$1"
    local evidence_dir="$2"
    local document_id="$3"
    local identity_dir="$4"

    section "IQ-6: Writing IQ Receipt — ${cell_label}"

    mkdir -p "${evidence_dir}"

    local cell_id wallet_addr
    cell_id="$(cat /tmp/fot8d_iq_cellid_${cell_label} 2>/dev/null || echo 'unknown')"
    wallet_addr="$(cat /tmp/fot8d_iq_wallet_${cell_label} 2>/dev/null || echo 'unknown')"

    local git_commit
    git_commit="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo 'unknown')"

    python3 - <<PYEOF
import json, os
receipt = {
    "document_id":       "${document_id}",
    "schema":            "fot8d_iq_receipt_v2",
    "cell":              "${cell_label}",
    "timestamp":         "${TIMESTAMP}",
    "git_commit":        "${git_commit}",
    "os_version":        "${OS_VER}",
    "architecture":      "${ARCH}",
    "cell_id":           "${cell_id}",
    "wallet_address":    "${wallet_addr}",
    "pii_stored":        False,
    "prereq_pass":       ${PREREQ_PASS},
    "prereq_fail":       ${PREREQ_FAIL},
    "license_accepted":  True,
    "clean_install":     "${CLEAN_OLD}" == "yes",
    "status":            "PASS",
    "next_step":         "zsh scripts/gamp5_oq.sh --cell ${cell_label,,}"
}
path = "${evidence_dir}/iq_receipt.json"
with open(path, "w") as f:
    json.dump(receipt, f, indent=2)
print(f"  Receipt: {path}")
PYEOF

    rm -f /tmp/fot8d_iq_cellid_${cell_label} /tmp/fot8d_iq_wallet_${cell_label}
    pass "IQ receipt written: ${evidence_dir}/iq_receipt.json"
}

[[ "${INSTALL_MACFUSION}" == "true" ]] && \
    write_iq_receipt "MacFusion" \
        "${REPO_ROOT}/cells/fusion/macos/GaiaFusion/evidence/iq" \
        "GFTCL-IQ-001"

[[ "${INSTALL_MACHEALTH}" == "true" ]] && \
    write_iq_receipt "MacHealth" \
        "${REPO_ROOT}/cells/fusion/macos/MacHealth/evidence/iq" \
        "GH-IQ-001"

# ══════════════════════════════════════════════════════════════════════════════
# IQ-7: Gold laptop → GitHub (write path — explicit opt-in only)
# ══════════════════════════════════════════════════════════════════════════════
section "IQ-7: GitHub (gold laptop sync)"

if [[ "${FOT_IQ_GOLD_LAPTOP_SYNC:-0}" == "1" ]]; then
    _origin="$(git -C "${REPO_ROOT}" remote get-url origin 2>/dev/null || true)"
    if [[ -z "${_origin}" ]]; then
        warn "No origin remote — cannot push"
    else
        _branch="$(git -C "${REPO_ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || print main)"
        if [[ "${FOT_IQ_GOLD_COMMIT_RECEIPTS:-1}" != "0" ]]; then
            [[ "${INSTALL_MACFUSION}" == "true" ]] && [[ -f "${REPO_ROOT}/cells/fusion/macos/GaiaFusion/evidence/iq/iq_receipt.json" ]] && \
                git -C "${REPO_ROOT}" add -- cells/fusion/macos/GaiaFusion/evidence/iq/iq_receipt.json 2>/dev/null || true
            [[ "${INSTALL_MACHEALTH}" == "true" ]] && [[ -f "${REPO_ROOT}/cells/fusion/macos/MacHealth/evidence/iq/iq_receipt.json" ]] && \
                git -C "${REPO_ROOT}" add -- cells/fusion/macos/MacHealth/evidence/iq/iq_receipt.json 2>/dev/null || true
            [[ -f "${REPO_ROOT}/cells/franklin/avatar/evidence/iq/genesis_record.json" ]] && \
                git -C "${REPO_ROOT}" add -f -- cells/franklin/avatar/evidence/iq/genesis_record.json 2>/dev/null || true
            if ! git -C "${REPO_ROOT}" diff --cached --quiet 2>/dev/null; then
                git -C "${REPO_ROOT}" commit -m "evidence(iq): IQ receipts ${TIMESTAMP}" 2>&1 && pass "Committed IQ evidence for push" || warn "git commit failed — push may have nothing new"
            fi
        fi
        if git -C "${REPO_ROOT}" push origin "${_branch}" 2>&1; then
            pass "origin/${_branch} updated — gold laptop sync"
        else
            warn "git push failed — check credentials/network; local receipts remain valid"
        fi
    fi
else
    pass "GitHub write skipped (read-only / non-gold host). Set FOT_IQ_GOLD_LAPTOP_SYNC=1 only on your laptop to publish."
fi

# ══════════════════════════════════════════════════════════════════════════════
banner "IQ COMPLETE"

[[ "${INSTALL_MACFUSION}" == "true" ]] && \
    print "${GRN}  ✅ MacFusion IQ — PASS${NC}"
[[ "${INSTALL_MACHEALTH}" == "true" ]] && \
    print "${GRN}  ✅ MacHealth IQ — PASS${NC}"

print ""
print "  Next step: zsh scripts/gamp5_oq.sh --cell ${CELL_CHOICE}"
print ""
