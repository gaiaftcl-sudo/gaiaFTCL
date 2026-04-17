"""Governance codex: Mother Protocol, enrichment, constitution body shape."""

from __future__ import annotations


def test_constitution_body_has_mother_protocol_and_technical():
    from services.discord_frontier.shared.constitution import constitution_body

    doc = constitution_body()
    assert doc.get("version") == 1
    assert "origin_cell" in doc
    mp = doc.get("mother_protocol")
    assert isinstance(mp, list) and len(mp) == 8
    assert all(isinstance(x, dict) and x.get("id") and x.get("title") for x in mp)
    inv = doc.get("invariants")
    assert isinstance(inv, list) and "mcp_is_law" in inv
    assert isinstance(doc.get("domain_resonance"), dict)


def test_enrich_constitution_kv_backfill():
    from services.discord_frontier.shared.constitution import enrich_constitution_document

    raw = {"version": 1, "invariants": ["x"], "domain_resonance": {}}
    out = enrich_constitution_document(raw)
    assert len(out.get("mother_protocol", [])) == 8


def test_enrich_preserves_existing_mother_protocol():
    from services.discord_frontier.shared.constitution import enrich_constitution_document

    mp = [{"id": "custom", "title": "T", "summary": "S"}]
    out = enrich_constitution_document({"mother_protocol": mp})
    assert out["mother_protocol"] == mp
