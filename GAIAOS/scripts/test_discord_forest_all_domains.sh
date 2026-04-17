#!/usr/bin/env bash
# Validate + static-test full GaiaFTCL Discord forest (every domain bot in registry).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DF="${REPO_ROOT}/services/discord_frontier"

echo "=== DISCORD FOREST — ALL DOMAINS ==="
echo "Frontier: ${DF}"
echo ""

python3 "${DF}/scripts/validate_game_room_registry.py"
python3 "${DF}/scripts/render_domain_compose_fragments.py" --write
python3 "${DF}/scripts/verify_discord_registry_compose.py"
python3 "${DF}/scripts/emit_discord_compose_config_test_env.py"

python3 -c "
from pathlib import Path
import sys
sys.path.insert(0, str(Path('${DF}').resolve()))
from shared.guild_topology import load_planned_channels
n = len(load_planned_channels())
assert n >= 30, n
print(f'OK: guild topology plan ({n} channels)')
"

echo ""
echo "=== Python syntax: all domain bot mains ==="
python3 -m compileall -q "${DF}/bots" "${DF}/discord_app" "${DF}/shared" "${DF}/mother" "${DF}/workers" || {
  echo "BLOCKED: compileall failed"
  exit 1
}

STUB="${DF}/discord-forest.env.compose-stub"
if [[ ! -f "$STUB" ]]; then
  echo "BLOCKED: missing ${STUB}"
  exit 2
fi

echo ""
echo "=== docker compose config (merged forest + domains) ==="
if ! command -v docker >/dev/null 2>&1; then
  echo "BLOCKED: docker not in PATH — skipping compose config"
  exit 0
fi

(
  cd "$DF"
  export DISCORD_FOREST_ENV_FILE="$STUB"
  docker compose -f docker-compose.discord-forest.yml \
    --env-file discord-forest.compose-config.env.example \
    config --quiet
)
echo "OK: docker compose config"

if [[ "${DISCORD_FOREST_DOCKER_BUILD_ALL:-}" == "1" ]]; then
  echo ""
  echo "=== docker compose build --profile domains (optional; slow) ==="
  (
    cd "$DF"
    export DISCORD_FOREST_ENV_FILE="$STUB"
    docker compose -f docker-compose.discord-forest.yml \
      --env-file discord-forest.compose-config.env.example \
      --profile domains build
  )
  echo "OK: docker build all domain services"
fi

echo ""
echo "=== DONE ==="
echo "Deploy every domain bot: cd services/discord_frontier && DISCORD_FOREST_ENV_FILE=/etc/gaiaftcl/discord-forest.env docker compose -f docker-compose.discord-forest.yml --profile domains up -d --build"
exit 0
