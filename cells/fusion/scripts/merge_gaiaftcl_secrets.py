#!/usr/bin/env python3
"""
Idempotent merge into /etc/gaiaftcl/secrets.env (mode 0600).
- Upserts CELL_ID, CELL_IP from environment when set.
- GAIAFTCL_INTERNAL_KEY: from env if non-empty; else keep file; else if MESH_HEAD_BOOTSTRAP=1, generate.
- Mirrors INTERNAL_KEY into GAIAFTCL_INTERNAL_SERVICE_KEY when service key absent (wallet-gate / adapters).
- Sets EARTH_INGESTOR=1 when CRYSTAL_EARTH_MOORING=1 (default).
- Non-head cells: sets MESH_HEARTBEAT_FEDERATION_URL to head :8803/mesh/heartbeat when absent;
  head (gaiaftcl-hcloud-hel1-01) clears that key to avoid a federation loop.
Does not print secret values.
"""
from __future__ import annotations

import os
import pathlib
import secrets
import sys


def _parse_env_file(text: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        if "=" not in s:
            continue
        k, _, v = s.partition("=")
        k = k.strip()
        if k:
            out[k] = v
    return out


def main() -> int:
    path = pathlib.Path(os.environ.get("GAIAFTCL_SECRETS_PATH", "/etc/gaiaftcl/secrets.env"))
    path.parent.mkdir(parents=True, exist_ok=True)

    raw = path.read_text(encoding="utf-8") if path.exists() else ""
    kv = _parse_env_file(raw)

    cell_id = os.environ.get("CELL_ID", "").strip()
    cell_ip = os.environ.get("CELL_IP", "").strip()
    key_env = os.environ.get("GAIAFTCL_INTERNAL_KEY", "").strip()
    head_bootstrap = os.environ.get("MESH_HEAD_BOOTSTRAP", "").strip() == "1"
    earth_mooring = os.environ.get("CRYSTAL_EARTH_MOORING", "1").strip() == "1"
    head_cell = "gaiaftcl-hcloud-hel1-01"
    mesh_head_ip = os.environ.get("MESH_HEAD_PUBLIC_IP", "77.42.85.60").strip()

    if cell_id:
        kv["CELL_ID"] = cell_id
    if cell_ip:
        kv["CELL_IP"] = cell_ip

    # Head must not federate to itself (loop). Workers POST heartbeats to head :8803/mesh/heartbeat.
    if cell_id == head_cell:
        kv.pop("MESH_HEARTBEAT_FEDERATION_URL", None)
    elif cell_id and "MESH_HEARTBEAT_FEDERATION_URL" not in kv:
        kv["MESH_HEARTBEAT_FEDERATION_URL"] = f"http://{mesh_head_ip}:8803/mesh/heartbeat"

    if key_env:
        kv["GAIAFTCL_INTERNAL_KEY"] = key_env
    else:
        cur = (kv.get("GAIAFTCL_INTERNAL_KEY") or "").strip()
        if not cur and head_bootstrap:
            kv["GAIAFTCL_INTERNAL_KEY"] = secrets.token_hex(32)

    ik = (kv.get("GAIAFTCL_INTERNAL_KEY") or "").strip()
    sk = (kv.get("GAIAFTCL_INTERNAL_SERVICE_KEY") or "").strip()
    if ik and not sk:
        kv["GAIAFTCL_INTERNAL_SERVICE_KEY"] = ik

    if earth_mooring:
        kv["EARTH_INGESTOR"] = "1"

    # Stable key order for readability; then any other keys from original file
    preferred = [
        "CELL_ID",
        "CELL_IP",
        "GAIAFTCL_INTERNAL_KEY",
        "GAIAFTCL_INTERNAL_SERVICE_KEY",
        "MESH_HEARTBEAT_FEDERATION_URL",
        "EARTH_INGESTOR",
    ]
    ordered: list[tuple[str, str]] = []
    seen: set[str] = set()
    for k in preferred:
        if k in kv:
            ordered.append((k, kv[k]))
            seen.add(k)
    for k in sorted(kv.keys()):
        if k not in seen:
            ordered.append((k, kv[k]))

    lines = [f"{k}={v}" for k, v in ordered]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    path.chmod(0o600)
    return 0


if __name__ == "__main__":
    sys.exit(main())
