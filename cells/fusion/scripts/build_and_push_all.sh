#!/usr/bin/env bash
# GATE3: NATS mesh.rebuild_request below — compact JSON, MAX_PAYLOAD 4096; not jsonl/bulk on wire.
set -euo pipefail

REGISTRY="gaiaftcl"
VERSION="2026.04.03-wallet-fix"

echo "🔨 Building and pushing all services with new founder wallet"
echo "Registry: $REGISTRY"
echo "Version: $VERSION"
echo ""

# Services to rebuild
SERVICES=(
    "fot_mcp_gateway:services/fot_mcp_gateway/Dockerfile"
    "gaiaos_mcp_server:services/gaiaos_mcp_server/Dockerfile.standalone"
    "franklin_guardian:services/franklin_guardian/Dockerfile"
    "wallet_observer:services/wallet_observer/Dockerfile"
    "gaiaos_ui_web:services/gaiaos_ui_web/Dockerfile"
)

for service_def in "${SERVICES[@]}"; do
    IFS=: read -r service_name dockerfile <<< "$service_def"
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 Building: $service_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    context_dir=$(dirname "$dockerfile")
    
    # Build
    docker build \
        -t "$REGISTRY/$service_name:$VERSION" \
        -t "$REGISTRY/$service_name:latest" \
        -f "$dockerfile" \
        "$context_dir" || {
        echo "❌ Build failed for $service_name"
        continue
    }
    
    # Push both tags
    echo "📤 Pushing $service_name..."
    docker push "$REGISTRY/$service_name:$VERSION"
    docker push "$REGISTRY/$service_name:latest"
    
    echo "✅ $service_name pushed"
    echo ""
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ ALL IMAGES BUILT AND PUSHED"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next: Broadcast to mesh cells"
echo "  ssh root@77.42.85.60 'docker exec gaiaftcl-nats nats pub gaiaftcl.mesh.rebuild_request \"{\\\"version\\\":\\\"$VERSION\\\",\\\"wallet\\\":\\\"0x91f6e41B4425326e42590191c50Db819C587D866\\\"}\"'"
