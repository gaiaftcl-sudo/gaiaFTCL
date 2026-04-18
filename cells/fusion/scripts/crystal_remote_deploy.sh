#!/usr/bin/env bash
# Run on the cell (after rsync). Uses docker-compose.cell.yml profiles.
set -euo pipefail
: "${CELL_ID:?}"
: "${CELL_IP:?}"
# Graph migrations run on hel1-01; other cells proxy public GET /graph/* to head wallet-gate.
# Use host port 8812 on the head (see docker-compose.head-graph-follow-port.yml): workers
# publish 8803 locally, and Docker OUTPUT DNAT would steal outbound tcp/8803 to the head.
if [ "$CELL_ID" != "gaiaftcl-hcloud-hel1-01" ]; then
  export MESH_GRAPH_FOLLOW_URL="${MESH_GRAPH_FOLLOW_URL:-http://77.42.85.60:8812}"
fi
mkdir -p /opt/gaia/GAIAOS /etc/gaiaftcl
test -f /etc/gaiaftcl/secrets.env || touch /etc/gaiaftcl/secrets.env
chmod 600 /etc/gaiaftcl/secrets.env 2>/dev/null || true
cd /opt/gaia/GAIAOS

# Germline: CELL_ID/CELL_IP + mesh-internal key (head generates once; siblings receive via deploy).
MESH_HEAD_BOOTSTRAP=0
[ "$CELL_ID" = "gaiaftcl-hcloud-hel1-01" ] && MESH_HEAD_BOOTSTRAP=1
export MESH_HEAD_BOOTSTRAP CRYSTAL_EARTH_MOORING="${CRYSTAL_EARTH_MOORING:-1}"
python3 /opt/gaia/cells/fusion/scripts/merge_gaiaftcl_secrets.py

COMPOSE=(docker compose --env-file /etc/gaiaftcl/secrets.env -f docker-compose.cell.yml)
COMPOSE_HEAD=(docker compose --env-file /etc/gaiaftcl/secrets.env -f docker-compose.cell.yml -f docker-compose.head-graph-follow-port.yml)

EARTH_PROFILE=()
if grep -qsE '^EARTH_INGESTOR=1' /etc/gaiaftcl/secrets.env 2>/dev/null || [ "${EARTH_INGESTOR:-}" = "1" ]; then
  EARTH_PROFILE=(--profile earth-ingestor)
fi

if [ "$CELL_ID" = "gaiaftcl-hcloud-hel1-01" ]; then
  docker stop fot-mcp-gateway-mesh 2>/dev/null || true
  docker rm fot-mcp-gateway-mesh 2>/dev/null || true
  export UPSTREAM_GATEWAY_URL=http://fot-mcp-gateway-mesh:8803
  export GATEWAY_HEALTH_URL=http://fot-mcp-gateway-mesh:8803/health
  "${COMPOSE_HEAD[@]}" "${EARTH_PROFILE[@]}" --profile mesh-gateway up -d --build
elif docker inspect gaiaftcl-mcp-gateway >/dev/null 2>&1; then
  export UPSTREAM_GATEWAY_URL=http://gaiaftcl-mcp-gateway:8830
  export GATEWAY_HEALTH_URL=http://gaiaftcl-mcp-gateway:8830/health
  "${COMPOSE[@]}" "${EARTH_PROFILE[@]}" up -d --build
elif docker inspect gaiaftcl-arangodb >/dev/null 2>&1 && docker inspect gaiaftcl-nats >/dev/null 2>&1; then
  export UPSTREAM_GATEWAY_URL=http://fot-mcp-gateway-mesh:8803
  export GATEWAY_HEALTH_URL=http://fot-mcp-gateway-mesh:8803/health
  if docker inspect fot-mcp-gateway-mesh >/dev/null 2>&1; then
    "${COMPOSE[@]}" "${EARTH_PROFILE[@]}" up -d --build
  else
    docker stop fot-mcp-gateway-mesh 2>/dev/null || true
    docker rm fot-mcp-gateway-mesh 2>/dev/null || true
    "${COMPOSE[@]}" "${EARTH_PROFILE[@]}" --profile mesh-gateway up -d --build
  fi
else
  docker network create gaiaftcl_gaiaftcl 2>/dev/null || true
  docker stop fot-mcp-gateway-mesh 2>/dev/null || true
  docker rm fot-mcp-gateway-mesh 2>/dev/null || true
  export UPSTREAM_GATEWAY_URL=http://fot-mcp-gateway-mesh:8803
  export GATEWAY_HEALTH_URL=http://fot-mcp-gateway-mesh:8803/health
  "${COMPOSE[@]}" "${EARTH_PROFILE[@]}" --profile infra --profile mesh-gateway up -d --build
fi

# Head only: ensure VIE document collections exist so /vie/ingest can close (idempotent).
if [ "$CELL_ID" = "gaiaftcl-hcloud-hel1-01" ] && docker inspect fot-mcp-gateway-mesh >/dev/null 2>&1; then
  KGM="$PWD/scripts/graph/knowledge_graph_migrate.py"
  if [ -f "$KGM" ]; then
    docker cp "$KGM" fot-mcp-gateway-mesh:/tmp/knowledge_graph_migrate.py
    docker exec fot-mcp-gateway-mesh python3 /tmp/knowledge_graph_migrate.py --ensure-vie-only \
      || echo "WARN: VIE Arango ensure failed (check gaiaftcl-arangodb + credentials)"
  fi
fi

# Discord Frontier membrane (opt-in; requires valid token + DISCORD_GUILD_ID in secrets.env).
if [ "$CELL_ID" = "gaiaftcl-hcloud-hel1-01" ] && grep -qs '^DISCORD_MEMBRANE_DEPLOY=1' /etc/gaiaftcl/secrets.env 2>/dev/null; then
  DC="$PWD/services/discord_frontier/docker-compose.discord-membrane.yml"
  if [ -f "$DC" ]; then
    docker compose --env-file /etc/gaiaftcl/secrets.env -f "$DC" up -d --build \
      || echo "WARN: discord membrane failed (token, guild id, or network)"
  fi
fi
