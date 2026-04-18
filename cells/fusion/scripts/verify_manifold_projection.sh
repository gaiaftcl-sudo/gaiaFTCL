#!/bin/bash
# Verify M⁸ Manifold Projection - Discord Sovereign Membrane Validation

set -euo pipefail

DOMAIN="${1:-ALL}"
CELL_URL="${2:-gaiaftcl.com}"

echo "🌐 GaiaFTCL M⁸ Manifold Projection Verification"
echo "================================================"
echo "Domain: $DOMAIN"
echo "Cell URL: $CELL_URL"
echo ""

DOMAINS=(
    "quantum_closure:9001"
    "law:9002"
    "biology_cures:9003"
    "atc:9004"
    "chemistry:9005"
    "governance:9006"
    "crypto:9007"
    "energy:9008"
    "finance:9009"
    "logistics:9010"
    "robotics:9011"
    "telecom:9012"
    "climate:9013"
)

check_service() {
    local domain=$1
    local port=$2
    
    echo -n "  Checking $domain (port $port)... "
    
    if curl -s -o /dev/null -w "%{http_code}" "http://${CELL_URL}:${port}" | grep -q "200\|302"; then
        echo "✅ LIVE"
        return 0
    else
        echo "❌ DOWN"
        return 1
    fi
}

check_arango() {
    echo -n "  Checking ArangoDB... "
    if curl -s -o /dev/null -w "%{http_code}" "http://${CELL_URL}:8529/_api/version" | grep -q "200"; then
        echo "✅ LIVE"
        return 0
    else
        echo "❌ DOWN"
        return 1
    fi
}

check_nats() {
    echo -n "  Checking NATS... "
    if nc -z -w 2 "${CELL_URL}" 4222 2>/dev/null; then
        echo "✅ LIVE"
        return 0
    else
        echo "❌ DOWN"
        return 1
    fi
}

check_journey_tracker() {
    echo -n "  Checking Journey Tracker... "
    if docker ps | grep -q "discord-journey-tracker"; then
        echo "✅ RUNNING"
        return 0
    else
        echo "❌ NOT RUNNING"
        return 1
    fi
}

echo "📊 Infrastructure Status:"
check_arango
check_nats
check_journey_tracker
echo ""

echo "🎨 Streamlit Dashboard Status:"

TOTAL=0
LIVE=0

if [ "$DOMAIN" = "ALL" ]; then
    for entry in "${DOMAINS[@]}"; do
        IFS=':' read -r domain port <<< "$entry"
        TOTAL=$((TOTAL + 1))
        if check_service "$domain" "$port"; then
            LIVE=$((LIVE + 1))
        fi
    done
else
    for entry in "${DOMAINS[@]}"; do
        IFS=':' read -r domain port <<< "$entry"
        if [ "$domain" = "$DOMAIN" ]; then
            TOTAL=1
            if check_service "$domain" "$port"; then
                LIVE=1
            fi
            break
        fi
    done
fi

echo ""
echo "================================================"
echo "📈 Summary:"
echo "  Total Domains: $TOTAL"
echo "  Live Dashboards: $LIVE"
echo "  Down Dashboards: $((TOTAL - LIVE))"
echo ""

if [ "$LIVE" -eq "$TOTAL" ]; then
    echo "✅ ALL SYSTEMS GREEN - M⁸ Manifold Projection OPERATIONAL"
    echo ""
    echo "🎯 Terminal State: 201 (CREATED)"
    echo "The manifold is holding. Calories or Cures."
    echo "There is no third option."
    exit 0
else
    echo "⚠️  PARTIAL DEPLOYMENT - Some dashboards are down"
    echo "   Review logs and restart failed services"
    exit 1
fi
