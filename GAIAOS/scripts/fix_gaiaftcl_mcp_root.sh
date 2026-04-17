#!/usr/bin/env bash
# Fix GaiaFTCL MCP Root Problem
# Root cause: ask_gaiaftcl returns 48-char fallback instead of full narrative
# Fixes: (1) substrate-generative uses gaia_akg, (2) reflection-game uses substrate-generative:8805

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAIAOS="${SCRIPT_DIR}/.."
CELL_HOST="${1:-77.42.85.60}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/ftclstack-unified}"

echo "🔧 Fixing GaiaFTCL MCP root problem on $CELL_HOST"
echo "   Root: ask_gaiaftcl returns fallback, not full narrative"
echo ""

# 1. Deploy substrate-generative with gaia_akg
echo "📦 Step 1: Deploy substrate-generative (ARANGO_DB=gaia_akg)"
ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@$CELL_HOST "mkdir -p /root/substrate_generative"
scp -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
  "$GAIAOS/services/substrate_generative_sidecar/generative_api.py" \
  "$GAIAOS/services/substrate_generative_sidecar/Dockerfile" \
  root@$CELL_HOST:/root/substrate_generative/

ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@$CELL_HOST << 'ENDSSH'
cd /root/substrate_generative
docker build -t gaiaftcl-substrate-generative:latest . 2>/dev/null || true
docker stop gaiaftcl-substrate-generative 2>/dev/null || true
docker rm gaiaftcl-substrate-generative 2>/dev/null || true
docker run -d \
  --name gaiaftcl-substrate-generative \
  --network gaiaftcl_gaiaftcl \
  -p 8805:8805 \
  -e ARANGO_URL=http://gaiaftcl-arangodb:8529 \
  -e ARANGO_DB=gaia_akg \
  -e ARANGO_USER=root \
  -e ARANGO_PASSWORD=gaiaftcl2026 \
  --restart unless-stopped \
  gaiaftcl-substrate-generative:latest
echo "  substrate-generative: restarted with gaia_akg"
ENDSSH

# 2. Deploy reflection-game with SUBSTRATE_URL=substrate-generative:8805
echo ""
echo "📦 Step 2: Restart reflection-game (SUBSTRATE_URL=substrate-generative:8805)"
ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@$CELL_HOST "mkdir -p /root/gaiaos/services/franklin_guardian /root/gaiaos/services/life_game /root/substrate_generative"
scp -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
  "$GAIAOS/services/franklin_guardian/docker-compose.internal-life.yml" \
  root@$CELL_HOST:/root/gaiaos/services/franklin_guardian/
scp -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
  "$GAIAOS/services/life_game/franklin_reflection_game.py" \
  root@$CELL_HOST:/root/gaiaos/services/life_game/

ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@$CELL_HOST << 'ENDSSH'
cd /root/gaiaos/services/franklin_guardian
docker-compose -f docker-compose.internal-life.yml up -d reflection-game
echo "  reflection-game: restarted with SUBSTRATE_URL=gaiaftcl-substrate-generative:8805"
ENDSSH

echo ""
echo "⏳ Waiting 10s for services to stabilize..."
sleep 10

echo ""
echo "✅ Fix applied. Test via MCP ask_gaiaftcl."
echo "   If still 48 chars: check substrate-generative logs for errors."
echo "   ssh root@$CELL_HOST 'docker logs gaiaftcl-substrate-generative --tail 50'"
echo ""
