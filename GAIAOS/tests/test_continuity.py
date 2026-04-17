"""
Gap 7: prior turns loaded, same game_id across turns.
"""
import pytest
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "services", "life_game"))


@pytest.mark.asyncio
async def test_load_prior_turns_returns_list():
    """_load_prior_turns returns list of prior turns."""
    from franklin_reflection_game import FranklinReflectionGame
    game = FranklinReflectionGame()
    prior = await game._load_prior_turns("nonexistent_game_id_12345")
    assert isinstance(prior, list)
    assert prior == []


@pytest.mark.asyncio
async def test_turn_log_has_query_and_discovery_refs():
    """Turn log structure includes query and discovery_refs for continuity."""
    # Structural test: shape_truth_envelope and accumulate_turn_state produce correct shape
    from franklin_reflection_game import FranklinReflectionGame
    game = FranklinReflectionGame()
    envelope = await game.shape_truth_envelope(
        query="test query",
        reasoning={"output": {"manifold_position": [0.5] * 8, "entropy_delta": 0.5, "discovery_refs": []}},
        context={},
        wallet_address="0xTEST",
        game_id="test_game",
        turn_number=1,
    )
    assert "turn_log" in envelope
    assert len(envelope["turn_log"]) == 1
    assert envelope["turn_log"][0].get("query") == "test query"
    assert "discovery_refs" in envelope["turn_log"][0]
    assert "manifold_position" in envelope["turn_log"][0]
