"""
Gap 1: get_clarifying_response exists, is_ambiguous behavior.
"""
import pytest
import asyncio
import sys
import os

# Add gaiaos_substrate to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "services", "gaiaos_substrate"))


@pytest.mark.asyncio
async def test_get_clarifying_response_exists():
    from dialectic_engine import get_clarifying_response
    assert callable(get_clarifying_response)


@pytest.mark.asyncio
async def test_get_clarifying_response_returns_str_for_ambiguous():
    from dialectic_engine import get_clarifying_response
    result = await get_clarifying_response("this", context={})
    assert result is not None
    assert isinstance(result, str)
    assert len(result) > 0


@pytest.mark.asyncio
async def test_get_clarifying_response_returns_none_for_clear():
    from dialectic_engine import get_clarifying_response
    result = await get_clarifying_response("what is the mesh health?", context={})
    assert result is None


@pytest.mark.asyncio
async def test_is_ambiguous_this_true():
    from dialectic_engine import is_ambiguous
    result = await is_ambiguous("this", context={})
    assert result is True


@pytest.mark.asyncio
async def test_is_ambiguous_mesh_health_false():
    from dialectic_engine import is_ambiguous
    result = await is_ambiguous("what is the mesh health?", context={})
    assert result is False
