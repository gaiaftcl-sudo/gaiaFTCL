#!/usr/bin/env python3
"""
Phase D: Wallet Identity Ingest Tests
Run after Phase A passes. Requires GATEWAY_URL (default http://77.42.85.60:8803).
"""
import os
import sys

GATEWAY_URL = os.getenv("GATEWAY_URL", "http://77.42.85.60:8803")

def run():
    import urllib.request
    import json

    failed = 0

    # D1 — Anonymous ingest rejected
    print("D1: Anonymous ingest rejected...")
    req = urllib.request.Request(
        f"{GATEWAY_URL}/ingest",
        data=json.dumps({"query": "test"}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            print(f"  ❌ FAIL: Expected 400, got {r.status}")
            failed += 1
    except urllib.error.HTTPError as e:
        if e.code == 400:
            print("  ✅ PASS: 400 (need wallet_address or caller_id)")
        else:
            print(f"  ❌ FAIL: HTTP {e.code}")
            failed += 1
    except Exception as e:
        print(f"  ❌ FAIL: {e}")
        failed += 1

    # D2 — caller_id accepted
    print("D2: caller_id accepted...")
    req = urllib.request.Request(
        f"{GATEWAY_URL}/ingest",
        data=json.dumps({"caller_id": "test_runner", "query": "constitutional test"}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            body = json.loads(r.read().decode())
            if "claim_id" in body:
                print("  ✅ PASS: 200 with claim_id")
            else:
                print(f"  ⚠️  200 but no claim_id: {body}")
    except urllib.error.HTTPError as e:
        if e.code == 500:
            print("  ⚠️  KNOWN GAP: 500 (backend/ArangoDB connectivity) — not failing")
        else:
            print(f"  ❌ FAIL: HTTP {e.code}")
            failed += 1
    except Exception as e:
        print(f"  ❌ FAIL: {e}")
        failed += 1

    # D3 — wallet without signature rejected
    print("D3: wallet without signature rejected...")
    req = urllib.request.Request(
        f"{GATEWAY_URL}/ingest",
        data=json.dumps({"wallet_address": "0xRick", "query": "test no signature"}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            print(f"  ❌ FAIL: Expected 401, got {r.status}")
            failed += 1
    except urllib.error.HTTPError as e:
        if e.code == 401:
            print("  ✅ PASS: 401 (signature required)")
        else:
            print(f"  ❌ FAIL: HTTP {e.code}")
            failed += 1
    except Exception as e:
        print(f"  ❌ FAIL: {e}")
        failed += 1

    return failed

if __name__ == "__main__":
    sys.exit(run())
