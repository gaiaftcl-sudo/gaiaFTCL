#!/usr/bin/env bash
# Deploy crystal to Hetzner (hcloud) + Netcup (direct SSH).
set -uo pipefail
RSYNC_SRC="${RSYNC_SRC:-/Users/richardgillespie/Documents/FoT8D/GAIAOS/}"
EXCLUDES=(
  --exclude='node_modules'
  --exclude='.next'
  --exclude='target'
  --exclude='.git'
  --exclude='**/.git'
  --exclude='**/__pycache__'
  --exclude='.cursor'
  --exclude='evidence'
)
RESULT_FILE="${TMPDIR:-/tmp}/crystal_deploy_$$.tsv"
: >"$RESULT_FILE"

verify_cell() {
  local CELL="$1"
  local IP="$2"
  sleep 12
  local H=NO G=NO PE=NO
  if ssh -o BatchMode=yes -o ConnectTimeout=20 "root@${IP}" "curl -sf http://127.0.0.1:8803/health >/dev/null"; then
    H=YES
    echo "${CELL}_HEALTHY"
  else
    echo "${CELL}_FAILED_HEALTH"
    ssh -o BatchMode=yes "root@${IP}" "cd /opt/gaia/GAIAOS && docker compose -f docker-compose.cell.yml ps -a 2>&1; docker compose -f docker-compose.cell.yml logs --tail=40 2>&1" || true
  fi
  CODE="$(ssh -o BatchMode=yes "root@${IP}" "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8803/claims" 2>/dev/null | tr -d '[:space:]' || echo "000")"
  if [ "$CODE" = "400" ]; then
    G=YES
    echo "${CELL}_GATE_LIVE"
  else
    echo "${CELL}_GATE_FAILED code=${CODE}"
  fi
  if ssh -o BatchMode=yes "root@${IP}" "curl -sf http://127.0.0.1:8821/peers >/dev/null"; then
    PE=YES
    echo "${CELL}_PEERS_LIVE"
  else
    echo "${CELL}_PEERS_FAILED"
    ssh -o BatchMode=yes "root@${IP}" "docker logs gaiaftcl-mesh-peer-registry --tail=25 2>&1" || true
  fi
  printf '%s\t%s\t%s\t%s\n' "$CELL" "$H" "$G" "$PE" >>"$RESULT_FILE"
}

# Populated after gaiaftcl-hcloud-hel1-01 runs merge_gaiaftcl_secrets.py (head generates if missing).
MESH_INTERNAL_KEY=""

run_remote_deploy() {
  local IP="$1"
  local CELL="$2"
  local REMOTE
  if [ -n "${MESH_INTERNAL_KEY:-}" ]; then
    REMOTE="$(printf 'export GAIAFTCL_INTERNAL_KEY=%q CELL_ID=%q CELL_IP=%q && bash /opt/gaia/GAIAOS/scripts/crystal_remote_deploy.sh' "$MESH_INTERNAL_KEY" "$CELL" "$IP")"
  else
    REMOTE="$(printf 'export CELL_ID=%q CELL_IP=%q && bash /opt/gaia/GAIAOS/scripts/crystal_remote_deploy.sh' "$CELL" "$IP")"
  fi
  ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "root@${IP}" "$REMOTE"
}

HETZNER=(
  gaiaftcl-hcloud-hel1-01
  gaiaftcl-hcloud-hel1-02
  gaiaftcl-hcloud-hel1-03
  gaiaftcl-hcloud-hel1-04
  gaiaftcl-hcloud-hel1-05
)
NETCUP=(
  "gaiaftcl-netcup-nbg1-01:37.120.187.247"
  "gaiaftcl-netcup-nbg1-02:152.53.91.220"
  "gaiaftcl-netcup-nbg1-03:152.53.88.141"
  "gaiaftcl-netcup-nbg1-04:37.120.187.174"
)

for CELL in "${HETZNER[@]}"; do
  echo "========== $CELL (hcloud) =========="
  IP="$(hcloud server describe "$CELL" -o json | jq -r '.public_net.ipv4.ip')"
  echo "STEP1 IP=$IP"
  hcloud server ssh "$CELL" -- "mkdir -p /opt/gaia/GAIAOS"
  rsync -az --delete "${EXCLUDES[@]}" "$RSYNC_SRC" "root@${IP}:/opt/gaia/GAIAOS/" || { echo "RSYNC_FAILED $CELL"; echo -e "${CELL}\tNO\tNO\tNO" >>"$RESULT_FILE"; continue; }
  REMOTE_CMD=""
  if [ -n "${MESH_INTERNAL_KEY:-}" ]; then
    REMOTE_CMD="$(printf 'export GAIAFTCL_INTERNAL_KEY=%q CELL_ID=%q CELL_IP=%q && bash /opt/gaia/GAIAOS/scripts/crystal_remote_deploy.sh' "$MESH_INTERNAL_KEY" "$CELL" "$IP")"
  else
    REMOTE_CMD="$(printf 'export CELL_ID=%q CELL_IP=%q && bash /opt/gaia/GAIAOS/scripts/crystal_remote_deploy.sh' "$CELL" "$IP")"
  fi
  if ! hcloud server ssh "$CELL" -- "$REMOTE_CMD"; then
    echo "COMPOSE_FAILED $CELL"
  else
    if [ "$CELL" = "gaiaftcl-hcloud-hel1-01" ]; then
      MESH_INTERNAL_KEY="$(ssh -o BatchMode=yes -o ConnectTimeout=25 "root@${IP}" "grep '^GAIAFTCL_INTERNAL_KEY=' /etc/gaiaftcl/secrets.env 2>/dev/null | cut -d= -f2- | head -1" || true)"
    fi
  fi
  verify_cell "$CELL" "$IP"
done

for entry in "${NETCUP[@]}"; do
  CELL="${entry%%:*}"
  IP="${entry##*:}"
  echo "========== $CELL (ssh $IP) =========="
  ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "root@${IP}" "mkdir -p /opt/gaia/GAIAOS" || { echo "SSH_MKDIR_FAILED $CELL"; echo -e "${CELL}\tNO\tNO\tNO" >>"$RESULT_FILE"; continue; }
  rsync -az --delete "${EXCLUDES[@]}" "$RSYNC_SRC" "root@${IP}:/opt/gaia/GAIAOS/" || { echo "RSYNC_FAILED $CELL"; echo -e "${CELL}\tNO\tNO\tNO" >>"$RESULT_FILE"; continue; }
  if ! run_remote_deploy "$IP" "$CELL"; then
    echo "COMPOSE_FAILED $CELL"
  fi
  verify_cell "$CELL" "$IP"
done

echo ""
echo "| Cell | Healthy | Gate Live | Peers Live |"
echo "|------|---------|-----------|------------|"
while IFS= read -r line; do
  [ -z "$line" ] && continue
  c="$(echo "$line" | cut -f1)"
  h="$(echo "$line" | cut -f2)"
  g="$(echo "$line" | cut -f3)"
  p="$(echo "$line" | cut -f4)"
  printf "| %s | %s | %s | %s |\n" "$c" "$h" "$g" "$p"
done <"$RESULT_FILE"
rm -f "$RESULT_FILE"
