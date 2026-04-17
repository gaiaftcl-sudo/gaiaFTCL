#!/usr/bin/env python3
"""
Run G_FREESTYLE_L0 axiom bulk audit on truth_envelopes.
Reports pass/fail counts for Axiom 1 (non-extractive) and Axiom 2 (Geodetic Floor).
"""
import os
import sys
import json

try:
    import httpx
except ImportError:
    print("pip install httpx", file=sys.stderr)
    sys.exit(1)

# Add parent for axiom_audit_aql
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from axiom_audit_aql import AXIOM1_BULK_ALL, AXIOM2_BULK_ALL, AXIOM3_BULK_ALL

ARANGO_URL = os.getenv("ARANGO_URL", "http://localhost:8529")
ARANGO_DB = os.getenv("ARANGO_DB", "gaiaos")
ARANGO_USER = os.getenv("ARANGO_USER", "root")
ARANGO_PASS = os.getenv("ARANGO_PASSWORD", "gaiaftcl2026")
SINCE = os.getenv("SINCE", "2025-01-01T00:00:00Z")


def run_aql(query: str, bind_vars: dict) -> list:
    resp = httpx.post(
        f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/cursor",
        auth=(ARANGO_USER, ARANGO_PASS),
        json={"query": query, "bindVars": bind_vars},
        timeout=60.0,
    )
    if resp.status_code not in (200, 201):
        print(f"AQL error: {resp.status_code} {resp.text[:200]}", file=sys.stderr)
        return []
    data = resp.json()
    if data.get("error"):
        print(f"AQL error: {data.get('errorMessage', data['error'])}", file=sys.stderr)
        return []
    return data.get("result", [])


def main():
    print("=== G_FREESTYLE_L0 Axiom Bulk Audit ===")
    print(f"ArangoDB: {ARANGO_URL}")
    print(f"Database: {ARANGO_DB}")
    print(f"Since: {SINCE}")
    print()

    # Axiom 1: Non-extractive
    print("--- Axiom 1: Non-extractive exchange of vQbits ---")
    a1 = run_aql(AXIOM1_BULK_ALL, {"since": SINCE})
    a1_total = len(a1)
    a1_pass = sum(1 for r in a1 if r.get("non_extractive"))
    a1_fail = a1_total - a1_pass
    print(f"Total: {a1_total} | Pass: {a1_pass} | Fail: {a1_fail}")
    print()

    # Axiom 2: Geodetic Floor
    print("--- Axiom 2: Geodetic Floor preserved ---")
    a2 = run_aql(AXIOM2_BULK_ALL, {"since": SINCE})
    a2_total = len(a2)
    a2_pass = sum(1 for r in a2 if r.get("geodetic_floor_ok"))
    a2_fail = a2_total - a2_pass
    print(f"Total: {a2_total} | Pass: {a2_pass} | Fail: {a2_fail}")
    print()

    # Axiom 3: Wallet anchoring
    print("--- Axiom 3: Wallet as topological anchor ---")
    a3 = run_aql(AXIOM3_BULK_ALL, {"since": SINCE})
    a3_total = len(a3)
    a3_pass = sum(1 for r in a3 if r.get("wallet_anchored"))
    a3_fail = a3_total - a3_pass
    print(f"Total: {a3_total} | Pass: {a3_pass} | Fail: {a3_fail}")
    print()

    print("=== Audit complete ===")
    return 0 if (a1_fail == 0 and a2_fail == 0 and a3_fail == 0) else 1


if __name__ == "__main__":
    sys.exit(main())
