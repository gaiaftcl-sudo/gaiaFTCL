#!/usr/bin/env bash
set -euo pipefail

# Verify MCP server is running on all 10 cells with latest code

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== VERIFYING ALL CELLS MCP STATUS ==="
echo "Repo root: $REPO_ROOT"
echo ""

# Load cell registry
CELL_REGISTRY="${REPO_ROOT}/ftcl/config/cell_registry.json"

if [ ! -f "$CELL_REGISTRY" ]; then
  echo "❌ Cell registry not found: $CELL_REGISTRY"
  exit 1
fi

# Extract all active cells
CELLS=$(jq -r '.cells | to_entries[] | .value[] | select(.status == "ACTIVE") | "\(.cell_id)|\(.ip)|\(.hostname)"' "$CELL_REGISTRY")

TOTAL=0
REACHABLE=0
MCP_RUNNING=0
NEEDS_UPDATE=()

echo "Checking cells..."
echo ""

while IFS='|' read -r CELL_ID IP HOSTNAME; do
  TOTAL=$((TOTAL + 1))
  
  printf "%-15s %-20s %-20s " "$CELL_ID" "$IP" "$HOSTNAME"
  
  # Skip local cell (different access method)
  if [ "$CELL_ID" = "mac-lima" ]; then
    echo "⏭️  SKIP (local)"
    continue
  fi
  
  # Check SSH reachability
  if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@${IP}" "echo ok" &>/dev/null; then
    echo "❌ UNREACHABLE"
    continue
  fi
  
  REACHABLE=$((REACHABLE + 1))
  
  # Check if MCP server is running
  if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@${IP}" \
    "docker ps --filter 'name=gaiaos_ui_tester_mcp' --format '{{.Status}}' | grep -q Up" 2>/dev/null; then
    
    MCP_RUNNING=$((MCP_RUNNING + 1))
    
    # Check if health endpoint responds
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@${IP}" \
      "curl -sS http://localhost:8850/health 2>/dev/null | grep -q healthy" 2>/dev/null; then
      echo "✅ HEALTHY"
    else
      echo "⚠️  RUNNING (health check failed)"
      NEEDS_UPDATE+=("$CELL_ID")
    fi
  else
    echo "❌ MCP NOT RUNNING"
    NEEDS_UPDATE+=("$CELL_ID")
  fi
  
done <<< "$CELLS"

echo ""
echo "=== SUMMARY ==="
echo "Total cells:      $TOTAL"
echo "Reachable:        $REACHABLE"
echo "MCP running:      $MCP_RUNNING"
echo ""

if [ ${#NEEDS_UPDATE[@]} -gt 0 ]; then
  echo "⚠️  Cells needing update:"
  for CELL in "${NEEDS_UPDATE[@]}"; do
    echo "  - $CELL"
  done
  echo ""
  echo "To update, run:"
  echo "  bash scripts/deploy_mcp_to_cell.sh <cell_id>"
  exit 1
else
  echo "✅ All reachable cells have MCP running"
  exit 0
fi
