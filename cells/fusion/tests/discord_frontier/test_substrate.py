"""
Substrate integration against GAIAFTCL_GATEWAY (SSH tunnel default http://127.0.0.1:18803).
Match gateway GAIAFTCL_INTERNAL_KEY locally when that env is set on the server.
"""

from __future__ import annotations

import os
import time

import requests

GATEWAY = os.environ.get("GAIAFTCL_GATEWAY", "http://127.0.0.1:18803").rstrip("/")
INTERNAL_KEY = os.environ.get("GAIAFTCL_INTERNAL_KEY", "").strip()


def _ingest_headers() -> dict[str, str]:
    h: dict[str, str] = {}
    if INTERNAL_KEY:
        h["X-Gaiaftcl-Internal-Key"] = INTERNAL_KEY
    return h


def test_s1_universal_ingest_returns_claim_key():
    payload = {
        "type": "DISCORD_TEST",
        "from": "test_discord_user",
        "payload": {
            "game_room": "owl_protocol",
            "content": "substrate test message",
            "cell_id": "gaiaftcl-discord-bot-owl",
            "caller_id": "discord_test_suite",
            "envelope_status": "OPEN",
            "ttl": "24h",
        },
    }
    r = requests.post(
        f"{GATEWAY}/universal_ingest",
        json=payload,
        headers=_ingest_headers(),
        timeout=60,
    )
    assert r.status_code in (200, 201), r.text
    body = r.json()
    claim_key = body.get("_key") or body.get("key") or body.get("id") or body.get("claim_key")
    assert claim_key is not None, body


def test_s2_claims_filter_owl_protocol():
    time.sleep(2)
    r = requests.get(
        f"{GATEWAY}/claims",
        params={"filter": "owl_protocol", "limit": 5},
        timeout=60,
    )
    assert r.status_code == 200, r.text
    claims = r.json()
    assert any("owl_protocol" in str(c) for c in claims)


def test_s3_graph_stats():
    r = requests.get(f"{GATEWAY}/graph/stats", timeout=120)
    assert r.status_code == 200, r.text


def test_s4_unlicensed_wallet_blocked():
    r = requests.get(
        f"{GATEWAY}/discovery/AML-CHEM-001",
        headers={"X-Wallet-Address": "unknown_wallet"},
        timeout=60,
    )
    assert r.status_code in (400, 402, 403), r.text
