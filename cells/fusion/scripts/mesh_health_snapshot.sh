#!/usr/bin/env bash
# Pass A mesh probes — external HTTP to nine cells (same IPs as deploy_crystal_nine_cells Netcup + Hetzner order).
# Run from any host with outbound TCP. Receipt: stdout only; exit 0 always unless set STRICT=1.
set -uo pipefail

STRICT="${STRICT:-0}"
CELLS=(
  "gaiaftcl-hcloud-hel1-01:77.42.85.60"
  "gaiaftcl-hcloud-hel1-02:135.181.88.134"
  "gaiaftcl-hcloud-hel1-03:77.42.32.156"
  "gaiaftcl-hcloud-hel1-04:77.42.88.110"
  "gaiaftcl-hcloud-hel1-05:37.27.7.9"
  "gaiaftcl-netcup-nbg1-01:37.120.187.247"
  "gaiaftcl-netcup-nbg1-02:152.53.91.220"
  "gaiaftcl-netcup-nbg1-03:152.53.88.141"
  "gaiaftcl-netcup-nbg1-04:37.120.187.174"
)

probe() {
  local name="$1" ip="$2" port="$3" path="$4"
  local code
  code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 8 "http://${ip}:${port}${path}" 2>/dev/null || echo "000")"
  printf "%s\t%s\t%d\t%s\t%s\n" "$name" "$ip" "$port" "$path" "$code"
}

echo "# mesh_health_snapshot $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo -e "# columns: cell\tip\tport\tpath\thttp_code"
echo "# 8803 = fot-mcp-gateway-mesh (or legacy path); 8807 = domain edge if exposed"
echo ""

FAIL=0
for entry in "${CELLS[@]}"; do
  name="${entry%%:*}"
  ip="${entry##*:}"
  probe "$name" "$ip" 8803 "/health"
  probe "$name" "$ip" 8807 "/health"
done

echo ""
echo "# claims without wallet (expect 400 on gated mesh)"
for entry in "${CELLS[@]}"; do
  name="${entry%%:*}"
  ip="${entry##*:}"
  code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 8 "http://${ip}:8803/claims?limit=1" 2>/dev/null || echo "000")"
  printf "%s\t%s\t8803\t/claims\t%s\n" "$name" "$ip" "$code"
  if [[ "$STRICT" == "1" && "$code" != "400" && "$code" != "401" && "$code" != "403" ]]; then
    FAIL=1
  fi
done

exit "$FAIL"
