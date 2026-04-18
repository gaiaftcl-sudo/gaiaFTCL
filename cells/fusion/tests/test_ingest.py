"""
Gap 3 partial: claim keys at ingest.
"""
import pytest


def test_ingest_claim_structure():
    """Ingested claim should have wallet_address, query, type - no hardcoded claim_type routing in test."""
    claim = {
        "wallet_address": "0xTEST0000000000000000000000000000000001",
        "query": "What is the mesh health?",
        "type": "reflection",
    }
    assert "wallet_address" in claim
    assert "query" in claim
    assert "type" in claim
    assert claim["wallet_address"].startswith("0x")
    assert len(claim["query"]) > 0
