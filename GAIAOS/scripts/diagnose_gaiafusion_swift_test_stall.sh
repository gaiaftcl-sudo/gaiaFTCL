#!/usr/bin/env bash
# C4 witness: why `swift test` may hang after "Build complete" — stale SwiftPM / XCTest workers.
# Uninterruptible (UE/UEs) helpers often survive killed shells; SIGKILL may not reap them until reboot.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GF="$ROOT/macos/GaiaFusion"
echo "━━ GaiaFusion swift test stall diagnostic (GF=$GF) ━━"
echo "swift-test processes:"
pgrep -lf swift-test 2>/dev/null || echo "  (none)"
echo "swiftpm-xctest-helper (STAT often UE when stuck):"
ps aux 2>/dev/null | rg '[/]swiftpm-xctest-helper.*GaiaFusionPackageTests' || echo "  (none)"
echo "xctest targeting this package:"
ps aux 2>/dev/null | rg '[/]xctest.*GaiaFusionPackageTests' || echo "  (none)"
echo "GaiaFusion debug binary (stray / zombie cwd under .build):"
ps aux 2>/dev/null | rg '[/]GaiaFusion/.build/arm64-apple-macosx/debug/GaiaFusion$' || echo "  (none)"
echo ""
echo "If helpers show STAT=UE and swift test never prints test cases: reboot or log out/in to clear kernel-side waits."
echo "After a clean boot, run: bash scripts/run_gaiafusion_swift_tests.sh"
exit 0
