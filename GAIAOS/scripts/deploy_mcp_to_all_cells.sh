#!/usr/bin/env bash
set -euo pipefail

# Deploy latest MCP server (gaiaos_ui_tester_mcp) to all cells

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SSH_KEY="$HOME/.ssh/ftclstack-unified"

echo "=== DEPLOYING MCP TO ALL CELLS ===" echo ""
echo "Building MCP server locally first..."
cd "${REPO_ROOT}/services/gaiaos_ui_tester_mcp"

# Build release binary
if ! cargo build --release 2>&1 | tail -5; then
  echo "❌ Build failed"
  exit 1
fi

BINARY="${REPO_ROOT}/services/gaiaos_ui_tester_mcp/target/release/gaiaos_ui_tester_mcp"

if [ ! -f "$BINARY" ]; then
  echo "❌ Binary not found: $BINARY"
  exit 1
fi

echo "✅ Binary built: $(ls -lh $BINARY | awk '{print $5}')"
echo ""

# Deploy to each cell
CELLS=(
  "hel1-01:77.42.85.60"
  "hel1-02:135.181.88.134"
  "hel1-03:77.42.32.156"
  "hel1-04:77.42.88.110"
  "hel1-05:37.27.7.9"
  "nbg1-01:37.120.187.247"
  "nbg1-02:152.53.91.220"
  "nbg1-03:152.53.88.141"
  "nbg1-04:37.120.187.174"
)

SUCCESS=0
FAILED=0

for CELL in "${CELLS[@]}"; do
  CELL_ID="${CELL%%:*}"
  IP="${CELL##*:}"
  
  echo "Deploying to $CELL_ID ($IP)..."
  
  # Copy binary
  if ! scp -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
    "$BINARY" "root@${IP}:/usr/local/bin/gaiaos_ui_tester_mcp" 2>&1 | grep -v "Warning"; then
    echo "  ❌ Failed to copy binary"
    FAILED=$((FAILED + 1))
    continue
  fi
  
  # Stop old MCP if running
  ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@${IP}" \
    "docker stop gaiaos_ui_tester_mcp 2>/dev/null || true; docker rm gaiaos_ui_tester_mcp 2>/dev/null || true" 2>&1 | grep -v "Warning" || true
  
  # Create systemd service
  ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@${IP}" \
    "cat > /etc/systemd/system/gaiaos-ui-tester-mcp.service <<'EOF'
[Unit]
Description=GaiaOS UI Tester MCP Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gaiaos_ui_tester_mcp
Restart=always
RestartSec=10
WorkingDirectory=/var/www/gaiaftcl/GAIAOS
Environment=RUST_LOG=info

[Install]
WantedBy=multi-user.target
EOF
" 2>&1 | grep -v "Warning"
  
  # Reload systemd and start service
  if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@${IP}" \
    "systemctl daemon-reload && systemctl enable gaiaos-ui-tester-mcp && systemctl restart gaiaos-ui-tester-mcp" 2>&1 | grep -v "Warning"; then
    
    # Wait for health check
    sleep 3
    
    if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@${IP}" \
      "curl -sS http://localhost:8850/health 2>/dev/null | grep -q healthy" 2>/dev/null; then
      echo "  ✅ Deployed and healthy"
      SUCCESS=$((SUCCESS + 1))
    else
      echo "  ⚠️  Deployed but health check failed"
      FAILED=$((FAILED + 1))
    fi
  else
    echo "  ❌ Failed to start service"
    FAILED=$((FAILED + 1))
  fi
  
  echo ""
done

echo "=== DEPLOYMENT SUMMARY ==="
echo "Success: $SUCCESS"
echo "Failed:  $FAILED"
echo ""

if [ $FAILED -gt 0 ]; then
  exit 1
fi

echo "✅ All cells deployed successfully"
