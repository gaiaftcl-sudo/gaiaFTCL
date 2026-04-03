#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
APP_DIR="${ROOT_DIR}/apps/gaiaos_browser_cell"
ART_DIR="${APP_DIR}/validation_artifacts"

: "${BROWSER_CELL_BASE_URL:?ERROR: BROWSER_CELL_BASE_URL not set}"

export GAIAOS_RUN_ID="${GAIAOS_RUN_ID:-$(date +%Y%m%d-%H%M%S)-$(git -C "${ROOT_DIR}" rev-parse --short HEAD)}"

echo "Running evidence bundle: ${GAIAOS_RUN_ID}"
cd "${ROOT_DIR}"

# Optional: enforce no-remote-deps before running Playwright.
"${APP_DIR}/scripts/check_no_remote_ui_deps.sh"

# Run the official wrapper (generates INDEX + diagnostics).
"${APP_DIR}/tests/playwright/helpers/run_iqoqpq_with_index.sh"

RUN_DIR="${ART_DIR}/${GAIAOS_RUN_ID}"
LATEST="${ART_DIR}/LATEST"

if [[ ! -f "${RUN_DIR}/INDEX.md" ]]; then
  echo "ERROR: run did not produce INDEX.md at ${RUN_DIR}/INDEX.md"
  exit 3
fi

echo "Refreshing ${LATEST} (no symlinks)..."
rm -rf "${LATEST}"
mkdir -p "${LATEST}"
cp -R "${RUN_DIR}/." "${LATEST}/"

# Preserve stop reproduction + fix narrative (if available) so LATEST is always self-contained.
FIX_SRC="$(ls -1dt "${ART_DIR}"/final_ui_all_worlds_* 2>/dev/null | head -n 1 || true)"
if [[ -n "${FIX_SRC}" ]]; then
  if [[ -f "${FIX_SRC}/FIX_SUMMARY.md" ]]; then
    cp -f "${FIX_SRC}/FIX_SUMMARY.md" "${LATEST}/FIX_SUMMARY.md" || true
  fi
  mkdir -p "${LATEST}/diagnostics" || true
  for f in stop_state.png stop_state.webm playwright_trace.zip hard_fail_proof.txt browser_console_stop_repro.log; do
    if [[ -f "${FIX_SRC}/diagnostics/${f}" ]]; then
      cp -f "${FIX_SRC}/diagnostics/${f}" "${LATEST}/diagnostics/${f}" || true
    fi
  done
fi

# Regenerate index for LATEST so it links any preserved diagnostics and matches the current required list.
export GAIAOS_RUN_ID="LATEST"
node "${APP_DIR}/tests/playwright/helpers/dist/build_index.js"

echo "OK: ${LATEST}/INDEX.md"


