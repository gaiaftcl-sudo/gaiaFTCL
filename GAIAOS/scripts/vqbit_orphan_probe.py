#!/usr/bin/env python3
"""
Read-only Arango probe: vqbit_measurements rows with null envelope linkage.
Receipt: prints JSON to stdout. Requires ARANGO_URL, ARANGO_DB, ARANGO_PASSWORD (or defaults matching compose).

  ARANGO_URL=http://127.0.0.1:8529 ARANGO_DB=gaiaos \\
    ARANGO_PASSWORD=... python3 scripts/vqbit_orphan_probe.py
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request


def main() -> int:
    base = os.environ.get("ARANGO_URL", "http://127.0.0.1:8529").rstrip("/")
    db = os.environ.get("ARANGO_DB", "gaiaos")
    user = os.environ.get("ARANGO_USER", "root")
    password = os.environ.get("ARANGO_PASSWORD", "gaiaftcl2026")
    coll = os.environ.get("VQBIT_MEASUREMENTS_COLLECTION", "vqbit_measurements")

    aql = f"""
    LET orphans = LENGTH(
      FOR v IN {coll}
        FILTER v.envelope_id == null OR v.game_id == null OR v.agent_id == null
        RETURN 1
    )
    LET total = LENGTH(FOR v IN {coll} RETURN 1)
    RETURN {{ collection: "{coll}", orphans, total, orphan_ratio: orphans / MAX([1, total]) }}
    """
    body = json.dumps({"query": aql}).encode("utf-8")
    url = f"{base}/_db/{db}/_api/cursor"
    req = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    cred = urllib.request.HTTPPasswordMgrWithDefaultRealm()
    cred.add_password(None, base, user, password)
    auth = urllib.request.HTTPBasicAuthHandler(cred)
    opener = urllib.request.build_opener(auth)
    try:
        with opener.open(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        print(json.dumps({"error": "http", "status": e.code, "body": e.read().decode("utf-8", errors="replace")[:500]}))
        return 1
    except urllib.error.URLError as e:
        print(json.dumps({"error": "url", "detail": str(e.reason)}))
        return 1

    data = json.loads(raw)
    result = data.get("result", [])
    out = {"receipt": "vqbit_orphan_probe", "arango": base, "database": db, "result": result[0] if result else None}
    print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
