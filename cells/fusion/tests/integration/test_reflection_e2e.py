"""
E2E: POST /ingest -> wait -> envelope in truth_envelopes with manifold_position, turn_log.
Requires services up.
"""
import pytest
import os

pytestmark = pytest.mark.skipif(
    not os.getenv("RUN_INTEGRATION"),
    reason="Set RUN_INTEGRATION=1 to run E2E tests"
)
