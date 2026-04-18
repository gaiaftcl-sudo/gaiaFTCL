#!/usr/bin/env bash
# Nine-cell mesh witness: :8803/health, :8803/claims (expect 400), :8821/peers.
# Writes evidence/release/RELEASE_WITNESS_<UTC>.json when GAIAOS root is cwd or REPO_ROOT is set.
# ssh -n: required so ssh does not consume stdin when used with a heredoc or pipe.
set -uo pipefail
KEY="${SSH_IDENTITY_FILE:-$HOME/.ssh/ftclstack-unified}"
ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
ts="$(date -u +%Y%m%dT%H%M%SZ)"
out="$(mktemp)"
cleanup() { rm -f "$out"; }
trap cleanup EXIT

while read -r cell ip; do
  [ -z "${cell:-}" ] && continue
  h=$(ssh -n -o BatchMode=yes -o ConnectTimeout=18 -i "$KEY" "root@${ip}" \
    'curl -sf -m 6 http://127.0.0.1:8803/health >/dev/null && echo YES || echo NO')
  c=$(ssh -n -o BatchMode=yes -i "$KEY" "root@${ip}" \
    "curl -s -o /dev/null -m 6 -w '%{http_code}' http://127.0.0.1:8803/claims 2>/dev/null | tr -d '\r'")
  p=$(ssh -n -o BatchMode=yes -i "$KEY" "root@${ip}" \
    'curl -sf -m 6 http://127.0.0.1:8821/peers >/dev/null && echo YES || echo NO')
  if [ "$c" = "400" ]; then cg=YES; else cg=NO; fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$cell" "$ip" "$h" "$cg" "$p" >>"$out"
  printf '%s\t%s\t%s\t%s\t%s\n' "$cell" "$ip" "$h" "$cg" "$p"
done <<'ROWS'
gaiaftcl-hcloud-hel1-01 77.42.85.60
gaiaftcl-hcloud-hel1-02 135.181.88.134
gaiaftcl-hcloud-hel1-03 77.42.32.156
gaiaftcl-hcloud-hel1-04 77.42.88.110
gaiaftcl-hcloud-hel1-05 37.27.7.9
gaiaftcl-netcup-nbg1-01 37.120.187.247
gaiaftcl-netcup-nbg1-02 152.53.91.220
gaiaftcl-netcup-nbg1-03 152.53.88.141
gaiaftcl-netcup-nbg1-04 37.120.187.174
ROWS

python3 <<PY
import json
from pathlib import Path

ts = "${ts}"
out = Path("${out}")
rows = []
for line in out.read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if not line:
        continue
    parts = line.split("\t")
    if len(parts) >= 5:
        rows.append({
            "cell_id": parts[0],
            "ip": parts[1],
            "health_8803": parts[2],
            "claims_gate_400": parts[3],
            "peers_8821": parts[4],
        })
all_green = len(rows) == 9 and all(
    r["health_8803"] == "YES" and r["claims_gate_400"] == "YES" and r["peers_8821"] == "YES"
    for r in rows
)
doc = {
    "witness_ts_utc": ts,
    "matrix": rows,
    "all_nine_green": all_green,
    "row_count": len(rows),
    "head_discord_core_lane": "gaiaftcl-discord-membrane + discord-frontier-mother (constitution KV)",
    "discord_forest_full_fleet": "enable DISCORD_FOREST_FULL_DEPLOY=1 after all DISCORD_BOT_TOKEN_* in /etc/gaiaftcl/discord-forest.env",
}
ev = Path("${ROOT}") / "evidence" / "release"
ev.mkdir(parents=True, exist_ok=True)
path = ev / f"RELEASE_WITNESS_{ts}.json"
path.write_text(json.dumps(doc, indent=2), encoding="utf-8")
print(path)
raise SystemExit(0 if all_green else 1)
PY
