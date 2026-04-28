#!/usr/bin/env zsh
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
OUT="${2:-${ROOT}/evidence/fsd_missing_refs_baseline.json}"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

typeset -a REFS=(
  "cells/lithography/qualification/traceability_matrix.md"
  "cells/lithography/rtl/hmmu/README.md"
  "cells/fusion/macos/MacFusionQualification/README.md"
  "cells/fusion/macos/MacHealthQualification/README.md"
  "cells/fusion/macos/QualificationRunner/README.md"
  "cells/fusion/test_qualification_clean_clone.sh"
  "cells/fusion/deploy/mac_cell_mount/bin/cell_onboard.sh"
  "cells/fusion/deploy/mac_cell_mount/bin/gaia_mount"
  "cells/fusion/deploy/mac_cell_mount/spring/seed_receipt_template.json"
  "cells/fusion/deploy/mac_cell_mount/nats/nats_seed.conf"
  "cells/fusion/deploy/mac_cell_mount/README_MEMBRANE.md"
  "cells/fusion/deploy/fusion_mesh/config/benchmarks/osti_baseline.json"
  "cells/fusion/services/gaiaftcl_sovereign_facade/src/entry_point.swift"
  "cells/health/.admincell-expected/orchestrator.sha256"
)

mkdir -p "$(dirname "${OUT}")"

{
  print "{"
  print "  \"generated_at\": \"${TS}\","
  print "  \"root\": \"${ROOT}\","
  print "  \"references\": ["
  local i=1
  local total="${#REFS[@]}"
  local rel abs ref_state
  for rel in "${REFS[@]}"; do
    abs="${ROOT}/${rel}"
    if [[ -e "${abs}" ]]; then
      ref_state="present"
    else
      ref_state="missing"
    fi
    print "    {\"path\":\"${rel}\",\"status\":\"${ref_state}\"}$( (( i < total )) && print , )"
    i=$(( i + 1 ))
  done
  print "  ]"
  print "}"
} > "${OUT}"

print "WROTE:${OUT}"
