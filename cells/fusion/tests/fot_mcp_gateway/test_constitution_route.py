"""Wallet gateway GET /constitution (governance surface)."""

from __future__ import annotations

import importlib.util
import os
import sys
from pathlib import Path

import pytest

_GAIAOS = Path(__file__).resolve().parents[2]
_GATEWAY = _GAIAOS / "services" / "fot_mcp_gateway"
_CONST_SRC = _GAIAOS / "services" / "discord_frontier" / "shared" / "constitution.py"


def _load_gateway_app():
    os.environ.setdefault("GATEWAY_SKIP_NATS", "1")
    _services = str(_GAIAOS / "services")
    if _services not in sys.path:
        sys.path.insert(0, _services)
    if str(_GATEWAY) not in sys.path:
        sys.path.insert(0, str(_GATEWAY))
    spec = importlib.util.spec_from_file_location(
        "gaiaftcl_constitution_doc",
        _CONST_SRC,
    )
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules["gaiaftcl_constitution_doc"] = mod
    spec.loader.exec_module(mod)
    import main as gw_main  # noqa: WPS433 — test harness import after path/module setup

    return gw_main


@pytest.fixture()
def client():
    gw_main = _load_gateway_app()
    from fastapi.testclient import TestClient

    with TestClient(gw_main.app) as c:
        yield c


def test_constitution_route_returns_document_and_source(client):
    r = client.get("/constitution")
    assert r.status_code == 200
    data = r.json()
    assert data.get("source")
    assert data.get("nats_connected") is False
    doc = data.get("document") or {}
    assert doc.get("version") == 1
    assert len(doc.get("mother_protocol") or []) == 8
    assert "mcp_is_law" in (doc.get("invariants") or [])
