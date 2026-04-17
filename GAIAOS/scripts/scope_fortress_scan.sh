#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# scope_fortress_scan.sh — Compliance scanner for REFUSED gates
# Authority: .cursor/rules/scope-fortress-gates.mdc
# Run: bash scripts/scope_fortress_scan.sh
# Exit 0 = clean, Exit 1 = violation(s)
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
RST='\033[0m'

VIOLATIONS=0
SCAN_ROOT="${GAIA_ROOT:-.}"
SCAN_ROOT="$(cd "$SCAN_ROOT" && pwd)"

# Prefer ripgrep: recursive grep on apps/ can take 10s+ per pattern (node_modules trees);
# rg respects .gitignore and is typically sub-second for the same scope.
USE_RG=0
if command -v rg >/dev/null 2>&1; then
    USE_RG=1
fi

header() { echo -e "\n${YLW}═══ $1 ═══${RST}"; }
pass()   { echo -e "  ${GRN}✓${RST} $1"; }
fail()   { echo -e "  ${RED}✗ REFUSED${RST} $1"; VIOLATIONS=$((VIOLATIONS + 1)); }

# ─── GATE 1 — Passkey / custody (code only; alternation = separate patterns or grep -E) ───
header "GATE 1: PASSKEY / KEY CUSTODY"

G1_START=$VIOLATIONS

# Each pattern tested with grep -E (extended regex) where | is used
GATE1_ERE_PATTERNS=(
    'navigator\.credentials\.(create|get)'
    'PublicKeyCredential'
    'crypto\.subtle\.(generateKey|exportKey)'
    'generateKeyPair'
    'WebAuthn|webauthn'
    'passkey|PasskeyRegistration'
    'createEmbeddedWallet'
    'mnemonic.*seed'
)

GATE1_FIXED=(
    'BIP39'
    'bip39'
)

GATE1_EXCLUDE='node_modules/|\.git/|vendor/|dist/|build/|/evidence/|scope_fortress_scan\.sh|scope-fortress-gates\.mdc|SKILL\.md|\.plan\.md'

# Targeted trees only (full services/ is too large for interactive grep).
GATE1_SCAN_DIRS=(
  scripts macos deploy apps tools
  services/gaiaos_ui_web/app
  services/wallet_signer
  services/wallet_observer
  services/fot_mcp_gateway
  services/fusion_control_mac
)

# GATE 1: one ripgrep pass per pattern over all dirs (fast); else per-dir grep.
scan_ere() {
    local pattern="$1"
    if [ "$USE_RG" -eq 1 ]; then
        local roots=()
        local d
        for d in "${GATE1_SCAN_DIRS[@]}"; do
            [ -d "$SCAN_ROOT/$d" ] && roots+=("$SCAN_ROOT/$d")
        done
        [ "${#roots[@]}" -eq 0 ] && return 0
        rg -n -S --no-heading -e "$pattern" "${roots[@]}" \
            -g '*.ts' -g '*.tsx' -g '*.js' -g '*.jsx' -g '*.swift' -g '*.py' -g '*.sh' -g '*.md' \
            2>/dev/null | grep -vE "$GATE1_EXCLUDE" || true
        return 0
    fi
    local d
    for d in "${GATE1_SCAN_DIRS[@]}"; do
        [ -d "$SCAN_ROOT/$d" ] || continue
        case "$d" in
            services/fusion_control_mac)
                grep -rEn --include='*.swift' --include='*.md' "$pattern" "$SCAN_ROOT/$d" 2>/dev/null || true
                ;;
            *)
                grep -rEn --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' \
                    --include='*.swift' --include='*.py' --include='*.sh' \
                    "$pattern" "$SCAN_ROOT/$d" 2>/dev/null || true
                ;;
        esac
    done | grep -vE '^\s*$' | grep -vE "$GATE1_EXCLUDE" || true
}

scan_fixed() {
    local pattern="$1"
    if [ "$USE_RG" -eq 1 ]; then
        local roots=()
        local d
        for d in "${GATE1_SCAN_DIRS[@]}"; do
            [ -d "$SCAN_ROOT/$d" ] && roots+=("$SCAN_ROOT/$d")
        done
        [ "${#roots[@]}" -eq 0 ] && return 0
        rg -n -S --no-heading -F "$pattern" "${roots[@]}" \
            -g '*.ts' -g '*.tsx' -g '*.js' -g '*.jsx' -g '*.swift' -g '*.py' -g '*.sh' -g '*.md' \
            2>/dev/null | grep -vE "$GATE1_EXCLUDE" || true
        return 0
    fi
    local d
    for d in "${GATE1_SCAN_DIRS[@]}"; do
        [ -d "$SCAN_ROOT/$d" ] || continue
        case "$d" in
            services/fusion_control_mac)
                grep -rnF --include='*.swift' --include='*.md' "$pattern" "$SCAN_ROOT/$d" 2>/dev/null || true
                ;;
            *)
                grep -rnF --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' \
                    --include='*.swift' --include='*.py' --include='*.sh' \
                    "$pattern" "$SCAN_ROOT/$d" 2>/dev/null || true
                ;;
        esac
    done | grep -vE '^\s*$' | grep -vE "$GATE1_EXCLUDE" || true
}

for pattern in "${GATE1_ERE_PATTERNS[@]}"; do
    hits=$(scan_ere "$pattern")
    if [ -n "$hits" ]; then
        fail "GATE 1 violation — ERE pattern '$pattern':"
        echo "$hits" | head -10 | sed 's/^/       /'
    fi
done

for pattern in "${GATE1_FIXED[@]}"; do
    hits=$(scan_fixed "$pattern")
    if [ -n "$hits" ]; then
        fail "GATE 1 violation — literal / line pattern '$pattern':"
        echo "$hits" | head -10 | sed 's/^/       /'
    fi
done

WC="$SCAN_ROOT/services/gaiaos_ui_web/app/context/WalletContext.tsx"
if [ -f "$WC" ]; then
    if grep -qE 'generateKey|createKey|subtle\.generate' "$WC" 2>/dev/null; then
        fail "GATE 1 — WalletContext contains key generation code"
    else
        pass "WalletContext — no key generation"
    fi
else
    pass "WalletContext not at expected path (skipped)"
fi

G1_END=$VIOLATIONS
if [ "$G1_END" -eq "$G1_START" ]; then
    pass "GATE 1 clean"
fi

# ─── GATE 2 — Discord (Founder Mac paths only; server workers excluded) ───
header "GATE 2: DISCORD AUTOMATION (MAC / SCRIPTS LANE)"

G2_START=$VIOLATIONS

GATE2_DIRS=()
for d in "$SCAN_ROOT/scripts" "$SCAN_ROOT/deploy/mac_cell_mount" "$SCAN_ROOT/macos"; do
    [ -d "$d" ] && GATE2_DIRS+=("$d")
done

GATE2_BAD_ERE=(
    'open[[:space:]]+discord://'
    'child_process.*exec.*discord'
)

GATE2_EXCLUDE='scope_fortress|membrane_routing|discord_open_bot_invite_mac\.sh'

if [ "${#GATE2_DIRS[@]}" -gt 0 ]; then
    for pattern in "${GATE2_BAD_ERE[@]}"; do
        hits=$(grep -rEn --include='*.sh' --include='*.swift' --include='*.applescript' \
            "$pattern" "${GATE2_DIRS[@]}" 2>/dev/null | grep -vE "$GATE2_EXCLUDE" || true)
        if [ -n "$hits" ]; then
            fail "GATE 2 violation — pattern '$pattern':"
            echo "$hits" | head -10 | sed 's/^/       /'
        fi
    done
fi

# Rule may live under GAIAOS/.cursor/rules or monorepo root .cursor/rules (FoT8D).
DISCORD_MAC_RULE=""
if [ -f "$SCAN_ROOT/.cursor/rules/discord-mac-automation.mdc" ]; then
    DISCORD_MAC_RULE="$SCAN_ROOT/.cursor/rules/discord-mac-automation.mdc"
elif [ -f "$SCAN_ROOT/../.cursor/rules/discord-mac-automation.mdc" ]; then
    DISCORD_MAC_RULE="$SCAN_ROOT/../.cursor/rules/discord-mac-automation.mdc"
fi
if [ -n "$DISCORD_MAC_RULE" ]; then
    pass "discord-mac-automation.mdc present ($DISCORD_MAC_RULE)"
else
    fail "GATE 2 — discord-mac-automation.mdc MISSING (expected .cursor/rules under GAIA_ROOT or parent)"
fi

if [ -f "$SCAN_ROOT/services/discord_frontier/shared/membrane_routing.py" ]; then
    pass "membrane_routing.py present"
else
    fail "GATE 2 — membrane_routing.py MISSING"
fi

G2_END=$VIOLATIONS
if [ "$G2_END" -eq "$G2_START" ]; then
    pass "GATE 2 clean"
fi

# ─── GATE 3 — Bulk data on NATS ───
header "GATE 3: LARGE DATA ON NATS"

G3_START=$VIOLATIONS

GATE3_ERE=(
    'nats[[:space:]]+pub.*jsonl'
    'readFileSync?\(.*jsonl.*\).*publish'
    'nc\.publish\([^)]*jsonl'
)

GATE3_SCAN_DIRS=(scripts macos deploy services/gaiaos_ui_web services/fot_mcp_gateway services/discord_frontier apps tools)

for pattern in "${GATE3_ERE[@]}"; do
    hits=""
    if [ "$USE_RG" -eq 1 ]; then
        roots=()
        for d in "${GATE3_SCAN_DIRS[@]}"; do
            [ -d "$SCAN_ROOT/$d" ] && roots+=("$SCAN_ROOT/$d")
        done
        if [ "${#roots[@]}" -gt 0 ]; then
            hits=$(rg -n -S --no-heading -e "$pattern" "${roots[@]}" \
                -g '*.ts' -g '*.tsx' -g '*.js' -g '*.py' -g '*.sh' 2>/dev/null \
                | grep -vE 'node_modules/|\.git/|scope_fortress_scan|/evidence/' || true)
        fi
    else
        for d in "${GATE3_SCAN_DIRS[@]}"; do
            [ -d "$SCAN_ROOT/$d" ] || continue
            hits+=$(grep -rEn --include='*.ts' --include='*.tsx' --include='*.js' --include='*.py' --include='*.sh' \
                "$pattern" "$SCAN_ROOT/$d" 2>/dev/null || true)$'\n'
        done
    fi
    hits=$(echo "$hits" | grep -vE '^\s*$' | grep -vE 'node_modules/|\.git/|scope_fortress_scan|/evidence/' || true)
    if [ -n "$hits" ]; then
        fail "GATE 3 violation — '$pattern':"
        echo "$hits" | head -8 | sed 's/^/       /'
    fi
done

if [ "$USE_RG" -eq 1 ]; then
    NATS_PUB_FILES=$(rg -l -S -e 'nats[[:space:]]+pub\b' -e '\.publish\(' "$SCAN_ROOT/scripts" \
        "$SCAN_ROOT/deploy/mac_cell_mount/bin" 2>/dev/null | grep -vE 'node_modules|scope_fortress_scan|fusion_mesh_mooring_heartbeat\.sh' || true)
else
    NATS_PUB_FILES=$(grep -rlE 'nats[[:space:]]+pub\b|\.publish\(' "$SCAN_ROOT/scripts" \
        "$SCAN_ROOT/deploy/mac_cell_mount/bin" 2>/dev/null | grep -vE 'node_modules|scope_fortress_scan|fusion_mesh_mooring_heartbeat\.sh' || true)
fi

if [ -n "$NATS_PUB_FILES" ]; then
    echo -e "  ${YLW}ℹ${RST} NATS publish in scripts (must reference schema or ≤4KB guard):"
    echo "$NATS_PUB_FILES" | sed 's/^/       /'
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        [ ! -f "$f" ] && continue
        if grep -qE 'cell\.status\.v1|gaiaftcl\.fusion\.cell\.status|MAX_PAYLOAD|4096|4_096|4kb|4KB' "$f" 2>/dev/null; then
            pass "$(basename "$f") references schema or size guard"
        else
            fail "GATE 3 — $(basename "$f") publishes to NATS without schema/size reference"
        fi
    done <<< "$NATS_PUB_FILES"
fi

G3_END=$VIOLATIONS
if [ "$G3_END" -eq "$G3_START" ]; then
    pass "GATE 3 clean"
fi

# ─── GATE 4 — FUSION_SKIP_MOOR_PREFLIGHT in prod launch surfaces ───
header "GATE 4: FUSION_SKIP_MOOR_PREFLIGHT IN PROD LAUNCH"

G4_START=$VIOLATIONS

SKIP_EXCLUDE='\.md$|\.mdc$|scope_fortress_scan\.sh|FUSION_FLEET_MOOR_USD_PLAN|\.plan\.md|example\.|\.example\.'

while IFS= read -r f; do
    [[ "$f" == *node_modules* ]] && continue
    [[ "$f" == */.git/* ]] && continue
    case "$f" in
        *.service|*.timer|*.plist|*docker-compose*.yml|*docker-compose*.yaml|*compose*.yml|*compose*.yaml)
            if grep -q 'FUSION_SKIP_MOOR_PREFLIGHT' "$f" 2>/dev/null; then
                fail "GATE 4 — $f sets FUSION_SKIP_MOOR_PREFLIGHT (break-glass must not be in unattended prod)"
            fi
            ;;
    esac
done < <(find "$SCAN_ROOT" \( -name '*.service' -o -name '*.timer' -o -name '*.plist' -o -name 'docker-compose*.yml' -o -name 'docker-compose*.yaml' -o -name 'compose*.yml' -o -name 'compose*.yaml' \) 2>/dev/null)

G4_END=$VIOLATIONS
if [ "$G4_END" -eq "$G4_START" ]; then
    pass "GATE 4 clean"
fi

# ─── SUMMARY (per-gate deltas via G*_END) ───
header "SCAN COMPLETE"

G1V=$((G1_END - G1_START))
G2V=$((G2_END - G2_START))
G3V=$((G3_END - G3_START))
G4V=$((G4_END - G4_START))

if [ "$VIOLATIONS" -eq 0 ]; then
    echo -e "\n${GRN}ALL GATES CLEAN — 0 violations${RST}"
    echo "Terminal state: CALORIE (scope fortress holding)"
    exit 0
fi

echo -e "\n${RED}REFUSED — $VIOLATIONS violation(s) found${RST}"
echo "Terminal state: REFUSED"
echo ""
echo "Gate 1 (Passkey/Custody):     $G1V violation(s)"
echo "Gate 2 (Discord Mac lane):    $G2V violation(s)"
echo "Gate 3 (Large Data / NATS):   $G3V violation(s)"
echo "Gate 4 (Skip moor in prod):   $G4V violation(s)"
echo ""
echo "Rule: .cursor/rules/scope-fortress-gates.mdc"
exit 1
