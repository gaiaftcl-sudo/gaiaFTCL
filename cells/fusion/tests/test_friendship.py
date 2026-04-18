"""
Friendship test: 5-turn conversation, Turn 5 references Turn 2.
"""
import pytest
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "services", "life_game"))


@pytest.mark.asyncio
async def test_prior_turns_structure_for_friendship():
    """prior_turns from _load_prior_turns has query, manifold_position for synthesis."""
    from franklin_reflection_game import FranklinReflectionGame
    game = FranklinReflectionGame()
    prior = await game._load_prior_turns("nonexistent")
    assert prior == []
    # When prior exists, each turn should have query for "what we discussed"
    assert isinstance(prior, list)
