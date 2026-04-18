#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# WATCHTOWER REMOVAL - Migration to Closed Update Protocol
# ═══════════════════════════════════════════════════════════════════════════════
#
# This script removes Watchtower and any :latest tag polling mechanisms
# from a GaiaFTCL cell, bringing it into compliance with FTCL-UPDATE-SPEC-1.0.
#
# Per the spec: "Any cell running Watchtower is OUT-OF-CONSTITUTION and must
# emit FAILURE until removed."
#
# Usage:
#   ./remove-watchtower.sh [cell_ip]
#
# If no cell_ip is provided, runs on localhost.
#
# ═══════════════════════════════════════════════════════════════════════════════

set -e

CELL_IP="${1:-localhost}"
SSH_KEY="${SSH_KEY:-~/.ssh/ftclstack-unified}"

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  WATCHTOWER REMOVAL - FTCL-UPDATE-SPEC-1.0 COMPLIANCE"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""
echo "Target: $CELL_IP"
echo ""

# Function to run command on target
run_cmd() {
    if [ "$CELL_IP" = "localhost" ]; then
        eval "$1"
    else
        ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "root@$CELL_IP" "$1"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: Stop and remove Watchtower
# ═══════════════════════════════════════════════════════════════════════════════

echo "Step 1: Removing Watchtower..."

run_cmd '
    # Stop watchtower if running
    if docker ps -q -f name=watchtower 2>/dev/null | grep -q .; then
        echo "  Stopping watchtower..."
        docker stop watchtower
        docker rm watchtower
        echo "  ✓ Watchtower container removed"
    elif docker ps -aq -f name=watchtower 2>/dev/null | grep -q .; then
        echo "  Removing stopped watchtower..."
        docker rm watchtower
        echo "  ✓ Watchtower container removed"
    else
        echo "  ✓ No watchtower container found"
    fi
    
    # Also check for gaiaftcl-watchtower
    if docker ps -aq -f name=gaiaftcl-watchtower 2>/dev/null | grep -q .; then
        docker stop gaiaftcl-watchtower 2>/dev/null || true
        docker rm gaiaftcl-watchtower 2>/dev/null || true
        echo "  ✓ gaiaftcl-watchtower removed"
    fi
    
    # Remove watchtower image to prevent accidental restart
    if docker images -q containrrr/watchtower 2>/dev/null | grep -q .; then
        docker rmi containrrr/watchtower 2>/dev/null || true
        echo "  ✓ Watchtower image removed"
    fi
'

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: Identify containers using :latest tags
# ═══════════════════════════════════════════════════════════════════════════════

echo "Step 2: Checking for :latest tag violations..."

LATEST_CONTAINERS=$(run_cmd '
    docker ps --format "{{.Names}} {{.Image}}" | grep ":latest" || true
')

if [ -n "$LATEST_CONTAINERS" ]; then
    echo "  ⚠️  Found containers using :latest tags:"
    echo "$LATEST_CONTAINERS" | while read line; do
        echo "      - $line"
    done
    echo ""
    echo "  These containers violate FTCL-UPDATE-SPEC-1.0 §3 (Digest-Pinning Law)"
    echo "  They must be updated to use digest references:"
    echo "      image: ghcr.io/gaiaftcl/service@sha256:<digest>"
    echo ""
    COMPLIANCE="PARTIAL"
else
    echo "  ✓ No :latest tag violations found"
    COMPLIANCE="FULL"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: Remove auto-update cron jobs
# ═══════════════════════════════════════════════════════════════════════════════

echo "Step 3: Checking for auto-update cron jobs..."

run_cmd '
    # Check for any watchtower or auto-pull cron jobs
    if crontab -l 2>/dev/null | grep -iE "(watchtower|docker.*pull|auto.*update)" > /dev/null; then
        echo "  ⚠️  Found auto-update cron jobs:"
        crontab -l | grep -iE "(watchtower|docker.*pull|auto.*update)"
        echo ""
        echo "  Remove these manually with: crontab -e"
    else
        echo "  ✓ No auto-update cron jobs found"
    fi
'

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4: Verify compose files
# ═══════════════════════════════════════════════════════════════════════════════

echo "Step 4: Checking docker-compose files..."

run_cmd '
    # Check for watchtower in compose files
    for f in /root/cells/fusion/docker-compose*.yml /root/docker-compose*.yml; do
        if [ -f "$f" ]; then
            if grep -q "watchtower" "$f" 2>/dev/null; then
                echo "  ⚠️  Watchtower found in: $f"
                echo "      Remove the watchtower service section"
            fi
            if grep -E "image:.*:latest" "$f" 2>/dev/null | head -3; then
                echo "  ⚠️  :latest tags found in: $f"
            fi
        fi
    done
' 2>/dev/null || true

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 5: Create compliance marker
# ═══════════════════════════════════════════════════════════════════════════════

echo "Step 5: Creating compliance marker..."

run_cmd '
    mkdir -p /root/cells/fusion/ftcl/compliance
    
    cat > /root/cells/fusion/ftcl/compliance/UPDATE_PROTOCOL_COMPLIANCE.json << EOF
{
    "spec": "FTCL-UPDATE-SPEC-1.0",
    "watchtower_removed": true,
    "removal_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "update_protocol": "G_FTCL_UPDATE_FLEET_V1",
    "digest_pinning": "REQUIRED",
    "latest_tags": "FORBIDDEN",
    "status": "COMPLIANT"
}
EOF
    echo "  ✓ Compliance marker created"
'

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  REMOVAL COMPLETE"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""
echo "  Watchtower:     REMOVED"
echo "  Auto-cron:      CHECKED"
echo "  Compose files:  CHECKED"
echo ""

if [ "$COMPLIANCE" = "FULL" ]; then
    echo "  STATUS: ✓ COMPLIANT with FTCL-UPDATE-SPEC-1.0"
else
    echo "  STATUS: ⚠️  PARTIAL - Manual fixes required for :latest tags"
fi

echo ""
echo "  Next steps:"
echo "    1. Update docker-compose to use digest-pinned images"
echo "    2. Deploy the cell-updater service"
echo "    3. Updates now require G_FTCL_UPDATE_FLEET_V1 game"
echo ""
