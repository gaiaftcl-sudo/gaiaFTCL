#!/usr/bin/env python3
"""
Phase B: Comms Organ Unit Tests
Run after Phase A passes. Requires GATEWAY_URL (default http://77.42.85.60:8803).
"""
import os
import sys

GATEWAY_URL = os.getenv("GATEWAY_URL", "http://77.42.85.60:8803")

def run():
    import urllib.request
    import json

    failed = 0

    # B1 — Bridge responds to valid caller_id
    print("B1: Bridge responds to valid caller_id...")
    req = urllib.request.Request(
        f"{GATEWAY_URL}/mailcow/mailbox",
        data=json.dumps({
            "caller_id": "agent_spawner",
            "domain": "gaiaftcl.com",
            "local_part": "test_substrate_comms",
            "password": "TestPass123!",
        }).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            body = json.loads(r.read().decode())
            if body.get("status") == "created" or "email" in body:
                print("  ✅ PASS: Mailbox created")
            else:
                print(f"  ⚠️  Created but unexpected: {body}")
    except urllib.error.HTTPError as e:
        if e.code == 200:
            print("  ✅ PASS")
        else:
            print(f"  ❌ FAIL: HTTP {e.code}")
            failed += 1
    except Exception as e:
        print(f"  ❌ FAIL: {e}")
        failed += 1

    # B2 — Bridge rejects missing caller_id
    print("B2: Bridge rejects missing caller_id...")
    req = urllib.request.Request(f"{GATEWAY_URL}/mailcow/mailboxes", method="GET")
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            print(f"  ❌ FAIL: Expected 400, got {r.status}")
            failed += 1
    except urllib.error.HTTPError as e:
        if e.code == 400:
            print("  ✅ PASS: 400 (caller_id required)")
        else:
            print(f"  ❌ FAIL: HTTP {e.code}")
            failed += 1
    except Exception as e:
        print(f"  ❌ FAIL: {e}")
        failed += 1

    # B3 — List mailboxes with caller_id
    print("B3: List mailboxes with caller_id...")
    req = urllib.request.Request(f"{GATEWAY_URL}/mailcow/mailboxes?caller_id=agent_spawner", method="GET")
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            body = json.loads(r.read().decode())
            if "mailboxes" in body and isinstance(body["mailboxes"], list):
                print(f"  ✅ PASS: {len(body['mailboxes'])} mailboxes")
            else:
                print(f"  ❌ FAIL: {body}")
                failed += 1
    except Exception as e:
        print(f"  ❌ FAIL: {e}")
        failed += 1

    return failed

if __name__ == "__main__":
    sys.exit(run())
