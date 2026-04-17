#!/usr/bin/env bash
# Parallel-safe checks for sovereign sidecar *repo artifacts* (no VM required).
# Receipt: exit 0 only if all checks pass.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FAIL=0

run_check() {
  local name="$1"
  shift
  if "$@"; then
    echo "OK  $name"
  else
    echo "FAIL $name" >&2
    FAIL=1
  fi
}

echo "━━ Fusion sidecar bundle verify (GAIA_ROOT=$ROOT) ━━"

run_check "compose file present" test -f docker-compose.fusion-sidecar.yml
run_check "README_CELL_STACK canonical" test -f deploy/mac_cell_mount/README_CELL_STACK.md
run_check "arango bootstrap script" test -f scripts/fusion_sidecar_arango_bootstrap.sh
run_check "fusion_sidecar_stack_smoke script" test -f scripts/fusion_sidecar_stack_smoke.sh
run_check "mcp_mac_cell_probe script" test -f scripts/mcp_mac_cell_probe.py
if command -v docker >/dev/null 2>&1; then
  run_check "docker compose config" sh -c "docker compose -f docker-compose.fusion-sidecar.yml config >/dev/null"
else
  echo "SKIP docker compose config (docker not in PATH)"
fi

run_check "guest mount script bash -n" bash -n deploy/mac_cell_mount/fusion_sidecar_guest/mount-gaiaos-virtiofs.sh

run_check "SUBSTRATE_SOURCE_OF_TRUTH index" test -f docs/SUBSTRATE_SOURCE_OF_TRUTH.md

for f in \
  deploy/mac_cell_mount/fusion_sidecar_guest/README.md \
  deploy/mac_cell_mount/FUSION_SIDECAR_HOST_APP.md \
  deploy/mac_cell_mount/FUSION_SIDECAR_GUEST_IMAGE.md \
  evidence/fusion_control/FUSION_SIDECAR_FIELD_OF_FIELDS.md \
  evidence/fusion_control/FUSION_SIDECAR_ACTIVE_PLAN.md; do
  run_check "doc exists $f" test -f "$f"
done

if [[ "${VERIFY_FUSION_SIDECAR_XCODE:-0}" == "1" ]]; then
  run_check "xcodebuild FusionSidecarHost" \
    xcodebuild -project macos/FusionSidecarHost/FusionSidecarHost.xcodeproj \
      -scheme FusionSidecarHost -configuration Debug build -destination "platform=macOS" -quiet
else
  echo "SKIP xcodebuild (set VERIFY_FUSION_SIDECAR_XCODE=1 to enable)"
fi

if [[ "$FAIL" -eq 0 ]]; then
  echo "CALORIE: fusion sidecar bundle checks passed"
  exit 0
fi
echo "REFUSED: one or more bundle checks failed"
exit 1
