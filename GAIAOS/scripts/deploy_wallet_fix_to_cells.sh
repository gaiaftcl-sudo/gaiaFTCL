#!/usr/bin/env bash
set -euo pipefail

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

echo "🚀 DEPLOYING WALLET FIX TO ALL CELLS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Strategy: Update code files + restart containers"
echo "No rebuild needed - containers will pick up new code"
echo ""

for cell in "${CELLS[@]}"; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📡 Deploying to $cell"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    ssh -i ~/.ssh/qfot_unified root@$cell << 'ENDSSH'
# Pull latest code
cd /root/GAIAOS
git fetch origin
git reset --hard origin/fix/mesh-surgical-proof-v2 || git reset --hard origin/main

# Restart all services to pick up new wallet
docker compose -f docker-compose.cell.yml restart

echo "✅ Cell restarted with new wallet code"
ENDSSH
    
    echo "✅ $cell complete"
    echo ""
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ ALL 9 CELLS UPDATED"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "New wallet: 0x91f6e41B4425326e42590191c50Db819C587D866"
echo "Verification: Check ArangoDB on primary cell"
