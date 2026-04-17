#!/bin/bash
# Sync substrate tests to head cell and run full suite.
# Usage: ./scripts/run_substrate_on_cell.sh [cell_ip]
# Requires: rsync, ssh, ~/.ssh/ftclstack-unified (or SSH_KEY env)

set -e

CELL_IP="${1:-77.42.85.60}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/ftclstack-unified}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Syncing substrate tests to $CELL_IP..."
rsync -avz -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
  "$REPO_ROOT/tests/" "root@${CELL_IP}:/root/gaiaos/tests/"
rsync -avz -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
  "$REPO_ROOT/test_spawning_system.py" "root@${CELL_IP}:/root/gaiaos/"
rsync -avz -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
  "$REPO_ROOT/scripts/run_substrate_test_suite.sh" "root@${CELL_IP}:/root/gaiaos/scripts/"
rsync -avz -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
  "$REPO_ROOT/services/mailcow_bridge/tests/" "root@${CELL_IP}:/root/gaiaos/services/mailcow_bridge/tests/"
# Spawning scripts (Phase M tests check these)
for f in register_all_students.py claim_all_students.py deploy_students_to_cells.py; do
  [ -f "$REPO_ROOT/$f" ] && rsync -avz -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
    "$REPO_ROOT/$f" "root@${CELL_IP}:/root/gaiaos/"
done

echo ""
echo "Running substrate suite on cell..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "root@${CELL_IP}" \
  "cd /root/gaiaos && LOCAL=1 MCP_GATEWAY_URL=http://127.0.0.1:8803 bash scripts/run_substrate_test_suite.sh"
