#!/usr/bin/env bash
# Limb → nine sovereign cells: SSH BatchMode ring (no key path required; uses ssh default identities).
# IPs match mesh_health_snapshot / crystal deploy Netcup; Hetzner resolved via hcloud when available.
set -uo pipefail

STRICT="${STRICT:-0}"
FAIL=0

HETZNER_FALLBACK=(
  "77.42.85.60"
  "135.181.88.134"
  "77.42.32.156"
  "77.42.88.110"
  "37.27.7.9"
)
NETCUP_IPS=(
  "37.120.187.247"
  "152.53.91.220"
  "152.53.88.141"
  "37.120.187.174"
)

HETZNER_NAMES=(
  gaiaftcl-hcloud-hel1-01
  gaiaftcl-hcloud-hel1-02
  gaiaftcl-hcloud-hel1-03
  gaiaftcl-hcloud-hel1-04
  gaiaftcl-hcloud-hel1-05
)

ALL_IPS=()
if command -v hcloud >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  for c in "${HETZNER_NAMES[@]}"; do
    ip="$(hcloud server describe "$c" -o json 2>/dev/null | jq -r '.public_net.ipv4.ip // empty')"
    if [ -n "$ip" ] && [ "$ip" != "null" ]; then
      ALL_IPS+=("$ip")
    fi
  done
fi
if [ "${#ALL_IPS[@]}" -ne 5 ]; then
  ALL_IPS=("${HETZNER_FALLBACK[@]}")
fi
for ip in "${NETCUP_IPS[@]}"; do
  ALL_IPS+=("$ip")
done

HEAD_PUBLIC="${MESH_HEAD_IP:-77.42.85.60}"

echo "=== Mesh SSH ring (${#ALL_IPS[@]} cells) ==="
for ip in "${ALL_IPS[@]}"; do
  hn="$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 "root@${ip}" 'hostname' 2>/dev/null || true)"
  if [ -n "$hn" ]; then
    echo "  ✅ ${ip}  ${hn}"
  else
    echo "  ❌ ${ip}  SSH_FAILED"
    FAIL=1
  fi
done

echo "=== Head peer registry GET /peers (via SSH localhost:8821; WAN closed) ==="
PEER_JSON="$(ssh -o BatchMode=yes -o ConnectTimeout=15 "root@${HEAD_PUBLIC}" \
  'curl -sf --connect-timeout 8 http://127.0.0.1:8821/peers' 2>/dev/null || true)"
if [ -n "$PEER_JSON" ]; then
  n="$(echo "$PEER_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('peers', [])))")"
  echo "  peers_seen=${n}"
  if [ "${n:-0}" -ge 8 ]; then
    echo "  ✅ peer mesh warm (federated + local heartbeats visible on head)"
  elif [ "${n:-0}" -gt 0 ]; then
    echo "  ⚠️  partial peer mesh (expect ~9 after HTTP federation + NATS; check keys and MESH_HEARTBEAT_FEDERATION_URL)"
  else
    echo "  ⚠️  empty peer list (registry up; no heartbeats ingested)"
  fi
  if [ "${STRICT_PEERS:-0}" = "1" ] && [ "${n:-0}" -lt 8 ]; then
    echo "  ❌ STRICT_PEERS=1 requires peers_seen >= 8 (nine-cell mesh with one cell allowed down)"
    FAIL=1
  fi
else
  echo "  ❌ could not fetch /peers on head (registry down?)"
  FAIL=1
fi

echo "=== Nine-cell roster (registry self on each host via SSH; local NATS ⇒ peers[] empty is OK) ==="
ROSTER_OK=0
for ip in "${ALL_IPS[@]}"; do
  js="$(ssh -o BatchMode=yes -o ConnectTimeout=12 "root@${ip}" \
    'curl -sf --connect-timeout 6 http://127.0.0.1:8821/peers' 2>/dev/null || true)"
  if [ -z "$js" ]; then
    echo "  ❌ ${ip}  no /peers"
    FAIL=1
    continue
  fi
  cid="$(echo "$js" | python3 -c "import json,sys; d=json.load(sys.stdin); print((d.get('self') or {}).get('cell_id',''))")"
  rip="$(echo "$js" | python3 -c "import json,sys; d=json.load(sys.stdin); print((d.get('self') or {}).get('ip',''))")"
  if [ -n "$cid" ]; then
    echo "  ✅ ${ip}  cell_id=${cid}  ip=${rip}"
    ROSTER_OK=$((ROSTER_OK + 1))
  else
    echo "  ❌ ${ip}  missing self.cell_id"
    FAIL=1
  fi
done
if [ "$STRICT" = "1" ] && [ "$ROSTER_OK" -ne 9 ]; then
  echo "  ❌ STRICT: roster ${ROSTER_OK}/9"
  FAIL=1
fi

if [ "$STRICT" = "1" ] && [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
