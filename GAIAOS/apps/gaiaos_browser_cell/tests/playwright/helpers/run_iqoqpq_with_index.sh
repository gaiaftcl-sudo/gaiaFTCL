#!/usr/bin/env bash
set -euo pipefail

: "${GAIAOS_RUN_ID:?ERROR: GAIAOS_RUN_ID not set}"
: "${BROWSER_CELL_BASE_URL:?ERROR: BROWSER_CELL_BASE_URL not set}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
PW_CFG="${ROOT_DIR}/apps/gaiaos_browser_cell/tests/playwright/playwright.config.ts"
HELPERS_DIR="${ROOT_DIR}/apps/gaiaos_browser_cell/tests/playwright/helpers"
RUN_DIR="${ROOT_DIR}/apps/gaiaos_browser_cell/validation_artifacts/${GAIAOS_RUN_ID}"
DIAG_DIR="${RUN_DIR}/diagnostics"

echo "Run: ${GAIAOS_RUN_ID}"
echo "Base URL: ${BROWSER_CELL_BASE_URL}"

cd "${ROOT_DIR}"

mkdir -p "${DIAG_DIR}"

echo "Capturing server logs snapshot (pre-run)..."
{
  echo "=== docker ps ==="
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
  echo ""
  echo "=== docker compose ps (apps/gaiaos_browser_cell) ==="
  (cd "${ROOT_DIR}/apps/gaiaos_browser_cell" && docker compose ps) || true
  echo ""
  echo "=== docker compose logs tail (apps/gaiaos_browser_cell) ==="
  (cd "${ROOT_DIR}/apps/gaiaos_browser_cell" && docker compose logs --no-color --tail=200) || true
} > "${DIAG_DIR}/server.log" 2>&1 || true

echo "Building index generator (pre-run, required for globalTeardown)..."
npx --yes tsc -p "${HELPERS_DIR}/tsconfig.build-index.json"

set +e
echo "Running Playwright (stdout/stderr captured)..."
npx --yes playwright test -c "${PW_CFG}" --reporter=line 2>&1 | tee "${DIAG_DIR}/playwright.log"
PW_EXIT="${PIPESTATUS[0]}"
set -e

echo "Generating INDEX.md..."
set +e
HAR_PATH="${DIAG_DIR}/network.har"
if [[ ! -f "${HAR_PATH}" ]]; then
  echo "Generating network.har (best-effort)..."
  GAIAOS_HAR_PATH="${HAR_PATH}" node "${HELPERS_DIR}/har_probe.js" 2>&1 | tee "${DIAG_DIR}/har_probe.log"
fi

node "${HELPERS_DIR}/dist/build_index.js" 2>&1 | tee "${DIAG_DIR}/index_generator.log"
IDX_EXIT="${PIPESTATUS[0]}"
set -e

INDEX_PATH="apps/gaiaos_browser_cell/validation_artifacts/${GAIAOS_RUN_ID}/INDEX.md"
echo "${INDEX_PATH}"

echo "Collecting Playwright failure artifacts (best-effort)..."
OUT_DIR="${DIAG_DIR}/playwright_output"
if [[ -d "${OUT_DIR}" ]]; then
  # trace zip (retain-on-failure)
  TRACE="$(find "${OUT_DIR}" -type f -name '*.zip' | head -n 1 || true)"
  if [[ -n "${TRACE}" ]]; then
    cp -f "${TRACE}" "${DIAG_DIR}/playwright_trace.zip" || true
  fi

  # screenshot on failure
  PNG="$(find "${OUT_DIR}" -type f -name '*.png' | head -n 1 || true)"
  if [[ -n "${PNG}" ]]; then
    cp -f "${PNG}" "${DIAG_DIR}/stop_state.png" || true
  fi

  # video on failure (webm in Playwright)
  WEBM="$(find "${OUT_DIR}" -type f -name '*.webm' | head -n 1 || true)"
  if [[ -n "${WEBM}" ]]; then
    cp -f "${WEBM}" "${DIAG_DIR}/stop_state.webm" || true
  fi
fi

echo "Capturing server logs snapshot (post-run)..."
{
  echo "=== docker compose logs tail (apps/gaiaos_browser_cell) ==="
  (cd "${ROOT_DIR}/apps/gaiaos_browser_cell" && docker compose logs --no-color --tail=400) || true
} >> "${DIAG_DIR}/server.log" 2>&1 || true

if [[ "${IDX_EXIT}" -ne 0 ]]; then
  exit 3
fi
exit "${PW_EXIT}"

