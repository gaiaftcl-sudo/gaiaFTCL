#!/usr/bin/env python3
"""
F1: ECDSA (OpenSSL pkeyutl) over SHA-256 of UTF-8 canonical JSON (sorted keys, compact).
Adds v0.2 signature fields to a v0.1 bootstrap receipt.

Superseded by Rust: `target/release/fo-franklin sign-bootstrap`. Kept for reference.
"""
from __future__ import annotations

import base64
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

SIG_KEYS = (
    "ecdsa_sha256_signature_b64",
    "signing_canonical_body_sha256",
    "signed_at_utc",
)


def canonical_bytes_from_body(body: dict) -> bytes:
    o = {k: v for k, v in body.items() if k not in SIG_KEYS}
    return json.dumps(o, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def get_priv_pem_from_storage(storage: str, repo: Path) -> bytes:
    if storage.startswith("file|"):
        rel = storage.split("|", 1)[1]
        p = (repo / rel).resolve()
        if not p.is_file():
            print(f"REFUSED: no private key file {p}", file=sys.stderr)
            raise SystemExit(1)
        return p.read_bytes()
    if storage.startswith("keychain|"):
        rest = storage[len("keychain|") :]
        if "|" not in rest:
            print("bad keychain private_key_storage", file=sys.stderr)
            raise SystemExit(1)
        svc, acc = rest.split("|", 1)
        r = subprocess.run(
            ["security", "find-generic-password", "-s", svc, "-a", acc, "-w"],
            capture_output=True,
            text=True,
        )
        if r.returncode != 0:
            print(r.stderr, file=sys.stderr)
            raise SystemExit(1)
        return (r.stdout or "").encode("utf-8")
    print(f"unknown private_key_storage: {storage!r}", file=sys.stderr)
    raise SystemExit(1)


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: sign_franklin_bootstrap_receipt.py <receipt.json> [REPO_ROOT]", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    repo: Path
    if len(sys.argv) > 2:
        repo = Path(sys.argv[2]).resolve()
    else:
        repo = path.resolve()
        for _ in range(8):
            if (repo / "cells" / "franklin").is_dir():
                break
            p = repo.parent
            if p == repo:
                repo = path.resolve().parents[3]
                break
            repo = p

    d = json.loads(path.read_text(encoding="utf-8"))
    storage = d.get("private_key_storage", "")
    if not storage:
        print("no private_key_storage", file=sys.stderr)
        return 1
    body = {k: v for k, v in d.items() if k not in SIG_KEYS}
    can = canonical_bytes_from_body(body)
    dig = hashlib.sha256(can).digest()

    hpath = spath = kpath = None
    try:
        pem = get_priv_pem_from_storage(storage, repo)
        with tempfile.NamedTemporaryFile(delete=False) as th:
            th.write(dig)
            hpath = th.name
        with tempfile.NamedTemporaryFile(delete=False) as ts:
            spath = ts.name
        with tempfile.NamedTemporaryFile(suffix=".pem", delete=False) as kf:
            kf.write(pem)
            kpath = kf.name
        os.chmod(kpath, 0o600)
        proc = subprocess.run(
            [
                "openssl",
                "pkeyutl",
                "-sign",
                "-inkey",
                kpath,
                "-in",
                hpath,
                "-out",
                spath,
            ],
            capture_output=True,
        )
        if proc.returncode != 0:
            print(proc.stderr.decode(), file=sys.stderr)
            return 1
        sig = Path(spath).read_bytes()
    finally:
        for p in (hpath, spath, kpath):
            if p and os.path.isfile(p):
                try:
                    os.unlink(p)
                except OSError:
                    pass

    out = body.copy()
    out["schema"] = "franklin_bootstrap_receipt_v0.2"
    out["ecdsa_sha256_signature_b64"] = base64.b64encode(sig).decode("ascii")
    out["signing_canonical_body_sha256"] = hashlib.sha256(can).hexdigest()
    out["signed_at_utc"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H%M%SZ")
    base_note = d.get("note", "")
    out["note"] = base_note + " | signed: ECDSA(OpenSSL) over sha256(sorted canonical json)."

    path.write_text(json.dumps(out, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("signed", path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
