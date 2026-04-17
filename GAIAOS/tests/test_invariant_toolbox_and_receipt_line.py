"""
Tests for invariant toolbox preflight and strict ``GAIAFTCL_INVARIANT_RESULT`` line (===).
"""
from __future__ import annotations

import shutil
from pathlib import Path

import pytest

import sys

_REPO = Path(__file__).resolve().parents[1]
_SCRIPTS = _REPO / "scripts"
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

import mesh_healer  # noqa: E402
import run_full_release_invariant as fri  # noqa: E402


def test_mesh_healer_cells_match_invariant_constant():
    assert mesh_healer.MESH_SOVEREIGN_CELLS == fri.MESH_SOVEREIGN_CELLS


def test_mesh_gate_spin_signature_changes_as_cells_heal():
    d6 = {
        "cells": [
            {"cell": "a", "ok": True},
            {"cell": "b", "ok": False},
            {"cell": "c", "ok": False},
        ],
    }
    d7 = {
        "cells": [
            {"cell": "a", "ok": True},
            {"cell": "b", "ok": True},
            {"cell": "c", "ok": False},
        ],
    }
    s6 = fri.mesh_gate_spin_signature(d6)
    s7 = fri.mesh_gate_spin_signature(d7)
    assert s6 != s7
    assert "mesh:1/9:b,c" == s6
    assert "mesh:2/9:c" == s7


def _minimal_ctx(repo: Path) -> fri.RunContext:
    ev = repo / "evidence" / "release"
    ev.mkdir(parents=True, exist_ok=True)
    ui = repo / "services" / "gaiaos_ui_web"
    ui.mkdir(parents=True, exist_ok=True)
    return fri.RunContext(
        repo_root=repo,
        evidence_release=ev,
        ui_dir=ui,
        heartbeat_jsonl=ev / "_test_toolbox_hb.jsonl",
        final_json=ev / "_test_toolbox_final.json",
        semantics_path=repo / "evidence" / "discord" / "RELEASE_C4_SEMANTICS.md",
        contract_path=ui / "spec" / "release_language_games.json",
        human_ack_path=ev / "HUMAN_VISUAL_ACK.json",
        min_png_bytes=50000,
        heartbeat_sec=15.0,
        earth_wait_sec=25.0,
        nats_url="nats://127.0.0.1:4222",
        discord_profile="gaiaftcl",
        spin_k=30,
        max_cycles=None,
        build_timeout_sec=None,
        use_governor_lock=False,
        mesh_only=False,
        mesh_nine_cell_surface=True,
        require_earth_moor=True,
        mesh_fusion_web_url="https://example.com/fusion-s4",
        invoke_full_session=True,
        require_full_session=False,
        clear_release_deck=False,
        full_session_timeout_sec=None,
        full_coverage=True,
        full_compliance=False,
        mac_sub_invariant_script=repo / "scripts" / "run_mac_fusion_sub_invariant.py",
        discord_execution_enabled=False,
    )


def test_parse_gaiaftcl_invariant_result_line_strict():
    line = fri.gaiaftcl_invariant_result_line(
        "CURE",
        True,
        Path("/tmp/r.json"),
        Path("/tmp/latest.json"),
    )
    parsed = fri.parse_gaiaftcl_invariant_result_line(line)
    assert parsed is not None
    assert parsed["terminal"] == "CURE"
    assert parsed["satisfied"] == "true"
    assert parsed["receipt"] == "/tmp/r.json"
    assert parsed["stable"] == "/tmp/latest.json"


def test_parse_rejects_legacy_single_equals():
    legacy = "GAIAFTCL_INVARIANT_RESULT terminal=CURE satisfied=true receipt=/a stable=/b"
    assert fri.parse_gaiaftcl_invariant_result_line(legacy) is None


def test_parse_rejects_missing_prefix():
    assert fri.parse_gaiaftcl_invariant_result_line("terminal===CURE") is None


def test_toolbox_missing_spec(tmp_path: Path):
    ctx = _minimal_ctx(tmp_path)
    ok, missing = fri.validate_invariant_toolbox(ctx)
    assert ok is False
    assert any(m.get("kind") == "spec" for m in missing)


def test_mesh_json_matches_mesh_sovereign_cells_constant():
    spec = fri.load_invariant_toolbox_spec(_REPO)
    assert spec is not None
    assert spec["mesh"]["sovereign_cells"] == fri._mesh_cells_as_spec_dicts()


def test_toolbox_real_repo_when_cli_present():
    """Integration: full GAIAOS checkout with npm/npx/python3/bash should pass toolbox."""
    for exe in ("python3", "bash", "npm", "npx"):
        if shutil.which(exe) is None:
            pytest.skip(f"{exe} not on PATH")
    ctx = _minimal_ctx(_REPO)
    (ctx.contract_path.parent).mkdir(parents=True, exist_ok=True)
    if not ctx.contract_path.is_file():
        pytest.skip("release_language_games.json missing")
    ok, missing = fri.validate_invariant_toolbox(ctx)
    assert ok is True, missing
