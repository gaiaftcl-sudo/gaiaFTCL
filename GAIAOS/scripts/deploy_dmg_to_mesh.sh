#!/usr/bin/env bash
set -euo pipefail

GAIA_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$GAIA_ROOT"

# Override for non-default mesh operator key: DMG_DEPLOY_SSH_KEY=/path/to/id_ed25519
SSH_KEY="${DMG_DEPLOY_SSH_KEY:-$HOME/.ssh/qfot_unified}"
if [[ ! -f "$SSH_KEY" ]]; then
  echo "❌ SSH key not found: $SSH_KEY (set DMG_DEPLOY_SSH_KEY)"
  exit 1
fi

VERSION="${VERSION:-1.0.0}"
DMG_NAME="GaiaFTCL-${VERSION}.dmg"
DMG_PATH="$GAIA_ROOT/dist/$DMG_NAME"

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

echo "📤 Deploying GaiaFTCL DMG to mesh"
echo "SSH key: $SSH_KEY"
echo "Version: $VERSION"
echo "DMG: $DMG_NAME"
echo ""

# Verify DMG exists
if [ ! -f "$DMG_PATH" ]; then
    echo "❌ DMG not found: $DMG_PATH"
    echo "   Run ./scripts/build_gaiaftcl_facade_dmg.sh first"
    exit 1
fi

# Verify checksum exists
if [ ! -f "$DMG_PATH.sha256" ]; then
    echo "❌ Checksum not found: $DMG_PATH.sha256"
    exit 1
fi

CHECKSUM=$(cat "$DMG_PATH.sha256" | awk '{print $1}')
echo "🔐 Checksum: $CHECKSUM"
echo ""

# Deploy to all cells
for cell in "${CELLS[@]}"; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📡 Deploying to $cell"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Create downloads directory on cell
    ssh -i "$SSH_KEY" root@$cell "mkdir -p /var/www/gaiaftcl/public/downloads"
    
    # Transfer DMG
    echo "  Transferring DMG..."
    scp -i "$SSH_KEY" "$DMG_PATH" root@$cell:/var/www/gaiaftcl/public/downloads/
    
    # Transfer checksum
    scp -i "$SSH_KEY" "$DMG_PATH.sha256" root@$cell:/var/www/gaiaftcl/public/downloads/
    
    # Transfer version manifest
    scp -i "$SSH_KEY" "$GAIA_ROOT/dist/version.json" root@$cell:/var/www/gaiaftcl/public/downloads/
    
    # Create symlink to latest
    ssh -i "$SSH_KEY" root@$cell "cd /var/www/gaiaftcl/public/downloads && ln -sf $DMG_NAME GaiaFTCL-latest.dmg"
    
    # Verify deployment
    echo "  Verifying..."
    ssh -i "$SSH_KEY" root@$cell "ls -lh /var/www/gaiaftcl/public/downloads/$DMG_NAME"
    
    echo "✅ $cell complete"
    echo ""
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ DMG DEPLOYED TO ALL 9 CELLS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Download URLs:"
echo "  https://gaiaftcl.com/downloads/$DMG_NAME"
echo "  https://gaiaftcl.com/downloads/GaiaFTCL-latest.dmg"
echo "  https://gaiaftcl.com/dmgInstall"
echo ""
