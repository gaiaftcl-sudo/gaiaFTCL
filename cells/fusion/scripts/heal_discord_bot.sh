#!/bin/bash
set -e

# Discord Bot Token Healing Script
# Usage: ./heal_discord_bot.sh <NEW_TOKEN>

if [ -z "$1" ]; then
    echo "❌ ERROR: Token required"
    echo "Usage: $0 <NEW_DISCORD_TOKEN>"
    exit 1
fi

NEW_TOKEN="$1"
CELL_IP="77.42.85.60"
SSH_KEY="$HOME/.ssh/ftclstack-unified"
CONTAINER_NAME="gaiaftcl-discord-membrane"

echo "=== DISCORD BOT HEALING PROTOCOL ==="
echo "Target: $CONTAINER_NAME @ $CELL_IP"
echo "Token: ${NEW_TOKEN:0:20}... (truncated)"
echo ""

echo "[1/4] Stopping container..."
ssh -i "$SSH_KEY" root@"$CELL_IP" "docker stop $CONTAINER_NAME"

echo "[2/4] Removing old container..."
ssh -i "$SSH_KEY" root@"$CELL_IP" "docker rm $CONTAINER_NAME"

echo "[3/4] Restarting with new token..."
ssh -i "$SSH_KEY" root@"$CELL_IP" "docker run -d \
    --name $CONTAINER_NAME \
    --network gaiaftcl-mesh \
    --restart unless-stopped \
    -e DISCORD_MEMBRANE_TOKEN='$NEW_TOKEN' \
    -e DISCORD_GUILD_ID=1487775674356990064 \
    -e NATS_URL=nats://gaiaftcl-nats:4222 \
    -e ARANGO_URL=http://gaiaftcl-arangodb:8529 \
    -e ARANGO_PASSWORD=gaiaftcl2026 \
    -e ARANGO_USER=root \
    -e ARANGO_DB=gaiaos \
    -e CELL_ID=gaiaftcl-discord-app-01 \
    -e CELL_IP=77.42.85.60 \
    -e HEAD_PUBLIC_IP=77.42.85.60 \
    -e DISCORD_EARTH_MESH_MONITOR=1 \
    -e DISCORD_MEMBRANE_DEPLOY=1 \
    -e DISCORD_EARTH_STALE_SEC=120 \
    discord-bot:latest"

echo "[4/4] Verifying connection (30s timeout)..."
sleep 5

for i in {1..6}; do
    echo "  Checking logs (attempt $i/6)..."
    LOGS=$(ssh -i "$SSH_KEY" root@"$CELL_IP" "docker logs $CONTAINER_NAME --tail 20" 2>&1)
    
    if echo "$LOGS" | grep -q "Logged in as"; then
        echo "✅ VERIFICATION SECURED: Bot is online and authenticated"
        echo ""
        echo "Bot Status:"
        echo "$LOGS" | grep "Logged in as"
        echo ""
        echo "=== SYSTEM HEALED ==="
        exit 0
    fi
    
    if echo "$LOGS" | grep -q "401"; then
        echo "❌ VERIFICATION FAILED: Still getting 401 Unauthorized"
        echo "Token may be invalid. Check Discord Developer Portal."
        exit 1
    fi
    
    sleep 5
done

echo "⚠️ VERIFICATION TIMEOUT: Bot may still be booting"
echo "Last 20 log lines:"
ssh -i "$SSH_KEY" root@"$CELL_IP" "docker logs $CONTAINER_NAME --tail 20"
exit 2
