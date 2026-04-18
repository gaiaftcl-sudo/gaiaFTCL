"""
Dynamic change test: audience_position drives tone, no keyword routing.
Precondition: grep finds ZERO keyword routing. If found, test fails.
"""
import subprocess
import pytest
import sys
import os


def test_no_keyword_routing_in_codebase():
    """
    Invariant: No is_investor, is_investor_pitch, or audience='investor' string labels.
    If grep finds any, test fails - prevents false closure.
    """
    root = os.path.join(os.path.dirname(__file__), "..", "services")
    patterns = [
        'is_investor_pitch',
        'is_investor =',
        'audience = "investor"',
        'claim_type in ["investor"',
    ]
    for pattern in patterns:
        result = subprocess.run(
            ["rg", "-l", pattern, "--glob", "!*.md", "--glob", "!*archive*", "-g", "!main*.py", "-g", "!*.bak", root],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0 and result.stdout.strip():
            files = result.stdout.strip().split("\n")
            pytest.fail(
                f"Keyword routing found: pattern '{pattern}' in {files}. "
                "Remove investor keyword routing; use audience_position."
            )


@pytest.mark.asyncio
async def test_audience_position_drives_tone():
    """When audience_position indicates investor (D2, D5 > 0.65), tone is professional."""
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "services", "substrate_generative_sidecar"))
    from generative_api import _audience_position_indicates_investor, detect_query_intent
    assert _audience_position_indicates_investor([0.5] * 8) is False
    investor_pos = [0.5, 0.5, 0.7, 0.5, 0.5, 0.7, 0.5, 0.5]
    assert _audience_position_indicates_investor(investor_pos) is True
    akg_full_context = {"akg_data": {}, "query_context": {"audience_position": investor_pos}}
    intent = detect_query_intent("give me a one-liner value prop", akg_full_context)
    assert intent["primary_intent"] == "investor_communication"
