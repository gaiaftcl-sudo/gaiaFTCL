#!/usr/bin/env bash
set -euo pipefail

# Simple MCP deployment - copy binary and run as systemd service

SSH_KEY="$HOME/.ssh/ftclstack-unified"
BINARY="/Users/richardgillespie/Documents/FoT8D/cells/fusion/services/gaiaos_ui_tester_mcp/target/release/gaiaos_ui_tester_mcp"

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

for CELL in "${CELLS[@]}"; do
  CELL_ID="${CELL%%:*}"
  IP="${CELL##*:}"
  
  printf "%-10s " "$CELL_ID"
  
  # Copy binary
  scp -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
    "$BINARY" "root@${IP}:/usr/local/bin/gaiaos_ui_tester_mcp" 2>&1 | grep -v "Warning" >/dev/null || { echo "❌ COPY FAILED"; continue; }
  
  # Deploy systemd service
  ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@${IP}" bash <<'EOF' 2>&1 | grep -v "Warning" >/dev/null
chmod +x /usr/local/bin/gaiaos_ui_tester_mcp
mkdir -p /var/www/gaiaftcl/cells/fusion/evidence/{ui_expected,ui_contract,agent_census,domain_tubes,closure_game,echo,mcp_calls}

cat > /etc/systemd/system/gaiaos-ui-tester-mcp.service <<'SVC'
[Unit]
Description=GaiaOS UI Tester MCP
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gaiaos_ui_tester_mcp
Restart=always
WorkingDirectory=/var/www/gaiaftcl/GAIAOS
Environment=RUST_LOG=info

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable gaiaos-ui-tester-mcp
systemctl restart gaiaos-ui-tester-mcp
sleep 2
curl -sS http://localhost:8850/health 2>/dev/null | grep -q healthy
EOF
  
  [ $? -eq 0 ] && echo "✅ HEALTHY" || echo "❌ FAILED"
done
