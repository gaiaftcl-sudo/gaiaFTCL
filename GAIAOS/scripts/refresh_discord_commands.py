#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import subprocess
import textwrap


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--guild", required=True, help="Discord guild id")
    ap.add_argument("--head-ip", default="77.42.85.60")
    ap.add_argument("--ssh-key", default="")
    args = ap.parse_args()

    ssh_key = args.ssh_key or os.path.expanduser("~/.ssh/ftclstack-unified")

    remote = textwrap.dedent(
        """
        set -euo pipefail
        export DISCORD_GUILD_ID="__GUILD__"
        cd /opt/gaia/GAIAOS/services/discord_frontier
        docker compose --env-file /etc/gaiaftcl/discord-forest.env -f docker-compose.discord-forest.yml up -d discord-frontier-mother discord-bot-owl discord-bot-governance
        python3 - <<'PY'
import base64, json, os, pathlib
import httpx

env = {}
for p in ["/etc/gaiaftcl/discord-forest.env", "/etc/gaiaftcl/secrets.env"]:
    fp = pathlib.Path(p)
    if not fp.exists():
        continue
    for line in fp.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        val = v.strip()
        if (val.startswith('"') and val.endswith('"')) or (val.startswith("'") and val.endswith("'")):
            val = val[1:-1]
        env[k.strip()] = val

guild = os.environ["DISCORD_GUILD_ID"]
tokens = {
    "app": env.get("DISCORD_APP_BOT_TOKEN", ""),
    "owl": env.get("DISCORD_BOT_TOKEN_OWL", ""),
    "governance": env.get("DISCORD_BOT_TOKEN_GOVERNANCE", ""),
}

def app_id_from_token(tok: str) -> str:
    if not tok or "." not in tok:
        return ""
    first = tok.split(".", 1)[0]
    pad = "=" * (-len(first) % 4)
    try:
        return base64.urlsafe_b64decode((first + pad).encode()).decode()
    except Exception:
        return ""

def refresh(label: str, tok: str) -> None:
    app_id = app_id_from_token(tok)
    if not app_id:
        print(f"REFRESH_SKIP {label} missing_app_id")
        return
    headers = {"Authorization": f"Bot {tok}", "Content-Type": "application/json"}
    u_guild = f"https://discord.com/api/v10/applications/{app_id}/guilds/{guild}/commands"
    u_global = f"https://discord.com/api/v10/applications/{app_id}/commands"
    with httpx.Client(timeout=20.0) as c:
        r = c.get(u_guild, headers=headers)
        if r.status_code != 200:
            print(f"REFRESH_FAIL {label} GET {r.status_code}")
            return
        cmds = r.json()
        source = "guild"
        if isinstance(cmds, list) and len(cmds) == 0:
            rg = c.get(u_global, headers=headers)
            if rg.status_code == 200 and isinstance(rg.json(), list):
                cmds = rg.json()
                source = "global"
        cleaned = []
        if isinstance(cmds, list):
            allow = {
                "name",
                "type",
                "description",
                "options",
                "default_member_permissions",
                "dm_permission",
                "nsfw",
                "name_localizations",
                "description_localizations",
            }
            for cmd in cmds:
                if isinstance(cmd, dict):
                    cleaned.append({k: v for k, v in cmd.items() if k in allow})
        p = c.put(u_guild, headers=headers, json=cleaned)
        detail = ""
        if p.status_code >= 300:
            try:
                detail = str(p.json())[:500]
            except Exception:
                detail = p.text[:500]
        print(
            f"REFRESH {label} app_id={app_id} get={r.status_code} put={p.status_code} "
            f"count={len(cleaned)} source={source}"
        )
        if detail:
            print(f"REFRESH_DETAIL {label} {detail}")

for name, token in tokens.items():
    if token:
        refresh(name, token)
    else:
        print(f"REFRESH_SKIP {name} missing_token")
PY
        """
    ).strip().replace("__GUILD__", args.guild)

    cmd = [
        "ssh",
        "-n",
        "-o",
        "BatchMode=yes",
        "-i",
        ssh_key,
        f"root@{args.head_ip}",
        remote,
    ]
    proc = subprocess.run(cmd, text=True)
    return proc.returncode


if __name__ == "__main__":
    raise SystemExit(main())

