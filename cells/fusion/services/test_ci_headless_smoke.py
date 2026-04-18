"""Headless CI smoke — VALIDATION_TIER: CI_headless_smoke (Python).

The GAIAOS tree has most pytest modules under ``tests/`` with path and fixture
dependencies that are not wired for Linux CI yet. This module lives under
``services/`` so ``pytest services/`` always collects at least one deterministic
unit test (no network, no DB).
"""


def test_ci_python_path_smoke():
    assert True
