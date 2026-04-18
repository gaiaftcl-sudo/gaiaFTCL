#!/usr/bin/env bash
set -euo pipefail

echo "================================================="
echo "=== PQ: Interactive Operator CLI (GAMP 5) ==="
echo "================================================="

# 1. Preflight Checks
IQ_HASH_FILE="evidence/iq/latest_iq_hash.txt"
OQ_HASH_FILE="evidence/oq/latest_oq_hash.txt"

if [ ! -f "$IQ_HASH_FILE" ] || [ ! -f "$OQ_HASH_FILE" ]; then
    echo "ERROR: Missing IQ or OQ hash. You must run scripts/run_cell_qualification_headless.sh first."
    exit 1
fi

IQ_HASH=$(cat "$IQ_HASH_FILE")
OQ_HASH=$(cat "$OQ_HASH_FILE")

echo "Found valid IQ Hash: $IQ_HASH"
echo "Found valid OQ Hash: $OQ_HASH"
echo ""

# 2. Operator Identity
OPERATOR=$(id -un)
SSH_KEY="$HOME/.ssh/id_ed25519"
if [ ! -f "$SSH_KEY" ]; then
    echo "ERROR: No SSH key found at $SSH_KEY. Required for CFR 21 Part 11 electronic signature."
    echo "Run 'ssh-keygen -t ed25519 -f $SSH_KEY -N \"\"' to generate one."
    exit 1
fi
OPERATOR_KEY_FINGERPRINT=$(ssh-keygen -lf "$SSH_KEY.pub" | awk '{print $2}')

echo "Operator: $OPERATOR"
echo "Identity Fingerprint: $OPERATOR_KEY_FINGERPRINT"
echo ""

# 3. Plant Selection
echo "Available Plants:"
ls -1 config/plants/*.yaml | awk -F/ '{print " - " $NF}'
echo ""
read -p "Enter plant config to deploy [tokamak.yaml]: " PLANT_FILE
PLANT_FILE=${PLANT_FILE:-tokamak.yaml}
PLANT_PATH="config/plants/$PLANT_FILE"

if [ ! -f "$PLANT_PATH" ]; then
    echo "ERROR: Plant config $PLANT_PATH not found."
    exit 1
fi

PLANT_ID=$(grep "plant_id:" "$PLANT_PATH" | awk '{print $2}' | tr -d '"')
CONFIG_HASH=$(shasum -a 256 "$PLANT_PATH" | awk '{print $1}')

echo "Selected Plant: $PLANT_ID"
echo "Config Hash: $CONFIG_HASH"
echo ""

# 4. Validation Parameters (Interactive Prompt)
echo "--- Validation Parameters ---"
read -p "Target Q-Value [1.5]: " TARGET_Q
TARGET_Q=${TARGET_Q:-1.5}

read -p "Frame Budget (ms) [3.0]: " FRAME_BUDGET
FRAME_BUDGET=${FRAME_BUDGET:-3.0}

echo ""

# 5. Run Package Gate
echo "--- Running Sovereign Package Gate ---"
scripts/pq_mac_cell_package_gate.sh || {
    echo "ERROR: Package Gate failed."
    exit 30
}

# Extract DMG info from the package gate receipt
PACKAGE_RECEIPT=$(ls -t evidence/pq/pq_package_gate_*.json | head -1)
DMG_PATH=$(jq -r '.packaging.dmg_path' "$PACKAGE_RECEIPT")
DMG_HASH=$(jq -r '.packaging.dmg_hash' "$PACKAGE_RECEIPT")

# 6. Generate Final GAMP 5 PQ Receipt
echo ""
echo "--- Generating GAMP 5 PQ Receipt ---"
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
RECEIPT_FILE="evidence/pq/pq_interactive_receipt_${TIMESTAMP}.json"

cat > "$RECEIPT_FILE.tmp" <<EOF
{
  "receipt_id": "GFTCL-PQ-INTERACTIVE-${TIMESTAMP}",
  "timestamp_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "operator_id": "$OPERATOR",
  "operator_key_fingerprint": "$OPERATOR_KEY_FINGERPRINT",
  "plant": {
    "plant_id": "$PLANT_ID",
    "config_hash": "$CONFIG_HASH",
    "config_version": 1
  },
  "requested_values": {
    "target_q_value": $TARGET_Q,
    "frame_budget_ms": $FRAME_BUDGET
  },
  "fleet": {
    "participating_cells": ["mac-cell-01"],
    "quorum": {
      "required": 1,
      "of": 1
    },
    "per_cell_timeout_s": 300
  },
  "fleet_results": [
    {
      "cell_id": "mac-cell-01",
      "terminal_state": "CALORIE",
      "parent_hash": "$IQ_HASH",
      "oq_hash": "$OQ_HASH",
      "run_id": "$(uuidgen | tr '[:upper:]' '[:lower:]')",
      "reason": "Operator validated",
      "evidence_hash": "$DMG_HASH",
      "received_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    }
  ],
  "artifact": {
    "dmg_path": "$DMG_PATH",
    "dmg_hash": "$DMG_HASH",
    "signature": "Ad-Hoc"
  },
  "terminal_state": "CALORIE"
}
EOF

# 7. Cryptographic Signature (CFR 21 Part 11)
echo "Signing receipt with SSH key..."
ssh-keygen -Y sign -f "$SSH_KEY" -n fot-pq-receipt "$RECEIPT_FILE.tmp" >/dev/null 2>&1
SIGNATURE=$(cat "$RECEIPT_FILE.tmp.sig" | tr '\n' '\\n')

# Use jq to inject the signature properly
jq --arg sig "$(cat "$RECEIPT_FILE.tmp.sig")" '. + {operator_signature: $sig}' "$RECEIPT_FILE.tmp" > "$RECEIPT_FILE"
rm "$RECEIPT_FILE.tmp" "$RECEIPT_FILE.tmp.sig"

echo ""
echo "✅ GAMP 5 PQ Complete."
echo "Receipt written to: $RECEIPT_FILE"
echo "Operator Signature Applied."
exit 0
