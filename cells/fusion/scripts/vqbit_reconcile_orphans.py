#!/usr/bin/env python3
"""
Orphan vQbit reconciliation — dry-run only (no writes).

Prints a sample of documents missing envelope_id/game_id/agent_id and a suggested
AQL template for human-reviewed batch linkage. Run against Arango when reachable:

  ARANGO_URL=http://127.0.0.1:8529 ARANGO_DB=gaiaos ARANGO_PASSWORD=... \\
    python3 scripts/vqbit_reconcile_orphans.py --limit 50

Exit 0 always if HTTP succeeds; 1 on connection/auth failure.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request


def _post_json(url: str, user: str, password: str, payload: dict) -> tuple[int, dict]:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, method="POST", headers={"Content-Type": "application/json"})
    cred = urllib.request.HTTPPasswordMgrWithDefaultRealm()
    cred.add_password(None, url.split("/_db")[0], user, password)
    opener = urllib.request.build_opener(urllib.request.HTTPBasicAuthHandler(cred))
    try:
        with opener.open(req, timeout=45) as resp:
            body = json.loads(resp.read().decode("utf-8"))
            return resp.status, body
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode("utf-8", errors="replace")[:800]}
    except urllib.error.URLError as e:
        return -1, {"error": str(e.reason)}


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--limit", type=int, default=30)
    args = p.parse_args()

    base = os.environ.get("ARANGO_URL", "http://127.0.0.1:8529").rstrip("/")
    db = os.environ.get("ARANGO_DB", "gaiaos")
    user = os.environ.get("ARANGO_USER", "root")
    password = os.environ.get("ARANGO_PASSWORD", "gaiaftcl2026")
    coll = os.environ.get("VQBIT_MEASUREMENTS_COLLECTION", "vqbit_measurements")

    url = f"{base}/_db/{db}/_api/cursor"
    aql_orphans = f"""
    FOR v IN {coll}
      FILTER v.envelope_id == null OR v.game_id == null OR v.agent_id == null
      SORT v.timestamp DESC
      LIMIT @lim
      RETURN {{ _key: v._key, timestamp: v.timestamp, domain: v.domain, cell_origin: v.cell_origin,
                envelope_id: v.envelope_id, game_id: v.game_id, agent_id: v.agent_id }}
    """
    code, body = _post_json(url, user, password, {"query": aql_orphans, "bindVars": {"lim": args.limit}})
    out = {
        "receipt": "vqbit_reconcile_orphans_dry_run",
        "arango": base,
        "database": db,
        "http_status": code,
        "sample_orphans": body.get("result") if code in (200, 201) else None,
        "error": body.get("error") if code not in (200, 201) else None,
        "strategy_note": (
            "No automatic write. Next: join orphans to truth_envelopes by time/domain/wallet in reviewed AQL; "
            "or ingest path fix so new rows carry envelope_id. Apply UPDATE only after operator closure."
        ),
        "template_aql_comment": (
            "// Example pattern (do not run blind): match envelope by nearest created_at to v.timestamp "
            "// FOR v IN vqbit_measurements FILTER v.envelope_id == null LIMIT 1 "
            "// LET e = FIRST(FOR x IN truth_envelopes SORT ABS(DATE_DIFF(v.timestamp, x.created_at)) ASC RETURN x) "
            "// UPDATE v WITH { envelope_id: e._key, reconciled: true } IN vqbit_measurements"
        ),
    }
    print(json.dumps(out, indent=2))
    return 0 if code in (200, 201) else 1


if __name__ == "__main__":
    sys.exit(main())
