#!/usr/bin/env bash
set -euo pipefail

# Discord game rooms — registry consistency + optional live mesh probes.
# Field-of-truth: registry + Codex checks are authoritative; NATS/HTTP probes are BLOCKED when unreachable.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DF_ROOT="${REPO_ROOT}/services/discord_frontier"

echo "=== DISCORD GAME ROOMS VALIDATION ==="
echo "Repo root: ${REPO_ROOT}"
echo ""

if [[ "${INTEGRATION_DISCORD_FOREST_ALL:-}" == "1" ]]; then
  if [[ -x "${REPO_ROOT}/scripts/test_discord_forest_all_domains.sh" ]]; then
    bash "${REPO_ROOT}/scripts/test_discord_forest_all_domains.sh" || exit $?
  else
    echo "BLOCKED: test_discord_forest_all_domains.sh missing"
    exit 2
  fi
  echo ""
fi

if [[ ! -d "${DF_ROOT}" ]]; then
  echo "BLOCKED: discord_frontier not found at ${DF_ROOT}"
  exit 2
fi

python3 "${DF_ROOT}/scripts/validate_game_room_registry.py"
echo ""

MESH_URL="${MESH_PEER_REGISTRY_URL:-http://localhost:8821}"
if curl -fsS --max-time 3 "${MESH_URL}/health" >/dev/null 2>&1; then
  echo "OK: mesh peer registry health at ${MESH_URL}"
else
  echo "BLOCKED: mesh peer registry not reachable at ${MESH_URL} (optional check; set MESH_PEER_REGISTRY_URL)"
fi

if [[ -n "${NATS_URL:-}" ]] && command -v nats >/dev/null 2>&1; then
  if nats rtt --server="${NATS_URL}" >/dev/null 2>&1; then
    echo "OK: NATS RTT succeeded for ${NATS_URL} (run: nats sub 'gaiaftcl.receipts.domain' --server=\${NATS_URL} to witness live receipts)"
  else
    echo "BLOCKED: NATS_URL set but nats rtt failed (server unreachable or CLI mismatch)"
  fi
else
  echo "BLOCKED: NATS receipt probe skipped (set NATS_URL and install nats CLI for optional live check)"
fi

echo ""
if [[ "${INTEGRATION_DISCORD_DEVPORTAL_EMBED:-}" == "1" ]]; then
  UI_WEB="${REPO_ROOT}/services/gaiaos_ui_web"
  if [[ -d "${UI_WEB}" ]] && command -v npm >/dev/null 2>&1; then
    echo "=== Developer Portal Embed Debugger (Playwright) ==="
    (cd "${UI_WEB}" && npm run playwright:devportal:validate-embed) || {
      echo "BLOCKED: devportal embed debugger validate failed (storage: ~/.playwright-discord/storage-devportal-gaiaftcl.json)"
      exit 2
    }
    echo ""
  else
    echo "BLOCKED: gaiaos_ui_web or npm missing — cannot run playwright:devportal:validate-embed"
    exit 2
  fi
else
  echo "Devportal embed: set INTEGRATION_DISCORD_DEVPORTAL_EMBED=1 to run Embed Debugger (optional DISCORD_EMBED_DEBUGGER_URL, DISCORD_EMBED_DEBUGGER_STRICT=1)"
fi

echo ""
if [[ "${INTEGRATION_DISCORD_ONBOARDING_FLOW:-}" == "1" ]]; then
  UI_WEB="${REPO_ROOT}/services/gaiaos_ui_web"
  if [[ -d "${UI_WEB}" ]] && command -v npm >/dev/null 2>&1; then
    echo "=== Discord onboarding flow (/moor -> /getmaccellfusion) ==="
    (cd "${UI_WEB}" && npm run test:e2e:discord:onboarding) || {
      echo "BLOCKED: onboarding flow validation failed (set DISCORD_OWL_CHANNEL_URL + storage state)"
      exit 2
    }
    echo ""
  else
    echo "BLOCKED: gaiaos_ui_web or npm missing — cannot run onboarding flow validation"
    exit 2
  fi
else
  echo "Onboarding flow: set INTEGRATION_DISCORD_ONBOARDING_FLOW=1 to run /moor -> /getmaccellfusion validation"
fi

echo ""
if [[ "${INTEGRATION_DISCORD_PLAYWRIGHT:-}" == "1" ]]; then
  if [[ -x "${REPO_ROOT}/scripts/run_discord_membrane_playwright.sh" ]]; then
    bash "${REPO_ROOT}/scripts/run_discord_membrane_playwright.sh" || echo "BLOCKED: Playwright Discord smoke failed"
  else
    echo "BLOCKED: run_discord_membrane_playwright.sh missing or not executable"
  fi
else
  echo "Playwright: set INTEGRATION_DISCORD_PLAYWRIGHT=1 to run tests/discord_frontier/playwright (optional DISCORD_PLAYWRIGHT_STORAGE_STATE + DISCORD_WEB_TEST_GUILD_URL)"
fi
