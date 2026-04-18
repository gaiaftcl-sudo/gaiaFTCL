#!/usr/bin/env bash
# Nine-cell WAN probe for invariant nineCellMeshGreenGate.
# Exit 0 iff every cell responds HTTP 2xx on :8803/health (MCP gateway surface).
# Same cell list as mesh_health_snapshot.sh / deploy_crystal_nine_cells.sh.
# Local Mac full-cell :8803 is probed separately (before this script) by verify_gaiafusion_working_app.sh / verify_gaiafusion_internal_surface_suite.sh + scripts/mcp_mac_cell_probe.py.
set -uo pipefail

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

ok=0
fail=0
for entry in "${CELLS[@]}"; do
  name="${entry%%:*}"
  ip="${entry##*:}"
  code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 6 --max-time 12 "http://${ip}:8803/health" 2>/dev/null || echo "000")"
  if [[ "$code" =~ ^2[0-9][0-9]$ ]]; then
    echo "OK	${name}	${ip}	8803	/health	${code}"
    ok=$((ok + 1))
  else
    echo "FAIL	${name}	${ip}	8803	/health	${code}"
    fail=$((fail + 1))
  fi
done

echo "# summary ok=${ok} fail=${fail} need_ok=9"
if [[ "$ok" -eq 9 && "$fail" -eq 0 ]]; then
  exit 0
fi
exit 1
