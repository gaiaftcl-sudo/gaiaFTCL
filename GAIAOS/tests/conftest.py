"""
Pytest fixtures for GaiaFTCL gap closure test suite.
"""
import os
import pytest

TEST_WALLET = "0xTEST0000000000000000000000000000000001"
ARANGO_URL = os.getenv("ARANGO_URL", "http://localhost:8529")
ARANGO_DB = os.getenv("ARANGO_DB", "gaiaos")
ARANGO_USER = os.getenv("ARANGO_USER", "root")
ARANGO_PASSWORD = os.getenv("ARANGO_PASSWORD", "gaiaftcl2026")


@pytest.fixture
def arango_auth():
    return (ARANGO_USER, ARANGO_PASSWORD)


@pytest.fixture
def test_wallet():
    return TEST_WALLET
