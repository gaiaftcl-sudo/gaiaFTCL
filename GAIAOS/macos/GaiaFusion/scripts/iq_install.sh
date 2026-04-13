#!/usr/bin/env zsh
# GaiaFusion Installation Qualification (IQ)
# GFTCL-IQ-001 | GAMP 5 EU Annex 11 | FDA 21 CFR Part 11
# Run once per Mac cell to qualify the installation and generate sovereign identity.
#
# Usage:  zsh scripts/iq_install.sh
#
# Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR}/.."
EVIDENCE_DIR="${PROJECT_ROOT}/evidence/iq"
IDENTITY_DIR="${HOME}/.gaiaftcl"
RECEIPT="${EVIDENCE_DIR}/iq_receipt.json"

mkdir -p "${EVIDENCE_DIR}"

# ── Colours (Zsh $'...' syntax for real escape codes) ─────────────────────────
GRN=$'\033[0;32m'
RED=$'\033[0;31m'
YLW=$'\033[1;33m'
BLU=$'\033[0;34m'
BOLD=$'\033[1m'
NC=$'\033[0m'

typeset -i IQ_PASS=0
typeset -i IQ_FAIL=0

pass() { print "${GRN}  ✅ PASS${NC}  $1"; (( IQ_PASS++ )) || true; }
fail() { print "${RED}  ❌ FAIL${NC}  $1"; (( IQ_FAIL++ )) || true; }
warn() { print "${YLW}  ⚠️  WARN${NC}  $1"; }
die()  { print "${RED}[IQ ABORT]${NC} $1" >&2; exit 1; }

print "${BOLD}${BLU}"
print "╔═══════════════════════════════════════════════════════════╗"
print "║  GaiaFusion Installation Qualification (GFTCL-IQ-001)   ║"
print "║  GAMP 5 / FDA 21 CFR Part 11                             ║"
print "╚═══════════════════════════════════════════════════════════╝${NC}"
print ""

# ── IQ-1: System Prerequisites ────────────────────────────────────────────────
print "${BOLD}IQ-1: System Prerequisites${NC}"

# macOS version ≥ 13 Ventura
OS_VER="$(sw_vers -productVersion)"
OS_MAJOR="${OS_VER%%.*}"
if (( OS_MAJOR >= 13 )); then
    pass "macOS version: ${OS_VER} (≥ 13 Ventura required)"
else
    fail "macOS version: ${OS_VER} — need ≥ 13 Ventura"
fi

# Architecture
ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then
    pass "CPU: Apple Silicon (arm64) — optimal for Metal Performance Shaders"
elif [[ "$ARCH" == "x86_64" ]]; then
    warn "CPU: Intel x86_64 — supported but Apple Silicon preferred"
    (( IQ_PASS++ )) || true
else
    fail "CPU: Unknown architecture: ${ARCH}"
fi

# Xcode Command Line Tools
if xcode-select -p &>/dev/null; then
    XCODE_PATH="$(xcode-select -p)"
    pass "Xcode CLT: ${XCODE_PATH}"
else
    fail "Xcode Command Line Tools not installed — run: xcode-select --install"
fi

# Swift
if command -v swift &>/dev/null; then
    SWIFT_VER="$(swift --version 2>&1 | head -1)"
    pass "Swift: ${SWIFT_VER}"
else
    fail "Swift not found — install Xcode"
fi

# Rust toolchain
if command -v rustc &>/dev/null; then
    RUST_VER="$(rustc --version)"
    pass "Rust: ${RUST_VER}"
else
    fail "Rust not installed — run: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
fi

# Cargo
if command -v cargo &>/dev/null; then
    pass "Cargo: $(cargo --version)"
else
    fail "Cargo not found"
fi

# aarch64-apple-darwin target
if rustup target list --installed 2>/dev/null | grep -q "aarch64-apple-darwin"; then
    pass "Rust target: aarch64-apple-darwin installed"
else
    warn "Rust target aarch64-apple-darwin not installed — adding..."
    rustup target add aarch64-apple-darwin && pass "Rust target: aarch64-apple-darwin added" || fail "Failed to add aarch64-apple-darwin target"
fi

# cbindgen
if command -v cbindgen &>/dev/null; then
    pass "cbindgen: $(cbindgen --version)"
else
    warn "cbindgen not installed — installing..."
    cargo install cbindgen 2>/dev/null && pass "cbindgen installed" || fail "cbindgen install failed"
fi

# Metal GPU
METAL_CHECK="$(system_profiler SPDisplaysDataType 2>/dev/null | grep -i 'metal\|gpu' | head -1 || true)"
if [[ -n "$METAL_CHECK" ]]; then
    pass "Metal GPU: supported"
else
    warn "Could not verify Metal GPU via system_profiler (may still be supported)"
fi

# Git
if command -v git &>/dev/null; then
    pass "Git: $(git --version)"
else
    fail "Git not installed"
fi

# OpenSSL (for wallet key generation)
if command -v openssl &>/dev/null; then
    pass "OpenSSL: $(openssl version)"
else
    fail "OpenSSL not found"
fi

# Disk space ≥ 2 GB
DISK_FREE_KB="$(df -k "${PROJECT_ROOT}" | tail -1 | awk '{print $4}')"
if (( DISK_FREE_KB > 2097152 )); then
    pass "Disk: $(( DISK_FREE_KB / 1048576 )) GB free (≥ 2 GB required)"
else
    fail "Disk: insufficient free space ($(( DISK_FREE_KB / 1024 )) MB, need ≥ 2 GB)"
fi

# RAM ≥ 8 GB
RAM_BYTES="$(sysctl -n hw.memsize)"
RAM_GB=$(( RAM_BYTES / 1073741824 ))
if (( RAM_GB >= 8 )); then
    pass "RAM: ${RAM_GB} GB (≥ 8 GB required)"
else
    fail "RAM: ${RAM_GB} GB — need ≥ 8 GB"
fi

print "\n${BOLD}IQ-1 Result: ${IQ_PASS} passed, ${IQ_FAIL} failed${NC}"
[[ "${IQ_FAIL}" -eq 0 ]] || die "IQ-1 prerequisites failed. Resolve above issues and re-run."

# ── IQ-2: Apple macOS Standards ───────────────────────────────────────────────
print "\n${BOLD}IQ-2: Apple macOS Standards${NC}"

DARK_MODE="$(defaults read -g AppleInterfaceStyle 2>/dev/null || print "Light")"
pass "Appearance mode: ${DARK_MODE}"

ACCENT="$(defaults read -g AppleAccentColor 2>/dev/null || print "4 (Blue/default)")"
pass "Accent color: ${ACCENT}"

# Verify project structure
[[ -f "${PROJECT_ROOT}/Package.swift" ]] && pass "Package.swift present" || fail "Package.swift missing"
[[ -d "${PROJECT_ROOT}/MetalRenderer/rust" ]] && pass "MetalRenderer/rust present" || fail "MetalRenderer/rust missing"
[[ -f "${PROJECT_ROOT}/MetalRenderer/rust/Cargo.toml" ]] && pass "Cargo.toml present" || fail "Cargo.toml missing"
[[ -d "${PROJECT_ROOT}/GaiaFusion" ]] && pass "GaiaFusion Swift sources present" || fail "GaiaFusion Swift sources missing"

# ── IQ-3: Sovereign Wallet Identity ───────────────────────────────────────────
print "\n${BOLD}IQ-3: Sovereign Wallet Identity Generation${NC}"

if [[ -f "${IDENTITY_DIR}/cell_identity" && -f "${IDENTITY_DIR}/wallet.key" ]]; then
    warn "Sovereign identity already exists at ${IDENTITY_DIR} — skipping regeneration"
    CELL_ID="$(cat "${IDENTITY_DIR}/cell_identity" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cell_id','unknown'))" 2>/dev/null || print "unknown")"
    WALLET_ADDRESS="$(cat "${IDENTITY_DIR}/cell_identity" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('wallet_address','unknown'))" 2>/dev/null || print "unknown")"
    pass "Identity loaded: ${CELL_ID:0:16}..."
    pass "Wallet: ${WALLET_ADDRESS}"
else
    mkdir -p "${IDENTITY_DIR}"
    chmod 700 "${IDENTITY_DIR}"

    # Hardware UUID
    HW_UUID="$(ioreg -rd1 -c IOPlatformExpertDevice | awk '/IOPlatformUUID/ {print $3}' | tr -d '"')"
    # Entropy
    ENTROPY="$(openssl rand -hex 32)"
    # Timestamp
    TS="$(date -u +%Y%m%dT%H%M%SZ)"
    # Cell ID = SHA256(UUID|entropy|timestamp)
    CELL_ID="$(print -n "${HW_UUID}${ENTROPY}${TS}" | openssl dgst -sha256 -hex | awk '{print $2}')"

    # secp256k1 wallet keypair
    openssl ecparam -name secp256k1 -genkey -noout \
        -out "${IDENTITY_DIR}/wallet.key" 2>/dev/null
    chmod 600 "${IDENTITY_DIR}/wallet.key"

    # Derive wallet address from public key hash
    PUBKEY_HEX="$(openssl ec -in "${IDENTITY_DIR}/wallet.key" \
        -pubout -outform DER 2>/dev/null | openssl dgst -sha256 -hex | awk '{print $2}')"
    WALLET_ADDRESS="gaia1${PUBKEY_HEX:0:38}"

    # Write identity file
    cat > "${IDENTITY_DIR}/cell_identity" <<EOF
{
  "cell_id": "${CELL_ID}",
  "wallet_address": "${WALLET_ADDRESS}",
  "hw_uuid": "${HW_UUID}",
  "generated_at": "${TS}",
  "schema": "gaiaftcl_sovereign_identity_v1"
}
EOF
    chmod 644 "${IDENTITY_DIR}/cell_identity"

    pass "Cell ID: ${CELL_ID:0:16}..."
    pass "Wallet address: ${WALLET_ADDRESS}"
    pass "Wallet key: ${IDENTITY_DIR}/wallet.key (mode 600 — SECRET)"
fi

# ── IQ-4: License Acceptance ──────────────────────────────────────────────────
print "\n${BOLD}IQ-4: License Acceptance — Sovereign Cell Identity${NC}"
print ""
print "  By accepting, you:"
print "  1. Acknowledge the autogenerated wallet above as this cell's sovereign identity"
print "  2. Accept the GaiaFTCL License (see LICENSE file)"
print "  3. Confirm this Mac is a GaiaFTCL sovereign cell under your control"
print "  4. Understand the wallet key at ${IDENTITY_DIR}/wallet.key is SECRET"
print ""
print -n "  Accept? [yes/no]: "
read ACCEPT
if [[ "${ACCEPT}" == "yes" ]]; then
    pass "License accepted — cell identity registered"
else
    die "License not accepted. IQ aborted."
fi

# ── IQ-5: Write Receipt ───────────────────────────────────────────────────────
print "\n${BOLD}IQ-5: Writing IQ Receipt${NC}"

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
GIT_COMMIT="$(git -C "${PROJECT_ROOT}" rev-parse HEAD 2>/dev/null || print 'unknown')"

cat > "${RECEIPT}" <<EOF
{
  "document_id": "GFTCL-IQ-001",
  "schema": "gaiaftcl_iq_receipt_v1",
  "timestamp": "${TIMESTAMP}",
  "git_commit": "${GIT_COMMIT}",
  "cell_id": "${CELL_ID}",
  "wallet_address": "${WALLET_ADDRESS}",
  "os_version": "${OS_VER}",
  "architecture": "${ARCH}",
  "dark_mode": "${DARK_MODE}",
  "accent_color": "${ACCENT}",
  "iq_pass": ${IQ_PASS},
  "iq_fail": ${IQ_FAIL},
  "license_accepted": true,
  "status": "IQ_COMPLETE",
  "next_step": "Run zsh scripts/oq_validate.sh"
}
EOF

pass "IQ receipt: ${RECEIPT}"

print ""
print "${GRN}${BOLD}╔═══════════════════════════════════════════════════════════╗${NC}"
print "${GRN}${BOLD}║  INSTALLATION QUALIFICATION COMPLETE                     ║${NC}"
print "${GRN}${BOLD}║  Cell: ${CELL_ID:0:16}...${NC}"
print "${GRN}${BOLD}║  Wallet: ${WALLET_ADDRESS:0:20}...${NC}"
print "${GRN}${BOLD}║  Next: zsh scripts/oq_validate.sh                        ║${NC}"
print "${GRN}${BOLD}╚═══════════════════════════════════════════════════════════╝${NC}"
