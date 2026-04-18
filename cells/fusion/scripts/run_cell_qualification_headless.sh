#!/usr/bin/env bash
set -euo pipefail

echo "================================================="
echo "=== Headless Mac Cell Exploitation Pipeline ==="
echo "================================================="
echo "Starting Sovereign Loop..."

# Ensure scripts are executable
chmod +x scripts/iq_mac_cell_hardware_lock.sh
chmod +x scripts/oq_mac_cell_physics_gate.sh
chmod +x scripts/pq_mac_cell_package_gate.sh

# --- Phase 1: IQ ---
echo ""
echo ">>> Phase 1: IQ (Hardware Lock) <<<"
scripts/iq_mac_cell_hardware_lock.sh --standalone || {
    EXIT_CODE=$?
    echo "CRITICAL: IQ Phase Failed (Exit Code: $EXIT_CODE)"
    exit 10
}

# --- Phase 2: OQ ---
echo ""
echo ">>> Phase 2: OQ (Physics & Patent Gate) <<<"
scripts/oq_mac_cell_physics_gate.sh || {
    EXIT_CODE=$?
    echo "CRITICAL: OQ Phase Failed (Exit Code: $EXIT_CODE)"
    exit 20
}

# --- Phase 3: PQ ---
# Removed from headless loop. PQ is now interactive.
# Run scripts/run_cell_pq_interactive.sh to complete the GAMP 5 cycle.

echo ""
echo "================================================="
echo "=== Pipeline Complete: 100% Field of Truth ==="
echo "================================================="
exit 0
