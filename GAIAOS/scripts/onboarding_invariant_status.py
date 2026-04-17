#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path

import httpx


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def main() -> int:
    ap = argparse.ArgumentParser(description="Check/reset onboarding moor state for invariant testing.")
    ap.add_argument("--discord-user-id", required=True)
    ap.add_argument("--reset", action="store_true", help="If set, revoke mooring (force re-onboarding).")
    ap.add_argument("--reason", default="release_invariant_admin_reset")
    ap.add_argument("--repo-root", default=str(Path(__file__).resolve().parents[1]))
    args = ap.parse_args()

    arango_url = os.environ.get("ARANGO_URL", "http://127.0.0.1:8529").rstrip("/")
    arango_db = os.environ.get("ARANGO_DB", "gaiaos")
    arango_user = os.environ.get("ARANGO_USER", "root")
    arango_password = os.environ.get("ARANGO_PASSWORD", "")
    coll = os.environ.get("AUTHORIZED_WALLETS_COLLECTION", "authorized_wallets")
    did = str(args.discord_user_id).strip()
    key = f"moor_discord_{did}"[:254]

    cursor_url = f"{arango_url}/_db/{arango_db}/_api/cursor"
    doc_url = f"{arango_url}/_db/{arango_db}/_api/document/{coll}/{key}"

    aql = f"""
    FOR w IN {coll}
      FILTER (TO_STRING(w.discord_id) == @did OR TO_STRING(w.discord_user_id) == @did)
      LIMIT 1
      RETURN w
    """
    out: dict = {
        "schema": "onboarding_invariant_status_v1",
        "ts_utc": utc_now(),
        "discord_user_id": did,
        "reset_requested": bool(args.reset),
    }

    async def run() -> None:
        async with httpx.AsyncClient(timeout=20.0) as client:
            r = await client.post(
                cursor_url,
                json={"query": aql, "bindVars": {"did": did}},
                auth=(arango_user, arango_password),
            )
            rows = (r.json().get("result") if r.status_code == 200 else []) or []
            doc = rows[0] if rows else {}
            out["before"] = {
                "found": bool(doc),
                "status": doc.get("status"),
                "active": doc.get("active"),
                "wallet_address": doc.get("wallet_address") or doc.get("address"),
            }
            if args.reset and doc:
                patch = {
                    "active": False,
                    "status": "RE_AUDIT",
                    "mooring_revoked_at": utc_now(),
                    "mooring_revoked_reason": f"ONBOARDING_INVARIANT_RESET: {args.reason}",
                    "c2_consecutive_torsion": 0,
                }
                rp = await client.patch(doc_url, json=patch, auth=(arango_user, arango_password))
                out["reset_result"] = {"http_status": rp.status_code, "ok": rp.status_code in (200, 201, 202)}
            # after
            r2 = await client.post(
                cursor_url,
                json={"query": aql, "bindVars": {"did": did}},
                auth=(arango_user, arango_password),
            )
            rows2 = (r2.json().get("result") if r2.status_code == 200 else []) or []
            doc2 = rows2[0] if rows2 else {}
            out["after"] = {
                "found": bool(doc2),
                "status": doc2.get("status"),
                "active": doc2.get("active"),
                "wallet_address": doc2.get("wallet_address") or doc2.get("address"),
            }
            out["onboarding_required_now"] = not bool(doc2 and (doc2.get("active", True) and str(doc2.get("status") or "MOORED") == "MOORED"))

    import asyncio

    asyncio.run(run())

    repo = Path(args.repo_root)
    out_path = repo / "evidence" / "release" / "ONBOARDING_INVARIANT_STATUS.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
    print(out_path)
    print(json.dumps({"onboarding_required_now": out["onboarding_required_now"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
