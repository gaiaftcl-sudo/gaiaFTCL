#!/usr/bin/env bash
#
# Deploy Founder Wallet System to All Mesh Cells
#
# This script:
# 1. Builds wallet_observer Docker image
# 2. Deploys to all 9 mesh cells
# 3. Seeds founder wallet in ArangoDB
# 4. Verifies deployment

set -euo pipefail

# Mesh cells
HETZNER_CELLS=(
    "77.42.85.60"      # hel1-01 (PRIMARY)
    "135.181.88.134"   # hel1-02
    "77.42.32.156"     # hel1-03
    "77.42.88.110"     # hel1-04
    "37.27.7.9"        # hel1-05
)

NETCUP_CELLS=(
    "37.120.187.247"   # nbg1-01
    "152.53.91.220"    # nbg1-02
    "152.53.88.141"    # nbg1-03
    "37.120.187.174"   # nbg1-04
)

ALL_CELLS=("${HETZNER_CELLS[@]}" "${NETCUP_CELLS[@]}")
SSH_KEY="~/.ssh/qfot_unified"
NEW_WALLET="0x91f6e41B4425326e42590191c50Db819C587D866"

echo "================================================================================"
echo "FOUNDER WALLET SYSTEM DEPLOYMENT"
echo "================================================================================"
echo ""
echo "Deploying to ${#ALL_CELLS[@]} mesh cells"
echo "New founder wallet: $NEW_WALLET"
echo ""

# Step 1: Build wallet_observer image
echo "[1/4] Building wallet_observer Docker image..."
cd services/wallet_observer
docker build -t gaiaftcl/wallet_observer:latest .
echo "✓ Built wallet_observer image"
echo ""
cd ../..

# Step 2: Deploy to all cells
echo "[2/4] Deploying wallet_observer to all cells..."
for cell_ip in "${ALL_CELLS[@]}"; do
    echo "  Deploying to $cell_ip..."
    
    # Copy service files
    ssh -i $SSH_KEY root@$cell_ip "mkdir -p /root/cells/fusion/services/wallet_observer"
    scp -i $SSH_KEY services/wallet_observer/* root@$cell_ip:/root/cells/fusion/services/wallet_observer/
    
    # Build and run on cell
    ssh -i $SSH_KEY root@$cell_ip << 'ENDSSH'
cd /root/cells/fusion/services/wallet_observer
docker build -t gaiaftcl/wallet_observer:latest .
docker stop gaiaftcl-wallet-observer 2>/dev/null || true
docker rm gaiaftcl-wallet-observer 2>/dev/null || true
docker run -d \
    --name gaiaftcl-wallet-observer \
    --restart unless-stopped \
    --network gaiaftcl-net \
    -e NATS_URL="nats://gaiaftcl-nats:4222" \
    -e ARANGO_URL="http://gaiaftcl-arangodb:8529" \
    -e ARANGO_PASSWORD="gaiaftcl2026" \
    gaiaftcl/wallet_observer:latest
ENDSSH
    
    echo "  ✓ Deployed to $cell_ip"
done
echo ""

# Step 3: Seed founder wallet in ArangoDB (primary cell only)
echo "[3/4] Seeding founder wallet in ArangoDB..."
PRIMARY_CELL="${HETZNER_CELLS[0]}"
ssh -i $SSH_KEY root@$PRIMARY_CELL "cd /root/GAIAOS && FOUNDER_ADDRESS=$NEW_WALLET bash scripts/seed_founder_wallet_arangosh.sh"
echo "✓ Seeded founder wallet"
echo ""

# Step 4: Verify deployment
echo "[4/4] Verifying deployment..."
for cell_ip in "${ALL_CELLS[@]}"; do
    echo "  Checking $cell_ip..."
    ssh -i $SSH_KEY root@$cell_ip "docker ps | grep wallet-observer" || echo "  ⚠️  Not running on $cell_ip"
done
echo ""

echo "================================================================================"
echo "DEPLOYMENT COMPLETE"
echo "================================================================================"
echo ""
echo "Wallet Observer deployed to ${#ALL_CELLS[@]} cells"
echo "Founder wallet: $NEW_WALLET"
echo ""
echo "Next steps:"
echo "  1. Start wallet_signer on Mac: python3 services/wallet_signer/main.py"
echo "  2. Test signature flow: ./scripts/test_wallet_signature.sh"
echo "  3. Execute Discord mooring for gaiaftcl and uum8d"
echo ""
echo "To check logs:"
echo "  ssh -i $SSH_KEY root@$PRIMARY_CELL 'docker logs gaiaftcl-wallet-observer'"
echo ""
echo "================================================================================"
