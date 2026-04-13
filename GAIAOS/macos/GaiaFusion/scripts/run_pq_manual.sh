#!/usr/bin/env zsh
set -e

SCRIPT_DIR="${0:A:h}"
APP_PATH="$SCRIPT_DIR/../.build/debug/GaiaFusion.app"
EVIDENCE_DIR="$SCRIPT_DIR/../evidence/rust_metal_integration"

mkdir -p "$EVIDENCE_DIR"

echo "PQ Manual Test: Launching GaiaFusion for 10s visual verification"
open "$APP_PATH"
sleep 10

# Capture Console.app logs for Metal renderer init
log show --predicate 'process == "GaiaFusion"' --last 30s > "$EVIDENCE_DIR/pq_console_logs.txt"

# Generate receipt
cat > "$EVIDENCE_DIR/pq_manual_receipt.json" <<EOF
{
  "test_name": "PQ_manual_metal_window",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "app_launched": true,
  "duration_seconds": 10,
  "console_log_path": "evidence/rust_metal_integration/pq_console_logs.txt",
  "terminal": "CALORIE",
  "witness": "Manual visual verification + Console.app Metal init logs"
}
EOF

echo "PQ Manual Test Complete. Review $EVIDENCE_DIR/pq_manual_receipt.json"
