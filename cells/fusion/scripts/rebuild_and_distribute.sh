#!/usr/bin/env bash
set -euo pipefail

VERSION="2026.04.03-wallet-fix"
TEMP_DIR="/tmp/gaiaftcl-images"
mkdir -p "$TEMP_DIR"

CELLS=(
    "77.42.85.60"
    "135.181.88.134"
    "77.42.32.156"
    "77.42.88.110"
    "37.27.7.9"
    "37.120.187.247"
    "152.53.91.220"
    "152.53.88.141"
    "37.120.187.174"
)

echo "🔨 REBUILDING ALL SERVICES WITH NEW WALLET"
echo "Version: $VERSION"
echo ""

# Build fot_mcp_gateway (context = repo root)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Building: fot_mcp_gateway"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker build \
    -t gaiaftcl/fot_mcp_gateway:$VERSION \
    -t gaiaftcl/fot_mcp_gateway:latest \
    -f services/fot_mcp_gateway/Dockerfile \
    .

# Build gaiaos_mcp_server (context = repo root)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Building: gaiaos_mcp_server"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker build \
    -t gaiaftcl/gaiaos_mcp_server:$VERSION \
    -t gaiaftcl/gaiaos_mcp_server:latest \
    -f services/gaiaos_mcp_server/Dockerfile.standalone \
    .

# Build gaiaos_ui_web (context = service dir)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Building: gaiaos_ui_web"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker build \
    -t gaiaftcl/gaiaos_ui_web:$VERSION \
    -t gaiaftcl/gaiaos_ui_web:latest \
    -f services/gaiaos_ui_web/Dockerfile \
    services/gaiaos_ui_web

echo ""
echo "✅ All images built locally"
echo ""
echo "📤 Distributing to all 9 cells..."
echo ""

for cell in "${CELLS[@]}"; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📡 Deploying to $cell"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Save images to tar
    echo "  Saving images..."
    docker save gaiaftcl/fot_mcp_gateway:latest | gzip > "$TEMP_DIR/fot_mcp_gateway.tar.gz"
    docker save gaiaftcl/gaiaos_mcp_server:latest | gzip > "$TEMP_DIR/gaiaos_mcp_server.tar.gz"
    docker save gaiaftcl/gaiaos_ui_web:latest | gzip > "$TEMP_DIR/gaiaos_ui_web.tar.gz"
    
    # Transfer to cell
    echo "  Transferring..."
    scp -i ~/.ssh/qfot_unified "$TEMP_DIR"/*.tar.gz root@$cell:/tmp/
    
    # Load and restart on cell
    echo "  Loading and restarting..."
    ssh -i ~/.ssh/qfot_unified root@$cell << 'ENDSSH'
cd /tmp
docker load < fot_mcp_gateway.tar.gz
docker load < gaiaos_mcp_server.tar.gz
docker load < gaiaos_ui_web.tar.gz
rm -f *.tar.gz

cd /root/GAIAOS
docker compose -f docker-compose.cell.yml up -d --force-recreate

echo "✅ Cell updated and restarted"
ENDSSH
    
    echo "✅ $cell complete"
    echo ""
done

# Cleanup
rm -rf "$TEMP_DIR"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ ALL 9 CELLS UPDATED WITH NEW WALLET"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "New wallet: 0x91f6e41B4425326e42590191c50Db819C587D866"
echo "Old wallet: 0x858e7ED49680C38B0254abA515793EEc3d1989F5 (REMOVED)"
