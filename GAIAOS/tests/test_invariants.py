"""
Phase 4: Invariant tests (run every CI).
"""
import subprocess
import pytest
import sys
import os


def test_no_claim_type_investor_bypass():
    """No if claim_type in ['investor', ...] in codebase."""
    root = os.path.join(os.path.dirname(__file__), "..", "services")
    result = subprocess.run(
        ["rg", "claim_type in \\[\"investor\"", "--glob", "!*.md", "--glob", "!*archive*", root],
        capture_output=True,
        text=True,
    )
    if result.returncode == 0 and result.stdout.strip():
        pytest.fail(f"claim_type investor bypass found: {result.stdout.strip()}")


@pytest.mark.asyncio
async def test_get_clarifying_response_callable():
    """get_clarifying_response is callable and returns str."""
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "services", "gaiaos_substrate"))
    from dialectic_engine import get_clarifying_response
    assert callable(get_clarifying_response)
    result = await get_clarifying_response("this", context={})
    assert result is None or isinstance(result, str)
