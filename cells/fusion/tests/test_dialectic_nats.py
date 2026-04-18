"""
test_dialectic_nats: G_FREESTYLE_L0 cell reset.
Dialectic moved to Rust/TTL. Reflection game is thin adapter: invoke substrate, store envelope.
"""
import pytest
import sys
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "services", "life_game"))


@pytest.mark.asyncio
async def test_shape_essay_minimal_passthrough():
    """shape_essay_from_substrate uses narrative from substrate, no Python conversation logic."""
    from franklin_reflection_game import shape_essay_from_substrate

    # Substrate returns narrative
    out = await shape_essay_from_substrate("q", {"generated": True, "output": {"narrative": "Hello from substrate"}}, {})
    assert out == "Hello from substrate"

    # Substrate returns collection_stats - minimal format
    out = await shape_essay_from_substrate(
        "q",
        {"generated": True, "output": {"collection_stats": {"discovered_proteins": 100, "discovered_materials": 10}}},
        {},
    )
    assert "110" in out
    assert "discoveries" in out

    # No narrative - fallback
    out = await shape_essay_from_substrate("q", {"generated": False, "output": {}}, {})
    assert "Substrate unreachable" in out or "unreachable" in out.lower()
