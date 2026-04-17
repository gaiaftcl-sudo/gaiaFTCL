#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _env_truthy(name: str) -> bool:
    v = (os.environ.get(name) or "").strip().lower()
    return v in ("1", "true", "yes", "on")


def _skip_discord_api_calls() -> bool:
    """Mesh-only / no-facade runs must not hit Discord HTTP (developer portal metadata)."""
    return _env_truthy("C4_INVARIANT_MESH_ONLY") or _env_truthy("C4_SKIP_DISCORD_METADATA")


def _required_game_ids_from_registry(repo_root: Path) -> list[str]:
    reg = repo_root / "services" / "discord_frontier" / "game_room_registry.json"
    if not reg.is_file():
        return []
    try:
        data = json.loads(reg.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return []
    out: list[str] = []
    for e in data.get("entries", []):
        if e.get("kind") == "game_room" and e.get("enabled", True) and e.get("mesh_mailbox") is not None:
            eid = str(e.get("id") or "").strip()
            if eid:
                out.append(eid.replace("_", "-"))
    return sorted(set(out))


def _available_validation_keys(repo_root: Path) -> set[str]:
    p = repo_root / "evidence" / "discord_game_rooms" / "game_validation_20260331_132531.json"
    if not p.is_file():
        return set()
    try:
        v = json.loads(p.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return set()
    return set((v.get("game_rooms") or {}).keys())


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    meta_script = repo / "scripts" / "validate_discord_application_metadata.py"
    if (
        not _skip_discord_api_calls()
        and meta_script.is_file()
        and (
            (os.environ.get("DISCORD_APP_BOT_TOKEN") or "").strip()
            or (os.environ.get("DISCORD_BOT_TOKEN") or "").strip()
        )
    ):
        try:
            subprocess.run(
                [sys.executable, str(meta_script)],
                cwd=str(repo),
                timeout=90,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            pass

    contract_path = repo / "spec" / "release_domain_ui_gameplay_gate.json"
    mesh_capture_path = repo / "evidence" / "mesh_game_runner" / "MESH_GAME_RUNNER_CAPTURE.json"
    discord_capture_path = repo / "evidence" / "discord_game_rooms" / "PLAYWRIGHT_MESH_GAME_CAPTURE.json"
    fusion_path = repo / "evidence" / "fusion_control" / "FUSION_OPENUSD_GAMEPLAY_WITNESS.json"
    quantum_path = repo / "evidence" / "discord_game_rooms" / "QUANTUM_ALGO_UI_GAMEPLAY_WITNESS.json"
    out_path = repo / "evidence" / "discord_game_rooms" / "DOMAIN_UI_GAMEPLAY_WITNESS.json"
    contract = {}
    if contract_path.is_file():
        try:
            contract = json.loads(contract_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            contract = {}

    capture = {}
    capture_source = "none"
    if mesh_capture_path.is_file():
        try:
            capture = json.loads(mesh_capture_path.read_text(encoding="utf-8"))
            capture_source = "mesh_game_runner"
        except (json.JSONDecodeError, OSError):
            capture = {}
    elif discord_capture_path.is_file():
        try:
            capture = json.loads(discord_capture_path.read_text(encoding="utf-8"))
            capture_source = "discord_mesh_capture"
        except (json.JSONDecodeError, OSError):
            capture = {}
    games = capture.get("games") if isinstance(capture, dict) else {}
    if not isinstance(games, dict):
        games = {}
    mesh_domains = capture.get("domains") if isinstance(capture, dict) else {}
    if not isinstance(mesh_domains, dict):
        mesh_domains = {}

    reg_to_validation = {
        "atc": "atc-ops",
        "biology-cures": "biology-cures",
        "crypto-risk": "crypto-risk",
        "nuclear-fusion": "nuclear-fusion",
        "token-economics": "token-economics",
        "logistics-chain": "logistics",
        "quantum-closure": "quantum-closure",
        "robotics-ops": "robotics",
        "telecom-mesh": "telecom",
        "med": "medical",
        "law": "law",
        "climate-accounting": "climate",
        "neuro-clinical": "neuro-clinical",
        "sports-vortex": "sports-vortex",
    }
    required = _required_game_ids_from_registry(repo)
    available_keys = _available_validation_keys(repo)
    required_filtered: list[str] = []
    for gid in required:
        mapped = reg_to_validation.get(gid, gid)
        if available_keys and mapped not in available_keys:
            continue
        required_filtered.append(gid)

    missing: list[str] = []
    if capture_source == "mesh_game_runner":
        required_domain_keys = [
            "fusion_discord_web_mac",
            "materials_molecules",
            "biology_disease",
            "atc_mirror_world",
            "quantum_algorithms",
            "sports_vortex",
            "neuro_clinical",
            "telecom_mesh",
        ]
        for did in required_domain_keys:
            row = mesh_domains.get(did)
            if not isinstance(row, dict):
                missing.append(did)
                continue
            ui = row.get("ui_interactions")
            shots = row.get("screenshot_paths")
            ok = (
                bool(row.get("live_captured"))
                and isinstance(ui, dict)
                and bool(ui.get("route_opened"))
                and bool(ui.get("gui_visible"))
                and bool(ui.get("gameplay_executed"))
                and isinstance(shots, list)
                and len([s for s in shots if isinstance(s, str) and s.strip()]) > 0
            )
            if not ok:
                missing.append(did)
    else:
        for gid in required_filtered:
            row = games.get(gid)
            if not isinstance(row, dict):
                missing.append(gid)
                continue
            ui = row.get("ui_interactions")
            if not isinstance(ui, dict):
                missing.append(gid)
                continue
            ok = (
                bool(row.get("live_captured"))
                and bool(ui.get("status_invoked"))
                and bool(ui.get("dashboard_invoked"))
                and bool(ui.get("discord_surface_proof_detected"))
                and bool(str(ui.get("screenshot_path") or "").strip())
            )
            if not ok:
                missing.append(gid)

    fusion_ok = False
    if fusion_path.is_file():
        try:
            f = json.loads(fusion_path.read_text(encoding="utf-8"))
            ft = str(f.get("terminal", "")).upper()
            fusion_ok = ft in ("CALORIE", "CURE") and str(f.get("url", "")).endswith("/fusion-s4")
        except (json.JSONDecodeError, OSError):
            fusion_ok = False

    quantum_count = 0
    quantum_from_capture: list[str] = []
    if quantum_path.is_file():
        try:
            q = json.loads(quantum_path.read_text(encoding="utf-8"))
            algos = q.get("algorithms_executed")
            if isinstance(algos, list):
                quantum_count = len([a for a in algos if str(a).strip()])
        except (json.JSONDecodeError, OSError):
            quantum_count = 0
    # Prefer Discord capture-backed quantum UI executions when present.
    if capture_source == "mesh_game_runner":
        q_row = mesh_domains.get("quantum_algorithms")
        if isinstance(q_row, dict):
            qshots = q_row.get("screenshot_paths")
            if isinstance(qshots, list):
                quantum_from_capture = [str(s).strip() for s in qshots if isinstance(s, str) and s.strip()]
                if quantum_from_capture:
                    quantum_count = len(quantum_from_capture)
    else:
        q_row = games.get("quantum-closure")
        if isinstance(q_row, dict):
            ui = q_row.get("ui_interactions")
            if isinstance(ui, dict):
                qshots = ui.get("screenshot_paths")
                if isinstance(qshots, list):
                    quantum_from_capture = [
                        str(s).strip()
                        for s in qshots
                        if isinstance(s, str) and "_qa_" in s and s.strip()
                    ]
                    if quantum_from_capture:
                        quantum_count = len(quantum_from_capture)
    # No text-file fallback for quantum count — invariant requires live GUI screenshots in capture.
    if quantum_from_capture:
        q_doc = {
            "schema": "quantum_algo_ui_gameplay_witness_v1",
            "ts_utc": utc_now(),
            "source": "discord_mesh_games_capture",
            "algorithms_executed": quantum_from_capture,
            "count": len(quantum_from_capture),
        }
        quantum_path.parent.mkdir(parents=True, exist_ok=True)
        quantum_path.write_text(json.dumps(q_doc, indent=2) + "\n", encoding="utf-8")

    quantum_required = int(contract.get("required_quantum_algorithm_count", 19))
    required_total_screenshots = int(contract.get("required_total_screenshots", 53))
    required_domain_min = contract.get("required_domain_screenshot_minimums") or {}
    if not isinstance(required_domain_min, dict):
        required_domain_min = {}

    domain_to_registry_ids: dict[str, list[str]] = {
        "fusion_discord_web_mac": [],
        "materials_molecules": ["biology-cures"],
        "biology_disease": ["biology-cures", "med", "neuro-clinical"],
        "atc_mirror_world": ["atc"],
        "quantum_algorithms": ["quantum-closure"],
        "sports_vortex": ["sports-vortex"],
        "neuro_clinical": ["neuro-clinical"],
        "telecom_mesh": ["telecom-mesh"],
    }
    fusion_screenshot_dir = repo / "evidence" / "fusion_control"
    fusion_shots = sorted(str(p) for p in fusion_screenshot_dir.glob("*.png")) if fusion_screenshot_dir.is_dir() else []
    domain_gameplay: dict[str, dict] = {}
    total_screenshots = 0
    for domain_id, min_count_raw in required_domain_min.items():
        min_count = int(min_count_raw)
        if capture_source == "mesh_game_runner":
            row = mesh_domains.get(domain_id)
            shots = row.get("screenshot_paths") if isinstance(row, dict) else []
            if not isinstance(shots, list):
                shots = []
            shots = [str(s).strip() for s in shots if isinstance(s, str) and s.strip()]
            count = len(shots)
        elif domain_id == "fusion_discord_web_mac":
            count = len(fusion_shots)
            shots = fusion_shots
        else:
            shots = []
            for gid in domain_to_registry_ids.get(domain_id, []):
                row = games.get(gid)
                if isinstance(row, dict):
                    ui = row.get("ui_interactions")
                    shot = ui.get("screenshot_path") if isinstance(ui, dict) else None
                    if isinstance(shot, str) and shot.strip():
                        shots.append(shot.strip())
                    shot_list = ui.get("screenshot_paths") if isinstance(ui, dict) else None
                    if isinstance(shot_list, list):
                        for sp in shot_list:
                            sps = str(sp).strip()
                            if sps:
                                shots.append(sps)
            # Deduplicate while preserving order
            seen = set()
            uniq: list[str] = []
            for s in shots:
                if s in seen:
                    continue
                seen.add(s)
                uniq.append(s)
            shots = uniq
            count = len(shots)
        total_screenshots += count
        domain_gameplay[domain_id] = {
            "graphical_witness_ok": count >= min_count,
            "screenshot_count": count,
            "required_screenshot_count": min_count,
            "screenshot_paths": shots,
        }

    blockers: list[str] = []
    if missing:
        blockers.append("missing_domain_graphical_games")
    if not fusion_ok:
        blockers.append("fusion_openusd_gameplay_missing")
    if quantum_count < quantum_required:
        blockers.append("quantum_algorithm_ui_coverage_insufficient")
    for domain_id, row in domain_gameplay.items():
        if not bool(row.get("graphical_witness_ok")):
            blockers.append(f"domain_graphical_shortfall:{domain_id}")
    if total_screenshots < required_total_screenshots:
        blockers.append("total_screenshot_floor_insufficient")

    require_discord_embedded = bool(contract.get("require_discord_embedded_flags"))
    meta_rel = str(contract.get("discord_application_metadata_witness") or "").strip()
    meta_path = (repo / meta_rel) if meta_rel else (repo / "evidence" / "discord" / "DISCORD_APPLICATION_METADATA_WITNESS.json")
    discord_meta: dict | None = None
    if meta_path.is_file():
        try:
            discord_meta = json.loads(meta_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            discord_meta = None
    if require_discord_embedded:
        if not isinstance(discord_meta, dict):
            blockers.append("discord_application_metadata_witness_missing")
        else:
            term = str(discord_meta.get("terminal") or "").upper()
            if term == "SKIPPED":
                blockers.append("discord_metadata_skipped_no_bot_token")
            elif not bool(discord_meta.get("discord_embedded_activity_eligible")):
                blockers.append("discord_embedded_platform_not_eligible")

    terminal = "CURE" if not blockers else "PARTIAL"
    doc = {
        "schema": "domain_ui_graphical_gameplay_witness_v1",
        "ts_utc": utc_now(),
        "domain_gameplay": domain_gameplay,
        "total_screenshots": total_screenshots,
        "required_total_screenshots": required_total_screenshots,
        "domain_games_required": required_filtered,
        "domain_games_graphical_ok": sorted([g for g in required_filtered if g not in missing]),
        "missing_domain_graphical_games": sorted(missing),
        "fusion_openusd_gameplay_ok": fusion_ok,
        "quantum_algorithm_ui_count": quantum_count,
        "quantum_algorithm_required_count": quantum_required,
        "blockers": blockers,
        "terminal": terminal,
        "discord_application_metadata": discord_meta,
        "require_discord_embedded_flags": require_discord_embedded,
        "capture_source": capture_source,
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
    print(out_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
