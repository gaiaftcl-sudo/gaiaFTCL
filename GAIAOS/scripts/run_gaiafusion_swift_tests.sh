#!/usr/bin/env bash
# GaiaFusion — XCTest via SwiftPM with a single --filter regex (OR semantics).
#
# Run from Terminal.app in an interactive Aqua session on the Mac. Headless / IDE-only shells
# can wedge swiftpm-xctest-helper on WindowServer Mach IPC (see macos/GaiaFusion/README.md).
#
# SwiftPM: each --filter is a regex; multiple --filter flags combine with AND, so
#   swift test --filter PlantKindsCatalogTests --filter LocalServerAPITests
# can match **zero** tests (distinct class names) and stall or confuse CI.
#
# Override the default bundle list:
#   GAIAFUSION_TEST_FILTER='PlantKindsCatalogTests' bash scripts/run_gaiafusion_swift_tests.sh
#
# If swift test hangs after "Build complete", inspect `ps` for swiftpm-xctest-helper in
# uninterruptible (UE) state — may require logging out or reboot to clear.
#
# Preflight: refuse fast when swiftpm-xctest-helper / xctest rows exist for this package (otherwise
# swift test often blocks silently). Note: `rm -rf .build` does **not** always reap STAT=UE rows in
# `ps` — same bundle path may reappear after rebuild, so we do not try to distinguish “ghost” vs “live”
# here; a stuck kernel queue still needs reboot / session reset. Skip: GAIAFUSION_SKIP_STALL_PREFLIGHT=1
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/macos/GaiaFusion"
if [[ "${GAIAFUSION_SKIP_STALL_PREFLIGHT:-0}" != "1" ]]; then
  STUCK="$(ps aux 2>/dev/null | rg '[/]swiftpm-xctest-helper.*GaiaFusionPackageTests|[/]xctest.*GaiaFusionPackageTests\.xctest' | wc -l | tr -d '[:space:]')"
  STUCK="${STUCK:-0}"
  if [[ "${STUCK}" -gt 0 ]]; then
    echo "REFUSED: ${STUCK} swiftpm-xctest-helper/xctest process(es) for GaiaFusion (often STAT=UE). Reboot or session reset, then retry." >&2
    echo "Witness: bash ${ROOT}/scripts/diagnose_gaiafusion_swift_test_stall.sh" >&2
    echo "Override (may hang): GAIAFUSION_SKIP_STALL_PREFLIGHT=1 $0 $*" >&2
    exit 86
  fi
fi
FILTER="${GAIAFUSION_TEST_FILTER:-PlantKindsCatalogTests|LocalServerAPITests|FusionFacilityWireframeGeometryTests|OpenUSDPlaybackSnapshotTests}"
exec swift test --filter "$FILTER" "$@"
