#!/usr/bin/env bash
# Scorched-earth purge for stuck swiftpm-xctest-helper / xctest (UE). Uses SUDO_PASSWORD from GAIAOS/.env.
# See .env.example; never commit real passwords (root .env is gitignored).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/sudo_from_env.sh"

echo "━━ gaiafusion_kernel_purge (GAIAOS=$ROOT) ━━"

echo "━━ Step 1: killall Swift / XCTest / simulator ━━"
sudo_from_env killall -9 swift-test swift-build swiftpm-xctest-helper xctest 2>/dev/null || true
sudo_from_env killall -9 CoreSimulatorService 2>/dev/null || true

echo "━━ Step 2: lsof lines matching GaiaFusion → kill -9 PIDs ━━"
sudo_from_env bash -c 'lsof 2>/dev/null | grep GaiaFusion | awk "{print \$2}" | sort -u | while read -r p; do [ -n "$p" ] && kill -9 "$p" 2>/dev/null || true; done'

echo "━━ Step 3: SwiftPM cache, DerivedData, macos/GaiaFusion/.build ━━"
sudo_from_env rm -rf "${HOME}/Library/Caches/org.swift.swiftpm"
sudo_from_env bash -c 'rm -rf "${HOME}/Library/Developer/Xcode/DerivedData/"*'
sudo_from_env rm -rf "${ROOT}/macos/GaiaFusion/.build"

echo "━━ Step 4: processes in uninterruptible-ish state (STAT starting with U) ━━"
ps -eo pid,stat,command 2>/dev/null | awk '$2 ~ /^U/ {print}' || true

echo "CALORIE: gaiafusion_kernel_purge finished — if U-state swiftpm-xctest-helper remains, reboot or soft-reset WindowServer (see macOS GaiaFusion README)."
