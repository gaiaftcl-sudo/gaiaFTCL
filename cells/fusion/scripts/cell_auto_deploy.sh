#!/usr/bin/env bash
set -euo pipefail

REGISTRY="gaiaftcl"
CELL_ID="${CELL_ID:-unknown}"

echo "🔊 Cell Auto-Deploy Listener Started"
echo "Cell ID: $CELL_ID"
echo "Listening on: gaiaftcl.mesh.rebuild_request"
echo ""

# Subscribe to NATS rebuild requests
docker exec gaiaftcl-nats nats sub gaiaftcl.mesh.rebuild_request | while read -r msg; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📨 Rebuild request received: $msg"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Extract version from JSON (basic parsing)
    version=$(echo "$msg" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
    
    if [ -z "$version" ]; then
        echo "⚠️  No version in message, using 'latest'"
        version="latest"
    fi
    
    echo "🔄 Pulling version: $version"
    
    # Pull all images
    docker pull "$REGISTRY/fot_mcp_gateway:$version" || true
    docker pull "$REGISTRY/gaiaos_mcp_server:$version" || true
    docker pull "$REGISTRY/franklin_guardian:$version" || true
    docker pull "$REGISTRY/wallet_observer:$version" || true
    docker pull "$REGISTRY/gaiaos_ui_web:$version" || true
    
    echo "📦 Images pulled, restarting services..."
    
    # Restart services using docker-compose
    cd /root/GAIAOS
    docker compose -f docker-compose.cell.yml pull
    docker compose -f docker-compose.cell.yml up -d --force-recreate
    
    echo "✅ Cell $CELL_ID updated and restarted"
    echo ""
done
