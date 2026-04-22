#!/usr/bin/env python3
"""Validate franklin_bootstrap_receipt v0.1 / v0.2 (openssl verify for v0.2).
Superseded by Rust: `target/release/fo-franklin validate-bootstrap`. Kept for reference."""
from __future__ import annotations

import base64
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REQUIRED = (
    "schema",
    "ts_utc",
    "repo_root",
    "curve",
    "public_key_pem",
    "public_key_commitment_sha256",
    "private_key_storage",
    "pre_mother",
    "note",
)
SIG = (
    "ecdsa_sha256_signature_b64",
    "signing_canonical_body_sha256",
    "signed_at_utc",
)


def _commitment_ok(d: dict) -> list[str]:
    e: list[str] = []
    pub = d.get("public_key_pem")
    if not isinstance(pub, str) or not pub:
        e.append("public_key_pem invalid")
        return e
    want = hashlib.sha256(pub.encode("utf-8")).hexdigest()
    if d.get("public_key_commitment_sha256") != want:
        e.append("public_key_commitment_sha256 mismatch")
    com = d.get("public_key_commitment_sha256")
    if isinstance(com, str) and not re.fullmatch(r"[a-f0-9]{64}", com):
        e.append("public_key_commitment must be 64 hex chars")
    return e


def _validate_common(d: dict) -> list[str]:
    e: list[str] = []
    for k in REQUIRED:
        if k not in d:
            e.append(f"missing: {k}")
    if d.get("curve") != "secp256k1":
        e.append("curve must be secp256k1")
    e.extend(_commitment_ok(d))
    return e


def _canonical_v02(d: dict) -> bytes:
    o = {k: v for k, v in d.items() if k not in SIG}
    return json.dumps(o, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def _verify_v02(d: dict) -> list[str]:
    e: list[str] = []
    for k in SIG:
        if k not in d:
            e.append(f"v0.2 missing {k}")
            return e
    can = _canonical_v02(d)
    if hashlib.sha256(can).hexdigest() != d.get("signing_canonical_body_sha256"):
        e.append("signing_canonical_body_sha256 does not match canonical body")
        return e
    dig = hashlib.sha256(can).digest()
    try:
        sig = base64.b64decode(d["ecdsa_sha256_signature_b64"], validate=True)
    except (ValueError, TypeError) as ex:
        return [f"bad signature b64: {ex}"]
    pub = d.get("public_key_pem", "")
    hpath = spath = pp = None
    try:
        with tempfile.NamedTemporaryFile(delete=False) as th:
            th.write(dig)
            hpath = th.name
        with tempfile.NamedTemporaryFile(delete=False) as ts:
            ts.write(sig)
            spath = ts.name
        with tempfile.NamedTemporaryFile(suffix=".pem", delete=False) as pk:
            pk.write(pub.encode("utf-8") if isinstance(pub, str) else b"")
            pp = pk.name
        r = subprocess.run(
            ["openssl", "pkeyutl", "-verify", "-pubin", "-inkey", pp, "-in", hpath, "-sigfile", spath],
            capture_output=True,
        )
        if r.returncode != 0:
            e.append(f"openssl verify failed rc={r.returncode} {r.stderr.decode()[:200]}")
    finally:
        for p in (hpath, spath, pp):
            if p and os.path.isfile(p):
                try:
                    os.unlink(p)
                except OSError:
                    pass
    return e


def validate(d: dict) -> list[str]:
    sch = d.get("schema", "")
    if sch == "franklin_bootstrap_receipt_v0.1":
        e = _validate_common(d)
        if d.get("schema") != "franklin_bootstrap_receipt_v0.1":
            e.append("schema v0.1")
        return e
    if sch == "franklin_bootstrap_receipt_v0.2":
        e = _validate_common(d)
        e.extend(_verify_v02(d))
        return e
    return [f"unknown or missing schema: {sch!r}"]


def main() -> int:
    p = sys.argv[1] if len(sys.argv) > 1 else None
    if not p or p in ("-h", "--help"):
        print("usage: validate_franklin_bootstrap_receipt.py <file.json>", file=sys.stderr)
        return 2
    try:
        obj = json.loads(Path(p).read_text(encoding="utf-8"))
    except OSError as ex:
        print(ex, file=sys.stderr)
        return 1
    if not isinstance(obj, dict):
        print("root must be object", file=sys.stderr)
        return 1
    err = validate(obj)
    if err:
        for x in err:
            print(x, file=sys.stderr)
        return 1
    print("OK:", obj.get("schema"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
