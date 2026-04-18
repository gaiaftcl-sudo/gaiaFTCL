#!/usr/bin/env python3
"""
Forge NATS user seeds + membrane passports for each game_room in game_room_registry.json.

Outputs (under --out-dir, default suitable for copying to /etc/gaiaftcl/secrets/):
  - cells/<registry_id>.seed     one-line NATS user seed (SU...) for nkeys_seed / signing
  - nats_cell_passports.json     public NKey + reply_verify_key_b64 for membrane Proxy Guard
  - nats_cell_users.fragment.conf  paste fragment for nats-server authorization (nkey + permissions)
  - README_NSC.md                how to produce full operator-signed .creds via nsc

Full JWT+.creds chains require an Operator/Account (``nsc``). This script generates the NKey
material and Ed25519 verify keys used for application-layer reply signatures.
"""

from __future__ import annotations

import argparse
import base64
import json
import sys
from pathlib import Path

# discord_frontier on path for shared.cell_subjects
_DF = Path(__file__).resolve().parent.parent / "services" / "discord_frontier"
sys.path.insert(0, str(_DF))

import nacl.signing  # noqa: E402
from nkeys import PREFIX_BYTE_USER, encode_seed, from_seed  # noqa: E402

from shared.cell_subjects import membrane_cell_subject  # noqa: E402


def _load_registry(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> int:
    ap = argparse.ArgumentParser(description="Forge NKey seeds + passports for membrane cells")
    ap.add_argument(
        "--registry",
        type=Path,
        default=_DF / "game_room_registry.json",
        help="Path to game_room_registry.json",
    )
    ap.add_argument(
        "--out-dir",
        type=Path,
        default=_DF.parent.parent / "evidence" / "nats_cell_forge",
        help="Output directory (e.g. /etc/gaiaftcl/secrets)",
    )
    args = ap.parse_args()

    reg = _load_registry(args.registry)
    entries = reg.get("entries") or []
    cells_dir = args.out_dir / "cells"
    cells_dir.mkdir(parents=True, exist_ok=True)

    passports: dict[str, dict] = {}
    user_blocks: list[str] = []

    for e in entries:
        if e.get("kind") != "game_room":
            continue
        if e.get("enabled") is False:
            continue
        dk = str(e.get("domain_key") or "").strip()
        rid = str(e.get("id") or dk).strip()
        if not dk:
            continue

        subj = membrane_cell_subject(dk)
        sk = nacl.signing.SigningKey.generate()
        raw32 = sk.encode()
        nk_seed = encode_seed(raw32, PREFIX_BYTE_USER)
        seed_line = nk_seed.decode("ascii") if isinstance(nk_seed, bytes) else str(nk_seed)

        kp = from_seed(bytearray(nk_seed))
        pub_nk = kp.public_key.decode("ascii") if isinstance(kp.public_key, bytes) else str(kp.public_key)
        kp.wipe()

        vk_b64 = base64.b64encode(bytes(sk.verify_key)).decode("ascii")

        seed_path = cells_dir / f"{rid}.seed"
        seed_path.write_text(seed_line + "\n", encoding="utf-8")
        seed_path.chmod(0o600)

        dom_key = dk.lower()
        passports[dom_key] = {
            "registry_id": rid,
            "domain_key": dk,
            "request_subject": subj,
            "public_nkey": pub_nk,
            "reply_verify_key_b64": vk_b64,
            "seed_filename": f"cells/{rid}.seed",
        }

        user_blocks.append(
            "\n".join(
                [
                    "    {",
                    f"      nkey: {pub_nk}",
                    "      permissions {",
                    f'        subscribe: "{subj}"',
                    '        publish: "_INBOX.>"',
                    "      }",
                    "    }",
                ]
            )
        )

    conf_body = (
        "# Paste into nats-server.conf (adjust for your server version).\n"
        "authorization {\n"
        "  users = [\n"
        + ",\n".join(user_blocks)
        + "\n  ]\n"
        "}\n"
    )

    doc = {
        "version": 1,
        "subject_prefix": "gaiaftcl.cell",
        "cells": passports,
    }
    args.out_dir.mkdir(parents=True, exist_ok=True)
    (args.out_dir / "nats_cell_passports.json").write_text(
        json.dumps(doc, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    (args.out_dir / "nats_cell_users.fragment.conf").write_text(conf_body, encoding="utf-8")
    nsc_readme = """# Operator-signed .creds (production)

The `.seed` files are sufficient for `nats.connect(nkeys_seed=...)` and for signing membrane replies.

A full **NATS USER JWT** `.creds` file (JWT + NKey) must be issued by your Operator/Account, e.g.:

```bash
export NSC_HOME=/path/to/nsc/store
nsc add account -n gaia-cells
nsc add user -a gaia-cells -n cell-law \\
  --allow-sub 'gaiaftcl.cell.law' \\
  --allow-pub '_INBOX.>'
nsc generate creds -a gaia-cells -n cell-law -o /etc/gaiaftcl/secrets/cells/law.creds
```

Align `--allow-sub` with each row's `request_subject` in `nats_cell_passports.json`.
Mount the generated `.creds` and set `NATS_CREDS_FILE` / `user_credentials` on workers and the membrane.
"""
    (args.out_dir / "README_NSC.md").write_text(nsc_readme, encoding="utf-8")

    print(f"Wrote {len(passports)} cell seeds under {cells_dir}")
    print(f"Passports: {args.out_dir / 'nats_cell_passports.json'}")
    print(f"Server fragment: {args.out_dir / 'nats_cell_users.fragment.conf'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
