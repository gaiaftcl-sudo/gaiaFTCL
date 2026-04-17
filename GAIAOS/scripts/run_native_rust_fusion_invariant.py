#!/usr/bin/env python3
"""Native Rust Fusion invariant runner (no sidecar/docker-default assumptions).

**Closure principle:** a file that has **not run** is an **open sore**, not CURE. Only a completed
pass with executed gates and live witnesses closes the envelope; unexecuted artifacts on disk are not closure.

**Invariant toolbox:** the contract JSON lists every CLI the runner may invoke; ``invariantToolboxGate``
runs first and probes them (executable on PATH + probe argv). Witnesses are written under
``evidence/native_fusion/`` — closure is enforced by this script, not by chat/manual checklists.

**Mesh-first:** ``nineCellMeshGreenGate`` runs immediately after the toolbox (WAN :8803/health on all
nine cells). When ``GAIAFTCL_INVARIANT_MESH_HEAL=1`` (default), failed probes invoke
``scripts/deploy_crystal_nine_cells.sh`` (optional ``deploy_dmg_to_mesh.sh``) until 9/9 green or
round cap — witness ``nine_cell_mesh_witness.json``. **Fusion UI preflight** runs only **after** mesh
green. Set ``GAIAFTCL_INVARIANT_MESH_HEAL=0`` for CI/head-only (skips WAN mesh).

**Outer fix loop:** any recoverable failure re-runs the **entire** pass (early gates → preflight → gates → seal)
after global ``ensure_fusion_ui_surface`` — default **unlimited** iterations until **CURE** (the only
successful exit terminal). **Policy** refusal keywords stop the loop. **Inner:** gate retries,
preflight phases, sub-seal retries. **Klein bottle:** receipt carries ``klein_bottle`` on CURE —
inside=outside fold; no CALORIE exit gate on this runner.

Use ``GAIAFTCL_INVARIANT_OUTER_FIX_LOOP_MAX=1`` for a single pass; ``GAIAFTCL_INVARIANT_NO_FUSION_UI_BOOTSTRAP=1`` for CI probe-only.

**Operator — do not cap the process with a short shell ``timeout``:** mesh heal + ``deploy_crystal_nine_cells.sh`` + ``cargo build --release`` (Tauri) routinely exceed **10–30+ minutes**. The Klein bottle closes on **terminal state** (CURE / REFUSED / policy), not a wall clock on the Python process. Watch live: ``tail -f evidence/native_fusion/MAC_FUSION_SUB_HEARTBEAT_<run_id>.jsonl``.

- ``C4_INVARIANT_FULL_COVERAGE=1`` — print full-coverage banner (reminder: no session time limit in-process).
- ``GAIAFTCL_INVARIANT_HEARTBEAT_JSONL=0`` — disable JSONL heartbeat lines (default **on**).
- Per-gate subprocess timeouts are large (see ``GAIAFTCL_INVARIANT_CARGO_RELEASE_BUILD_TIMEOUT_SEC``); they are **not** a substitute for killing the whole runner with ``timeout 120``.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Optional

INVARIANT_ID = "gaiaftcl_native_rust_fusion_invariant_v1"
HEARTBEAT_SCHEMA = "gaiaftcl_native_rust_fusion_invariant_heartbeat_v1"
# Successful process exit (exit 0) only when receipt terminal is CURE — not CALORIE.
EXIT_GATE_TERMINAL = "CURE"

# Must match contract `gate_order` tail; sub-seal runs after all of GATES pass.
# Gates that may transiently fail when the Fusion HTTP surface blips — self-heal between attempts.
GATES_SELF_HEAL_SURFACE: frozenset[str] = frozenset(
    {
        "s4c4ProjectionGate",
        "meshConnectivityGate",
        "fusionAppFullOperationalGate",
    }
)

EVIDENCE_WITNESS_FILES_FOR_SEAL = (
    "plant_hot_swap_witness.json",
    "protection_interlock_witness.json",
    "iso25010_quality_witness.json",
    "functional_safety_witness.json",
    "facility_middleware_witness.json",
    "fat_stage_witness.json",
    "sat_stage_witness.json",
    "commissioning_stage_witness.json",
    "long_soak_stage_witness.json",
)

# First two gates run before Fusion UI preflight (toolbox + nine-cell WAN mesh).
GATES_BEFORE_PREFLIGHT = (
    "invariantToolboxGate",
    "nineCellMeshGreenGate",
)

GATES: list[str] = [
    "invariantToolboxGate",
    "nineCellMeshGreenGate",
    "macFusionAppBuildGate",
    "macFusionAppTestGate",
    "macFusionAppLiveRunGate",
    "moorOnboardGate",
    "rustAppBuildGate",
    "metalRuntimeGate",
    "macDiscordActivitiesGate",
    "macNatsTunnelContractGate",
    "meshFleetSnapshotParityGate",
    "s4c4ProjectionGate",
    "meshConnectivityGate",
    "arangoQueryGate",
    "gnnInferenceGate",
        "nativeMenuActionCoverageGate",
        "sidecarControlSurfaceGate",
    "plantAdapterContractGate",
    "plantHotSwapGate",
    "protectionInterlockGate",
    "iso25010QualityGate",
    "functionalSafetyLifecycleGate",
    "facilityMiddlewareCompatGate",
    "fatConformanceGate",
    "satNetworkSecurityGate",
    "commissioningLoadGate",
    "longSoakStabilityGate",
    "fusionAppFullOperationalGate",
]

# Full coverage: these gates may heal across retries — do not spin-stall them (outer loop + inner heal).
HEALING_GATES_SPIN_EXEMPT: frozenset[str] = frozenset(
    {
        "nineCellMeshGreenGate",
        "macFusionAppBuildGate",
        "macFusionAppTestGate",
        "macFusionAppLiveRunGate",
        "fusionAppFullOperationalGate",
    }
)


def _full_coverage() -> bool:
    return os.environ.get("C4_INVARIANT_FULL_COVERAGE", "").strip() == "1"


def _spin_check_enabled(gate_name: str) -> bool:
    if _full_coverage() and gate_name in HEALING_GATES_SPIN_EXEMPT:
        return False
    return True


def _spin_threshold() -> int:
    return max(2, int(os.environ.get("GAIAFTCL_INVARIANT_SPIN_THRESHOLD", "12")))


class SpinTracker:
    """Same failure signature repeated K times → stall (REFUSED), unless gate is healing + full coverage."""

    def __init__(self) -> None:
        self._sig: dict[str, str] = {}
        self._n: dict[str, int] = {}

    def reset_gate(self, gate_name: str) -> None:
        self._sig.pop(gate_name, None)
        self._n.pop(gate_name, None)

    def stalled(self, gate_name: str, signature: str) -> bool:
        th = _spin_threshold()
        if self._sig.get(gate_name) != signature:
            self._sig[gate_name] = signature
            self._n[gate_name] = 1
            return False
        c = self._n.get(gate_name, 0) + 1
        self._n[gate_name] = c
        return c >= th


def _default_spin_signature(gate_name: str, witness: dict[str, Any]) -> str:
    parts: list[str] = []
    for k in ("reason", "build_rc", "test_rc", "exec_rc", "mesh_green", "operational"):
        if k in witness:
            parts.append(f"{k}={witness[k]}")
    if parts:
        return f"{gate_name}|" + "|".join(parts)
    raw = json.dumps(witness, sort_keys=True, default=str)
    return f"{gate_name}|{hashlib.sha256(raw.encode('utf-8', errors='replace')).hexdigest()[:16]}"


def _mesh_heal_enabled() -> bool:
    return os.environ.get("GAIAFTCL_INVARIANT_MESH_HEAL", "1").strip() != "0"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def run_cmd(cmd: list[str], cwd: Path, timeout: int = 60, max_output_chars: int = 8000) -> tuple[int, str]:
    try:
        cp = subprocess.run(
            cmd,
            cwd=str(cwd),
            timeout=timeout,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
        out = cp.stdout or ""
        if max_output_chars > 0 and len(out) > max_output_chars:
            out = out[-max_output_chars:]
        return cp.returncode, out
    except Exception as e:  # noqa: BLE001
        return 125, f"{type(e).__name__}: {e}"


def _load_json(path: Path) -> dict[str, Any]:
    try:
        raw = path.read_text(encoding="utf-8")
        doc = json.loads(raw)
        if isinstance(doc, dict):
            return doc
    except Exception:
        return {}
    return {}


@dataclass
class Ctx:
    root: Path
    contract_path: Path
    receipt_path: Path
    latest_path: Path
    evidence_dir: Path
    fusion_ui_port: str
    heartbeat: Optional["Heartbeat"] = None


@dataclass
class Heartbeat:
    """Append-only JSONL for ``tail -f`` while long gates run (mesh heal, cargo release, …)."""

    path: Path
    t0: float

    def emit(self, event: str, **extra: Any) -> None:
        if os.environ.get("GAIAFTCL_INVARIANT_HEARTBEAT_JSONL", "1").strip() == "0":
            return
        doc: dict[str, Any] = {
            "schema": HEARTBEAT_SCHEMA,
            "event": event,
            "elapsed_ms": int((time.monotonic() - self.t0) * 1000),
            "ts_utc": utc_now(),
        }
        doc.update(extra)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(doc, ensure_ascii=False) + "\n")


def _cargo_release_build_timeout_sec() -> int:
    return max(60, int(os.environ.get("GAIAFTCL_INVARIANT_CARGO_RELEASE_BUILD_TIMEOUT_SEC", "7200")))


def _heartbeat_emit(ctx: Ctx, event: str, **kw: Any) -> None:
    if ctx.heartbeat is not None:
        ctx.heartbeat.emit(event, **kw)


def load_contract(ctx: Ctx) -> dict[str, Any]:
    doc = json.loads(ctx.contract_path.read_text(encoding="utf-8"))
    if doc.get("invariant_id") != INVARIANT_ID:
        raise ValueError("contract invariant mismatch")
    if doc.get("gate_order") != GATES + ["subSealingGate"]:
        raise ValueError("contract gate order mismatch")
    tb = doc.get("invariant_toolbox")
    if not isinstance(tb, dict):
        raise ValueError("contract missing invariant_toolbox object")
    tools = tb.get("tools")
    if not isinstance(tools, list) or len(tools) < 1:
        raise ValueError("contract invariant_toolbox.tools must be a non-empty list")
    return doc


def contains_refusal_keywords(text: str, keywords: list[str]) -> bool:
    low = text.lower()
    return any(k.lower() in low for k in keywords)


def gate_invariant_toolbox(ctx: Ctx, contract: dict[str, Any]) -> tuple[bool, dict[str, Any]]:
    """
    First gate: contract ``invariant_toolbox.tools`` defines every CLI the mesh/deploy/runner stack
    expects (ssh, rsync, docker, cargo, …). Probes PATH + argv; writes
    ``evidence/native_fusion/invariant_toolbox_witness.json`` — the invariant owns closure, not chat.
    """
    tb = contract.get("invariant_toolbox") or {}
    tools_spec = tb.get("tools") or []
    ctx.evidence_dir.mkdir(parents=True, exist_ok=True)

    tool_rows: list[dict[str, Any]] = []
    required_failures: list[str] = []

    for spec in tools_spec:
        if not isinstance(spec, dict):
            required_failures.append("_invalid_tool_spec")
            continue
        tid = str(spec.get("id", "unknown"))
        optional = bool(spec.get("optional", False))
        if tid == "hcloud" and _mesh_heal_enabled():
            optional = False
        probe = spec.get("probe")
        if not isinstance(probe, list) or len(probe) < 1 or not all(isinstance(x, str) for x in probe):
            tool_rows.append({"id": tid, "optional": optional, "error": "invalid_probe"})
            if not optional:
                required_failures.append(tid)
            continue

        exe = probe[0]
        timeout_sec = int(spec.get("timeout_sec", 25))
        accept = spec.get("accept_rc")
        if accept is None:
            accept_rcs: list[int] = [0]
        elif isinstance(accept, int):
            accept_rcs = [accept]
        elif isinstance(accept, list):
            accept_rcs = [int(x) for x in accept]
        else:
            accept_rcs = [0]

        resolved = shutil.which(exe)
        if not resolved:
            tool_rows.append(
                {
                    "id": tid,
                    "optional": optional,
                    "on_path": False,
                    "skipped_optional_missing": optional,
                }
            )
            if not optional:
                required_failures.append(tid)
            continue

        rc, out = run_cmd(probe, cwd=ctx.root, timeout=timeout_sec)
        probe_ok = rc in accept_rcs
        tail = "\n".join(out.splitlines()[-5:])
        row: dict[str, Any] = {
            "id": tid,
            "optional": optional,
            "on_path": True,
            "resolved_path": resolved,
            "probe_rc": rc,
            "probe_ok": probe_ok,
            "probe_tail": tail[-1200:],
        }
        if not optional and not probe_ok:
            required_failures.append(tid)
        elif optional and not probe_ok:
            row["optional_probe_failed"] = True
        tool_rows.append(row)

    witness_doc = {
        "schema": "gaiaftcl_invariant_toolbox_witness_v1",
        "invariant_id": INVARIANT_ID,
        "ts_utc": utc_now(),
        "description": tb.get("description"),
        "tools": tool_rows,
        "required_failures": required_failures,
    }
    wpath = ctx.evidence_dir / "invariant_toolbox_witness.json"
    latest = ctx.evidence_dir / "LATEST_INVARIANT_TOOLBOX_WITNESS.json"
    wpath.write_text(json.dumps(witness_doc, indent=2), encoding="utf-8")
    latest.write_text(json.dumps(witness_doc, indent=2), encoding="utf-8")

    ok = len(required_failures) == 0
    return ok, {
        "witness_path": str(wpath.relative_to(ctx.root)),
        "latest_path": str(latest.relative_to(ctx.root)),
        "tool_count": len(tool_rows),
        "required_failures": required_failures,
        "ids_probed": [r.get("id") for r in tool_rows],
    }


def gate_nine_cell_mesh_green(ctx: Ctx) -> tuple[bool, dict[str, Any]]:
    """
    WAN mesh: all nine cells HTTP 2xx on :8803/health. When heal is on, ``mesh_healer.probe_and_heal_until_healthy``
    SSH-restarts failed gateway containers, re-probes, then runs deploy_crystal_nine_cells.sh (and optional DMG push).
    """
    ctx.evidence_dir.mkdir(parents=True, exist_ok=True)
    probe_script = ctx.root / "scripts" / "invariant_mesh_green_probe.sh"
    deploy_script = ctx.root / "scripts" / "deploy_crystal_nine_cells.sh"
    dmg_script = ctx.root / "scripts" / "deploy_dmg_to_mesh.sh"

    if not probe_script.is_file():
        return False, {"reason": "missing_probe_script", "path": str(probe_script.relative_to(ctx.root))}

    offline = os.environ.get("C4_INVARIANT_MESH_NINE_CELL_OFFLINE", "").strip().lower()
    if offline in ("1", "true", "yes"):
        doc = {
            "schema": "gaiaftcl_nine_cell_mesh_witness_v1",
            "invariant_id": INVARIANT_ID,
            "ts_utc": utc_now(),
            "skipped": True,
            "reason": "C4_INVARIANT_MESH_NINE_CELL_OFFLINE",
            "note": "WAN mesh check skipped (CI / headless)",
        }
        _write_nine_cell_mesh_witness(ctx, doc)
        return True, {"skipped": True, "reason": "C4_INVARIANT_MESH_NINE_CELL_OFFLINE"}

    if not _mesh_heal_enabled():
        doc = {
            "schema": "gaiaftcl_nine_cell_mesh_witness_v1",
            "invariant_id": INVARIANT_ID,
            "ts_utc": utc_now(),
            "skipped": True,
            "reason": "GAIAFTCL_INVARIANT_MESH_HEAL=0",
        }
        _write_nine_cell_mesh_witness(ctx, doc)
        return True, {"skipped": True, "reason": "GAIAFTCL_INVARIANT_MESH_HEAL=0"}

    scripts_dir = Path(__file__).resolve().parent
    if str(scripts_dir) not in sys.path:
        sys.path.insert(0, str(scripts_dir))
    import mesh_healer as mh  # noqa: PLC0415

    max_rounds = max(
        1,
        int(
            os.environ.get(
                "GAIAFTCL_INVARIANT_MESH_HEAL_MAX_ROUNDS",
                os.environ.get("C4_MESH_HEAL_MAX_ATTEMPTS", "10"),
            )
        ),
    )
    heal_wait = float(os.environ.get("C4_MESH_HEAL_WAIT_SEC", "30"))
    deploy_timeout = int(os.environ.get("GAIAFTCL_INVARIANT_MESH_DEPLOY_TIMEOUT_SEC", "7200"))
    post_sleep = float(os.environ.get("GAIAFTCL_INVARIANT_MESH_POST_DEPLOY_SLEEP_SEC", "45"))
    push_dmg = os.environ.get("GAIAFTCL_INVARIANT_MESH_PUSH_DMG", "").strip() == "1"

    def _on_event(row: dict[str, Any]) -> None:
        _heartbeat_emit(ctx, "mesh_heal", **row)

    mesh_ok, heal_summary = mh.probe_and_heal_until_healthy(
        ctx.root,
        max_heal_rounds=max_rounds,
        heal_wait_sec=heal_wait,
        post_deploy_sleep=post_sleep,
        deploy_script=deploy_script,
        deploy_timeout=deploy_timeout,
        dmg_script=dmg_script,
        push_dmg=push_dmg,
        on_event=_on_event,
    )

    fin = heal_summary.get("final") or {}
    healthy_count = fin.get("healthy_count")
    unhealthy = fin.get("unhealthy") or []

    if mesh_ok:
        doc = {
            "schema": "gaiaftcl_nine_cell_mesh_witness_v1",
            "invariant_id": INVARIANT_ID,
            "ts_utc": utc_now(),
            "mesh_green": True,
            "nine_of_nine": True,
            "heal_summary": heal_summary,
            "probe_script": str(probe_script.relative_to(ctx.root)),
        }
        _write_nine_cell_mesh_witness(ctx, doc)
        return True, {
            "mesh_green": True,
            "witness_path": str((ctx.evidence_dir / "nine_cell_mesh_witness.json").relative_to(ctx.root)),
            "heal_rounds_count": len(heal_summary.get("heal_rounds") or []),
        }

    doc = {
        "schema": "gaiaftcl_nine_cell_mesh_witness_v1",
        "invariant_id": INVARIANT_ID,
        "ts_utc": utc_now(),
        "mesh_green": False,
        "nine_of_nine": False,
        "heal_summary": heal_summary,
        "reason": heal_summary.get("reason", "nine_cell_mesh_not_green"),
    }
    _write_nine_cell_mesh_witness(ctx, doc)
    spin_sig = f"mesh:{healthy_count}/9:{','.join(sorted(unhealthy))}"
    return False, {
        "mesh_green": False,
        "reason": "nine_cell_mesh_not_green_after_heal",
        "witness_path": str((ctx.evidence_dir / "nine_cell_mesh_witness.json").relative_to(ctx.root)),
        "healthy_count": healthy_count,
        "unhealthy": unhealthy,
        "heal_rounds_sample": (heal_summary.get("heal_rounds") or [])[-4:],
        "spin_signature": spin_sig,
        "heal_why": "probe → ssh docker restart per failed cell → re-probe → deploy_crystal_nine_cells.sh "
        + ("+ DMG push " if push_dmg else "")
        + f"— still not 9/9 after {max_rounds} heal round(s). Check SSH keys (GAIAFTCL_INVARIANT_MESH_SSH_KEY) "
        "and cell reachability.",
    }


def _write_nine_cell_mesh_witness(ctx: Ctx, doc: dict[str, Any]) -> None:
    wpath = ctx.evidence_dir / "nine_cell_mesh_witness.json"
    latest = ctx.evidence_dir / "LATEST_NINE_CELL_MESH_WITNESS.json"
    wpath.write_text(json.dumps(doc, indent=2), encoding="utf-8")
    latest.write_text(json.dumps(doc, indent=2), encoding="utf-8")


def gate_mac_discord_activities(ctx: Ctx) -> tuple[bool, dict[str, Any]]:
    """Mac limb: Discord automation script present (Activities / AppleScript path discipline)."""
    if sys.platform != "darwin":
        return True, {"skipped": True, "reason": "non_darwin", "platform": sys.platform}
    p = ctx.root / "scripts" / "discord_open_bot_invite_mac.sh"
    ok = p.is_file()
    return ok, {"path": str(p.relative_to(ctx.root)), "script_present": ok}


def gate_mac_nats_tunnel_contract(ctx: Ctx) -> tuple[bool, dict[str, Any]]:
    """S⁴ Mac cell ports doc — NATS tunnel / MCP parity contract on disk."""
    p = ctx.root / "deploy" / "mac_cell_mount" / "MAC_FUSION_MESH_CELL_PORTS.md"
    if not p.is_file():
        return False, {"reason": "missing_mac_ports_doc", "path": str(p)}
    body = p.read_text(encoding="utf-8", errors="replace")
    ok = "14222" in body and "8803" in body
    return ok, {"path": str(p.relative_to(ctx.root)), "has_tunnel_and_mcp_ports": ok}


def gate_mesh_fleet_snapshot_parity(ctx: Ctx) -> tuple[bool, dict[str, Any]]:
    """Fusion fleet snapshot receipt — schema + cells map (parity discipline with fusion_control evidence)."""
    p = ctx.root / "evidence" / "fusion_control" / "fusion_fleet_snapshot.json"
    if not p.is_file():
        return False, {"reason": "missing_fleet_snapshot", "path": str(p.relative_to(ctx.root))}
    try:
        doc = json.loads(p.read_text(encoding="utf-8"))
    except Exception as e:  # noqa: BLE001
        return False, {"reason": "invalid_json", "error": str(e)}
    cells = doc.get("cells")
    ok = doc.get("schema") == "gaiaftcl_fusion_fleet_snapshot_v1" and isinstance(cells, dict) and len(cells) >= 1
    return ok, {
        "path": str(p.relative_to(ctx.root)),
        "cell_keys": len(cells) if isinstance(cells, dict) else 0,
        "schema_ok": doc.get("schema") == "gaiaftcl_fusion_fleet_snapshot_v1",
    }


def gate_moor_onboard_requirements(ctx: Ctx) -> tuple[bool, dict[str, Any]]:
    """
    Validate the live mooring identity and protocol binding before downstream UI/runtime gates.
    Fail if s4c4_hash is missing or unverified.
    """
    if sys.platform != "darwin":
        return True, {
            "skipped": True,
            "reason": "mooring_identity_requirements_non_darwin_skipped",
            "platform": sys.platform,
        }

    home_identity = Path.home() / ".gaiaftcl" / "cell_identity.json"
    if not home_identity.is_file():
        return False, {"reason": "missing_cell_identity", "path": str(home_identity)}

    identity = _load_json(home_identity)
    hash_value = identity.get("s4c4_hash")
    if hash_value in (None, "", "unverified"):
        return False, {"reason": "cell_identity_missing_s4c4_hash", "hash_value": hash_value, "path": str(home_identity)}

    requirements_path = ctx.root / "spec" / "mac_fusion_operator_requirements.json"
    if not requirements_path.is_file():
        return False, {
            "reason": "missing_mac_fusion_operator_requirements",
            "path": str(requirements_path),
            "cell_identity_hash": hash_value,
        }

    requirements = _load_json(requirements_path)
    protocol = requirements.get("validation_protocol")
    protocol_document = None if not isinstance(protocol, dict) else protocol.get("protocol_document")
    protocol_version = None if not isinstance(protocol, dict) else protocol.get("protocol_version")
    safety_standards = [] if not isinstance(protocol, dict) else protocol.get("safety_standards", [])
    if not isinstance(safety_standards, list):
        safety_standards = []

    protocol_path = None
    protocol_doc_exists = False
    if isinstance(protocol_document, str) and protocol_document:
        protocol_path = (ctx.root / protocol_document).resolve()
        protocol_doc_exists = protocol_path.is_file()

    s4 = identity.get("s4", {})
    s4_keys = ["hardware_uuid", "username", "hostname", "ssh_key_fingerprint", "app_version"]
    missing_s4_keys = [k for k in s4_keys if not isinstance(s4, dict) or not s4.get(k)]

    witness: dict[str, Any] = {
        "cell_identity_path": str(home_identity),
        "cell_identity_hash": hash_value,
        "mooring_state": identity.get("mooring_state"),
        "protocol_requirements_path": str(requirements_path),
        "protocol_document": protocol_document,
        "protocol_version": protocol_version,
        "protocol_doc_exists": protocol_doc_exists,
        "protocol_doc_path": str(protocol_path) if protocol_path is not None else None,
        "safety_standards": safety_standards,
        "required_safety_standards_present": "ISA-101" in safety_standards and "IAEA-SSG-51" in safety_standards,
        "s4_fields_present": len(missing_s4_keys) == 0,
        "missing_s4_fields": missing_s4_keys,
    }

    protocol_ok = bool(
        protocol_document
        and protocol_version
        and protocol_doc_exists
        and witness["required_safety_standards_present"]
    )
    return (
        protocol_ok and len(missing_s4_keys) == 0 and hash_value not in (None, "", "unverified"),
        witness,
    )


def _gate_retry_max(gate_name: str) -> int:
    """Per-gate retry budget (full attempts, not 'extra' retries)."""
    default = int(os.environ.get("GAIAFTCL_INVARIANT_GATE_RETRY_MAX", "8"))
    build_max = int(os.environ.get("GAIAFTCL_INVARIANT_BUILD_GATE_RETRIES", "4"))
    healing_floor = max(1, int(os.environ.get("GAIAFTCL_INVARIANT_HEALING_GATE_MIN_RETRIES", "12")))
    overrides = {
        "invariantToolboxGate": max(
            1, int(os.environ.get("GAIAFTCL_INVARIANT_TOOLBOX_GATE_RETRIES", "3"))
        ),
        "nineCellMeshGreenGate": max(
            1, int(os.environ.get("GAIAFTCL_INVARIANT_MESH_GATE_RETRIES", "3"))
        ),
        "rustAppBuildGate": build_max,
        "metalRuntimeGate": build_max,
        "macFusionAppBuildGate": build_max,
        "macFusionAppTestGate": build_max,
        "macFusionAppLiveRunGate": build_max,
        "fusionAppFullOperationalGate": int(os.environ.get("GAIAFTCL_INVARIANT_OPERATIONAL_OUTER_RETRIES", "1")),
    }
    base = max(1, overrides.get(gate_name, default))
    if _full_coverage() and gate_name in HEALING_GATES_SPIN_EXEMPT:
        return max(base, healing_floor)
    return base


def _gate_retry_delay_sec() -> float:
    return float(os.environ.get("GAIAFTCL_INVARIANT_GATE_RETRY_DELAY_SEC", "4"))


def run_gate_with_retries(
    gate_name: str,
    gate_fn: Callable[[], tuple[bool, dict[str, Any]]],
    ctx: Ctx,
    refusal_keywords: list[str],
    spin: Optional[SpinTracker] = None,
) -> tuple[bool, dict[str, Any]]:
    """Run a gate until success or retry budget exhausted — no single-shot early death."""
    budget = _gate_retry_max(gate_name)
    delay = _gate_retry_delay_sec()
    last_witness: dict[str, Any] = {}
    attempts_log: list[dict[str, Any]] = []

    for attempt in range(1, budget + 1):
        ok, witness = gate_fn()
        last_witness = witness
        wtxt = json.dumps(witness, ensure_ascii=False)
        if contains_refusal_keywords(wtxt, refusal_keywords):
            witness["reason"] = "refusal_keyword_detected"
            witness["retry_attempts"] = attempt
            witness["attempts_log"] = attempts_log
            return False, witness
        entry = {"attempt": attempt, "ok": ok}
        attempts_log.append(entry)
        if ok:
            if spin is not None:
                spin.reset_gate(gate_name)
            if attempt > 1:
                witness["recovered_on_attempt"] = attempt
            witness["retry_attempts"] = attempt
            witness["attempts_log"] = attempts_log
            return True, witness

        if _spin_check_enabled(gate_name) and spin is not None:
            sig = witness.get("spin_signature") or _default_spin_signature(gate_name, witness)
            if spin.stalled(gate_name, str(sig)):
                stalled_w = dict(witness)
                stalled_w["spin_stall"] = True
                stalled_w["spin_signature_used"] = str(sig)
                stalled_w["spin_threshold"] = _spin_threshold()
                stalled_w["retry_attempts"] = attempt
                stalled_w["attempts_log"] = attempts_log
                stalled_w["spin_note"] = (
                    "Repeated identical failure signature — fix substrate or raise GAIAFTCL_INVARIANT_SPIN_THRESHOLD"
                )
                return False, stalled_w

        if attempt < budget:
            if gate_name in GATES_SELF_HEAL_SURFACE:
                sh_ok, sh_w = ensure_fusion_ui_surface(ctx)
                entry["self_heal_ensure"] = {"ok": sh_ok, "keys": list(sh_w.keys())}
            time.sleep(delay)

    last_witness = dict(last_witness)
    last_witness["retry_exhausted"] = True
    last_witness["retry_attempts"] = budget
    last_witness["attempts_log"] = attempts_log
    return False, last_witness


def run_preflight_phases(ctx: Ctx, refusal_keywords: list[str]) -> tuple[bool, dict[str, Any]]:
    """Multiple full bootstrap cycles before giving up on preflight."""
    if os.environ.get("GAIAFTCL_INVARIANT_NO_FUSION_UI_BOOTSTRAP", "").strip() == "1":
        ok, w = ensure_fusion_ui_surface(ctx)
        if contains_refusal_keywords(json.dumps(w), refusal_keywords):
            w["reason"] = "refusal_keyword_detected"
            return False, w
        return ok, {"single_probe": True, "witness": w}

    phases = int(os.environ.get("GAIAFTCL_INVARIANT_PREFLIGHT_PHASES", "8"))
    delay = float(os.environ.get("GAIAFTCL_INVARIANT_PREFLIGHT_PHASE_DELAY_SEC", "5"))
    trace: list[dict[str, Any]] = []
    last_w: dict[str, Any] = {}
    for p in range(1, phases + 1):
        ok, w = ensure_fusion_ui_surface(ctx)
        last_w = w
        trace.append({"phase": p, "ok": ok, "summary": {k: w.get(k) for k in ("reason", "already_listening", "started") if k in w}})
        if contains_refusal_keywords(json.dumps(w), refusal_keywords):
            return False, {"phase_trace": trace, "final_witness": w, "reason": "refusal_keyword_detected"}
        if ok:
            return True, {"preflight_phases": p, "phase_trace": trace, "final_witness": w}
        if p < phases:
            time.sleep(delay)
    return False, {"preflight_exhausted": True, "phase_trace": trace, "final_witness": last_w}


def _fusion_base(ctx: Ctx) -> str:
    return f"http://127.0.0.1:{ctx.fusion_ui_port}"


def _fusion_s4_url(ctx: Ctx) -> str:
    return f"{_fusion_base(ctx)}/api/fusion/s4-projection"


def _fusion_mesh_url(ctx: Ctx) -> str:
    return f"{_fusion_base(ctx)}/api/sovereign-mesh"


def probe_fusion_s4_projection(ctx: Ctx) -> tuple[bool, int, str, dict[str, Any]]:
    """
    Returns (closure_ok, curl_rc, raw_out, parsed_doc).
    Shared by bootstrap, s4c4ProjectionGate, and sub-seal anti-entropy.
    """
    rc, out = run_cmd(
        ["bash", "-lc", f"curl -sfS -m 12 '{_fusion_s4_url(ctx)}'"],
        cwd=ctx.root,
        timeout=30,
    )
    doc: dict[str, Any] = {}
    try:
        doc = json.loads(out) if rc == 0 else {}
    except Exception:  # noqa: BLE001
        doc = {}
    ok = _s4_projection_accept(rc, out, doc)
    return ok, rc, out, doc


def probe_sovereign_mesh(ctx: Ctx) -> tuple[bool, int, str, dict[str, Any]]:
    rc, out = run_cmd(
        ["bash", "-lc", f"curl -sfS -m 12 '{_fusion_mesh_url(ctx)}'"],
        cwd=ctx.root,
        timeout=30,
    )
    doc: dict[str, Any] = {}
    try:
        doc = json.loads(out) if rc == 0 else {}
    except Exception:  # noqa: BLE001
        doc = {}
    ok = _mesh_connectivity_accept(rc, doc)
    return ok, rc, out, doc


def probe_get_http_status(ctx: Ctx, path: str) -> tuple[bool, int, int]:
    """GET path (leading /) or full URL; return (ok 2xx/3xx, curl_rc, http_code)."""
    url = f"{_fusion_base(ctx)}{path}" if path.startswith("/") else path
    rc, out = run_cmd(
        ["bash", "-lc", f"curl -sS -m 25 -o /dev/null -w '%{{http_code}}' '{url}'"],
        cwd=ctx.root,
        timeout=35,
    )
    try:
        code = int(out.strip())
    except ValueError:
        code = 0
    ok = rc == 0 and 200 <= code < 400
    return ok, rc, code


def probe_fusion_s4_page_source(ctx: Ctx) -> tuple[bool, int, str]:
    """Return raw /fusion-s4 source for UI runtime assertions (DOM IDs and JS hooks)."""
    url = f"{_fusion_base(ctx)}/fusion-s4"
    marker = "__GAIAFTCL_HTTP_STATUS__"
    rc, out = run_cmd(
        [
            "bash",
            "-lc",
            f"curl -sS -m 20 -H 'Accept: text/html' -H 'User-Agent: GaiaFTCL-InvariantProbe/1.0' "
            f"-w '\\n{marker}%{{http_code}}\\n' '{url}'",
        ],
        cwd=ctx.root,
        timeout=25,
        max_output_chars=0,
    )

    page_ok = False
    http_code = 0
    body = out
    marker_token = "\n" + marker
    if marker_token in out:
        body, status_text = out.rsplit(marker_token, 1)
        status_text = status_text.strip()
        http_code = int(status_text) if status_text.isdigit() else 0
        page_ok = 200 <= http_code < 400
    elif rc == 0:
        # Fallback for curl variants that drop the -w payload unexpectedly.
        page_ok = bool(body.strip())

    return page_ok, http_code if http_code else rc, body


def _fusion_chunk_bridge_tokens_present(ctx: Ctx, page_source: str) -> bool:
    """Fallback: inspect app fusion-s4 client chunks for bridge token strings."""
    chunk_paths = re.findall(
        r"(/_next/static/chunks/[^\"']*app_fusion-s4_page_tsx_[^\"']*\\.js)",
        page_source,
    )
    if not chunk_paths:
        chunk_paths = [
            "/_next/static/chunks/app_fusion-s4_page_tsx_7a1cdab0._.js",
            "/_next/static/chunks/app_fusion-s4_page_tsx_ac15eb1f._.js",
        ]
    seen = set()
    for rel in chunk_paths[:3]:
        if rel in seen:
            continue
        seen.add(rel)
        rc, chunk = run_cmd(
            ["bash", "-lc", f"curl -sS -m 12 '{_fusion_base(ctx)}{rel}'"],
            cwd=ctx.root,
            timeout=20,
            max_output_chars=0,
        )
        if rc != 0:
            continue
        if "fusionBridge" in chunk and "fusionReceive" in chunk:
            return True
    return False


def probe_fleet_digest(ctx: Ctx) -> tuple[bool, int, str]:
    url = f"{_fusion_base(ctx)}/api/fusion/fleet-digest"
    rc, out = run_cmd(
        ["bash", "-lc", f"curl -sfS -m 15 '{url}'"],
        cwd=ctx.root,
        timeout=25,
    )
    ok = rc == 0 and len(out.strip()) > 2
    return ok, rc, out[:500]


def probe_fusion_window_visible(ctx: Ctx) -> tuple[bool, dict[str, Any]]:
    """Confirm the native GaiaFusion process exposes at least one window titleable by AX."""
    if sys.platform != "darwin":
        return True, {
            "skipped": True,
            "reason": "non_darwin_window_probe_skipped",
            "platform": sys.platform,
        }

    script = """
        tell application "System Events"
            tell process "GaiaFusion"
                set winCount to count of windows
                if winCount > 0 then
                    set winTitle to name of window 1
                    return "WINDOW_OK|" & winCount & "|" & winTitle
                end if
                return "WINDOW_MISSING"
            end tell
        end tell
    """
    rc, out = run_cmd(["osascript", "-e", script], cwd=ctx.root, timeout=12)
    raw = (out or "").strip()
    ok = rc == 0 and raw.startswith("WINDOW_OK|")
    return ok, {
        "window_probe_rc": rc,
        "window_probe": raw[:240],
        "window_count": 0 if raw.startswith("WINDOW_MISSING") else None,
        "window_title": raw.split("|", 2)[2] if ok else None,
    }


def _cleanup_existing_gaiafusion_processes(ctx: Ctx) -> dict[str, Any]:
    """Best-effort cleanup of stale GaiaFusion processes (single Mac cell — executable name only, never pkill -f)."""
    cp = subprocess.run(
        ["pgrep", "-x", "GaiaFusion"],
        cwd=str(ctx.root),
        text=True,
        capture_output=True,
        check=False,
        timeout=8,
    )
    initial_raw = (cp.stdout or "").strip()
    if not initial_raw:
        return {
            "terminated": [],
            "terminated_count": 0,
            "leftover_after_cleanup": [],
            "cleanup_skip": "none_running",
        }

    numeric_pids = [p.strip() for p in initial_raw.splitlines() if p.strip().isdigit()]

    # Ask app to quit before hard killing.
    run_cmd(["osascript", "-e", 'tell application "GaiaFusion" to quit'], ctx.root, timeout=6)
    time.sleep(1.2)

    stop_script = ctx.root / "scripts" / "stop_mac_cell_gaiafusion.sh"
    run_cmd(["bash", str(stop_script)], ctx.root, timeout=30)

    leftover_cp = subprocess.run(
        ["pgrep", "-x", "GaiaFusion"],
        cwd=str(ctx.root),
        text=True,
        capture_output=True,
        check=False,
        timeout=8,
    )
    leftover = [p.strip() for p in (leftover_cp.stdout or "").splitlines() if p.strip().isdigit()]

    return {
        "terminated": numeric_pids,
        "terminated_count": len(numeric_pids),
        "leftover_after_cleanup": leftover,
        "termination_rc": cp.returncode,
        "initial_pids_raw": initial_raw,
        "stop_script": str(stop_script),
    }


def _npm_install_if_needed(ui_dir: Path, log_path: Path) -> tuple[bool, str]:
    force = os.environ.get("GAIAFTCL_INVARIANT_NPM_INSTALL", "").strip() == "1"
    if (ui_dir / "node_modules").is_dir() and not force:
        return True, "skipped_node_modules_present"
    with open(log_path, "ab", buffering=0) as logf:
        logf.write(f"\n--- npm install {utc_now()} ---\n".encode())
        cp = subprocess.run(
            ["npm", "install"],
            cwd=str(ui_dir),
            stdout=logf,
            stderr=subprocess.STDOUT,
            timeout=900,
            check=False,
        )
    return cp.returncode == 0, f"npm_install_rc={cp.returncode}"


def _poll_until_s4_ready(
    ctx: Ctx,
    proc: Any,
    base_sec: int,
    grace_sec: int,
) -> tuple[bool, int, float, dict[str, Any]]:
    """Poll S4 projection until OK or deadlines: base_sec, then grace_sec while npm still alive."""
    t0 = time.time()
    step = 2.0
    last_rc = -1
    meta: dict[str, Any] = {}
    deadline1 = t0 + base_sec
    deadline2 = t0 + base_sec + grace_sec

    while True:
        ok, rc, _, _ = probe_fusion_s4_projection(ctx)
        last_rc = rc
        if ok:
            return True, rc, time.time() - t0, meta
        now = time.time()
        npm_alive = proc.poll() is None
        limit = deadline2 if npm_alive else deadline1
        if now >= limit:
            meta["npm_alive_at_deadline"] = npm_alive
            break
        time.sleep(step)

    ok, rc, _, _ = probe_fusion_s4_projection(ctx)
    return ok, rc, time.time() - t0, meta


def ensure_fusion_ui_surface(ctx: Ctx) -> tuple[bool, dict[str, Any]]:
    """
    Self-heal: launch native GaiaFusion process, optionally launch npm dev server when needed,
    then poll /api/fusion/s4-projection until healthy.
    """
    if os.environ.get("GAIAFTCL_INVARIANT_NO_FUSION_UI_BOOTSTRAP", "").strip() == "1":
        ok, rc, out, _ = probe_fusion_s4_projection(ctx)
        return ok, {
            "mode": "probe_only",
            "bootstrap_disabled": True,
            "fusion_ui_port": ctx.fusion_ui_port,
            "http_rc": rc,
            "closure_ok": ok,
            "tail": out[-400:] if out else "",
        }

    ok, rc, out, _ = probe_fusion_s4_projection(ctx)
    if ok:
        return True, {
            "already_listening": True,
            "fusion_ui_port": ctx.fusion_ui_port,
            "http_rc": rc,
        }

    ui_dir = ctx.root / "services" / "gaiaos_ui_web"
    if not (ui_dir / "package.json").is_file():
        return False, {"reason": "missing_gaiaos_ui_web", "path": str(ui_dir)}

    fusion_resource = (
        ctx.root / "macos" / "GaiaFusion" / "GaiaFusion" / "Resources" / "fusion-web" / "index.html"
    )
    dev_proxy_mode = not fusion_resource.is_file()

    fusion_ev = ctx.root / "evidence" / "fusion_control"
    fusion_ev.mkdir(parents=True, exist_ok=True)
    log_path = fusion_ev / "invariant_fusion_ui_bootstrap.log"
    pid_path = fusion_ev / "invariant_fusion_ui_bootstrap.pid"

    base_wait = int(os.environ.get("GAIAFTCL_INVARIANT_FUSION_UI_BOOTSTRAP_SEC", "180"))
    grace = int(os.environ.get("GAIAFTCL_INVARIANT_FUSION_UI_COMPILE_GRACE_SEC", "300"))
    max_attempts = int(os.environ.get("GAIAFTCL_INVARIANT_FUSION_UI_BOOTSTRAP_ATTEMPTS", "5"))

    trace: list[dict[str, Any]] = []
    did_install = False

    class _AliveDummy:
        def poll(self) -> int | None:
            return None

    for attempt in range(1, max_attempts + 1):
        ok, _, _, _ = probe_fusion_s4_projection(ctx)
        if ok:
            return True, {
                "already_listening": True,
                "fusion_ui_port": ctx.fusion_ui_port,
                "bootstrap_attempts_used": attempt - 1,
                "attempts_trace": trace,
            }

        dev_server_port = os.environ.get("GAIAFTCL_INVARIANT_FUSION_DEV_UI_PORT", "3000")
        if not dev_server_port.isdigit():
            dev_server_port = "3000"

        env = os.environ.copy()
        env["GAIA_ROOT"] = str(ctx.root)
        env["FUSION_UI_PORT"] = dev_server_port
        env["FUSION_UI_PROXY_PORT"] = dev_server_port

        live_ok, live_meta = gate_mac_fusion_app_live_run(ctx)
        if not live_ok:
            trace.append({"attempt": attempt, "app_live": live_meta})
            if attempt < max_attempts:
                time.sleep(3)
                continue
            return False, {
                "reason": "mac_app_not_running",
                "fusion_ui_port": ctx.fusion_ui_port,
                "attempts_trace": trace,
            }

        trace.append({"attempt": attempt, "app_live": live_meta})
        proc: Any
        proc_started = False

        if dev_proxy_mode:
            node_server_running = False
            try:
                node_server_probe = run_cmd(
                    ["bash", "-lc", f"curl -sfS -m 3 'http://127.0.0.1:{dev_server_port}/fusion-s4' >/dev/null"],
                    cwd=str(ui_dir),
                    timeout=8,
                )
                node_server_running = node_server_probe[0] == 0
            except (FileNotFoundError, subprocess.TimeoutExpired):
                node_server_running = False

            if not did_install and (not (ui_dir / "node_modules").is_dir() or os.environ.get("GAIAFTCL_INVARIANT_NPM_INSTALL", "").strip() == "1"):
                ir, msg = _npm_install_if_needed(ui_dir, log_path)
                did_install = True
                trace.append({"attempt": attempt, "npm_install": {"ok": ir, "detail": msg}})
                if not ir:
                    if attempt < max_attempts:
                        time.sleep(3)
                        continue
                    return False, {
                        "reason": "npm_install_failed",
                        "fusion_ui_port": ctx.fusion_ui_port,
                        "attempts_trace": trace,
                        "npm_install_detail": msg,
                    }

            if node_server_running:
                proc = _AliveDummy()
                trace.append({"attempt": attempt, "dev_server_running": True})
            else:
                with open(log_path, "ab", buffering=0) as logf:
                    logf.write(f"\n--- invariant bootstrap attempt {attempt} {utc_now()} ---\n".encode())
                    proc = subprocess.Popen(
                        ["npm", "run", "dev:fusion"],
                        cwd=str(ui_dir),
                        env=env,
                        stdout=logf,
                        stderr=subprocess.STDOUT,
                        start_new_session=True,
                    )
                proc_started = True
                pid_path.write_text(str(proc.pid) + "\n", encoding="utf-8")
                trace.append({"attempt": attempt, "dev_server_started": proc.pid})
        else:
            proc = _AliveDummy()

        br: dict[str, Any] = {
            "attempt": attempt,
            "attempt_mode": "dev" if dev_proxy_mode else "static",
            "app_live": live_meta.get("already_running") or live_meta.get("spin_signature"),
        }
        ok, last_rc, waited, meta = _poll_until_s4_ready(ctx, proc, base_wait, grace)
        br["waited_sec"] = waited
        br["poll_meta"] = meta
        br["last_probe_rc"] = last_rc
        trace.append(br)

        if ok:
            return True, {
                "started": True,
                "fusion_ui_port": ctx.fusion_ui_port,
                "waited_sec": waited,
                "bootstrap_attempt": attempt,
                "attempts_trace": trace,
                "log": str(log_path.relative_to(ctx.root)),
                "pid_file": str(pid_path.relative_to(ctx.root)),
                "dev_proxy_mode": dev_proxy_mode,
            }

        if dev_proxy_mode and proc_started and proc.poll() is None:
            br["result"] = "s4_unreachable_while_dev_server_running_recycling"
            try:
                proc.terminate()
                proc.wait(timeout=20)
            except Exception:  # noqa: BLE001
                try:
                    proc.kill()
                    proc.wait(timeout=8)
                except Exception:  # noqa: BLE001
                    pass
        elif proc_started:
            br["result"] = "dev_server_exited_before_s4_ready"

        time.sleep(3)

    tail = ""
    try:
        tail = log_path.read_text(encoding="utf-8", errors="replace")[-4000:]
    except Exception:  # noqa: BLE001
        pass
    return False, {
        "reason": "bootstrap_exhausted",
        "fusion_ui_port": ctx.fusion_ui_port,
        "attempts_trace": trace,
        "log_tail": tail,
        "log": str(log_path.relative_to(ctx.root)),
    }


def gate_rust_app_build(ctx: Ctx) -> tuple[bool, dict[str, Any]]:
    rc, out = run_cmd(
        ["cargo", "build", "--release", "--manifest-path", "services/fusion_control_mac/Cargo.toml"],
        cwd=ctx.root,
        timeout=_cargo_release_build_timeout_sec(),
    )
    return rc == 0, {"build_rc": rc, "build_tail": "\n".join(out.splitlines()[-20:])}


def gate_mac_fusion_app_build(ctx: Ctx) -> tuple[bool, dict[str, Any]]:
    """SwiftPM Fusion Mac app — release build with stderr capture and per-attempt receipts."""
    if sys.platform != "darwin":
        return True, {"skipped": True, "reason": "non_darwin", "platform": sys.platform}

    serial = getattr(ctx, "_mac_fusion_build_serial", 0) + 1
    setattr(ctx, "_mac_fusion_build_serial", serial)

    manifest = ctx.root / "macos" / "GaiaFusion" / "Package.swift"
    if not manifest.is_file():
        return False, {
            "reason": "missing_manifest",
            "path": str(manifest.relative_to(ctx.root)),
            "spin_signature": "build:missing_manifest",
        }

    cmd = [
        "swift",
        "build",
        "--package-path",
        "macos/GaiaFusion",
        "--configuration",
        "release",
    ]
    timeout_sec = _cargo_release_build_timeout_sec()
    t0 = time.perf_counter()
    try:
        cp = subprocess.run(
            cmd,
            cwd=str(ctx.root),
            capture_output=True,
            text=True,
            timeout=timeout_sec,
            check=False,
        )
        rc = cp.returncode
        stderr_tail = (cp.stderr or "")[-3000:]
        combined = ((cp.stderr or "") + (cp.stdout or ""))[-4000:]
    except subprocess.TimeoutExpired:
        rc = 124
        stderr_tail = f"build_timeout_{timeout_sec}s"
        combined = stderr_tail
    except FileNotFoundError as e:
        rc = 127
        stderr_tail = str(e)
        combined = stderr_tail

    duration = round(time.perf_counter() - t0, 1)
    err_hash = hashlib.md5(stderr_tail.encode("utf-8", errors="replace"), usedforsecurity=False).hexdigest()[:12]
    witness: dict[str, Any] = {
        "build_rc": rc,
        "artifact": "macos/GaiaFusion/.build/release/GaiaFusion",
        "build_tail": "\n".join(combined.splitlines()[-28:]),
        "stderr_tail": stderr_tail,
        "duration_sec": duration,
        "attempt_serial": serial,
        "spin_signature": f"build:swift_native_mac:{err_hash}",
    }
    _heartbeat_emit(ctx, "mac_build", exit_code=rc, duration_sec=duration, attempt_serial=serial)

    if rc == 0:
        return True, witness

    ctx.evidence_dir.mkdir(parents=True, exist_ok=True)
    safe_ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    attempt_path = ctx.evidence_dir / f"BUILD_ATTEMPT_{serial}_{safe_ts}.json"
    try:
        attempt_path.write_text(
            json.dumps(
                {
                    "ts_utc": utc_now(),
                    "gate": "macFusionAppBuildGate",
                    **{k: witness[k] for k in witness if k != "spin_signature"},
                },
                indent=2,
            ),
            encoding="utf-8",
        )
        witness["build_attempt_artifact"] = str(attempt_path.relative_to(ctx.root))
    except OSError:
        witness["build_attempt_artifact"] = str(attempt_path)

    return False, witness


def gate_mac_fusion_app_test(ctx: Ctx) -> tuple[bool, dict[str, Any]]:
    """SwiftPM tests on Mac GaiaFusion package — CURE requires tests green, not only HTTP."""
    if sys.platform != "darwin":
        return True, {"skipped": True, "reason": "non_darwin", "platform": sys.platform}

    test_timeout = max(120, int(os.environ.get("GAIAFTCL_INVARIANT_CARGO_TEST_TIMEOUT_SEC", "3600")))
    cmd = [
        "swift",
        "test",
        "--package-path",
        "macos/GaiaFusion",
        "--",
    ]
    try:
        cp = subprocess.run(
            cmd,
            cwd=str(ctx.root),
            capture_output=True,
            text=True,
            timeout=test_timeout,
            check=False,
        )
        rc = cp.returncode
        out = (cp.stdout or "") + (cp.stderr or "")
    except subprocess.TimeoutExpired:
        rc = 124
        out = f"cargo_test_timeout_{test_timeout}s"
    except FileNotFoundError as e:
        rc = 127
        out = str(e)

    low = out.lower()
    tests_ran = "test passed" in low or "passed" in low or "swift test" in low
    ok = rc == 0
    tail = "\n".join(out.splitlines()[-40:])
    th = hashlib.md5(tail.encode("utf-8", errors="replace"), usedforsecurity=False).hexdigest()[:12]
    witness: dict[str, Any] = {
        "test_rc": rc,
        "tests_ran": tests_ran,
        "test_tail": tail,
    }
    if not ok:
        witness["spin_signature"] = f"test:native_swift_fusion:{th}"
    return ok, witness


def gate_mac_fusion_app_live_run(ctx: Ctx) -> tuple[bool, dict[str, Any]]:
    """
    Ensure the native Fusion process is running: if already up (pgrep), pass; else start from known paths,
    wait, verify alive. When this gate starts the process, it is left running (healing gate).
    Set GAIAFTCL_INVARIANT_MAC_APP_LIVE_RUN=0 to skip even on macOS (emergency only).
    """
    if os.environ.get("GAIAFTCL_INVARIANT_MAC_APP_LIVE_RUN", "").strip() == "0":
        return True, {"skipped": True, "reason": "GAIAFTCL_INVARIANT_MAC_APP_LIVE_RUN=0"}
    if sys.platform != "darwin":
        return True, {
            "skipped": True,
            "reason": "mac_fusion_app_live_run_requires_darwin_skipped_on_ci",
            "platform": sys.platform,
        }

    hold = float(os.environ.get("GAIAFTCL_INVARIANT_MAC_APP_LIVE_HOLD_SEC", "8"))
    stale_cleanup: dict[str, Any] | None = None
    was_running_without_window = False
    window_probe_for_missing_window: dict[str, Any] | None = None

    try:
        cp = subprocess.run(
            ["pgrep", "-f", "GaiaFusion"],
            capture_output=True,
            text=True,
            timeout=8,
            check=False,
        )
        if cp.returncode == 0 and (cp.stdout or "").strip():
            window_ok, window_witness = probe_fusion_window_visible(ctx)
            if window_ok:
                return True, {
                    "already_running": True,
                    "pgrep_stdout": (cp.stdout or "").strip()[:200],
                    "spin_signature": "live_run:already_running",
                    "window_probe": window_witness,
                }

            was_running_without_window = True
            window_probe_for_missing_window = window_witness
            stale_cleanup = _cleanup_existing_gaiafusion_processes(ctx)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False, {
            "pgrep_failed": True,
            "spin_signature": "live_run:pgrep_failed",
        }
    except Exception as e:  # noqa: BLE001
        return False, {
            "pgrep_error": f"{type(e).__name__}: {e}",
            "spin_signature": "live_run:pgrep_error",
        }

    if was_running_without_window and stale_cleanup is None:
        try:
            stale_cleanup = _cleanup_existing_gaiafusion_processes(ctx)
        except Exception as e:  # noqa: BLE001
            stale_cleanup = {"cleanup_error": f"{type(e).__name__}: {e}"}

    bin_release = ctx.root / "macos" / "GaiaFusion" / ".build" / "release" / "GaiaFusion"
    app_bundle_bin = Path("/Applications/GaiaFusion.app/Contents/MacOS/GaiaFusion")
    candidates: list[Path] = []
    if app_bundle_bin.is_file():
        candidates.append(app_bundle_bin)
    if bin_release.is_file():
        candidates.append(bin_release)

    if not candidates:
        return False, {
            "reason": "missing_binary",
            "tried": [str(app_bundle_bin), str(bin_release)],
            "spin_signature": "live_run:no_binary",
        }

    log_path = ctx.evidence_dir / "mac_fusion_app_live_run.log"
    ctx.evidence_dir.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["GAIA_ROOT"] = str(ctx.root)

    started_from: Path | None = None
    proc: subprocess.Popen[str] | None = None
    for bin_path in candidates:
        with open(log_path, "ab", buffering=0) as logf:
            logf.write(f"\n--- live run start {utc_now()} {bin_path} ---\n".encode())
            proc = subprocess.Popen(
                [str(bin_path)],
                cwd=str(bin_path.parent),
                env=env,
                stdout=logf,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
        started_from = bin_path
        break

    assert proc is not None and started_from is not None
    t0 = time.time()
    time.sleep(max(0.5, hold))
    poll = proc.poll()
    elapsed = time.time() - t0

    try:
        bin_disp = str(started_from.relative_to(ctx.root))
    except ValueError:
        bin_disp = str(started_from)

    witness: dict[str, Any] = {
        "pid": proc.pid,
        "hold_sec_config": hold,
        "elapsed_sec": round(elapsed, 3),
        "poll_after_hold": poll,
        "binary": bin_disp,
        "log": str(log_path.relative_to(ctx.root)),
        "started_left_running": True,
        "spin_signature": f"live_run:started:{started_from.name}",
    }
    if stale_cleanup is not None:
        witness["cleanup_witness"] = stale_cleanup
    if was_running_without_window:
        witness["recovered_from_stale_window_missing"] = True
        if window_probe_for_missing_window is not None:
            witness["prior_window_probe"] = window_probe_for_missing_window

    if poll is not None:
        tail = ""
        try:
            tail = log_path.read_text(encoding="utf-8", errors="replace")[-2500:]
        except OSError:
            pass
        witness["early_exit"] = True
        witness["exit_code"] = poll
        witness["log_tail"] = tail
        witness.pop("started_left_running", None)
        return False, witness

    return True, witness


def gate_metal_runtime(ctx: Ctx) -> tuple[bool, dict[str, Any]]:
    bin_path = ctx.root / "services" / "fusion_control_mac" / "target" / "release" / "fusion_control"
    if not bin_path.is_file():
        return False, {"reason": "missing_binary", "path": str(bin_path)}
    metallib_candidates = [
        ctx.root / "services" / "fusion_control_mac" / "dist" / "FusionControl.app" / "Contents" / "Resources" / "default.metallib",
        ctx.root / "services" / "fusion_control_mac" / "default.metallib",
    ]
    metallib = next((p for p in metallib_candidates if p.is_file()), None)
    env_prefix = f"FUSION_METALLIB='{metallib}' " if metallib else ""
    rc, out = run_cmd(
        ["bash", "-lc", f"{env_prefix}'{bin_path}' --cycles 16"],
        cwd=ctx.root,
        timeout=180,
    )
    ok = False
    parsed: dict[str, Any] = {}
    try:
        parsed = json.loads(out)
        ok = bool(parsed.get("ok")) and parsed.get("validation_engine") == "gpu_fused_multicycle"
    except Exception:  # noqa: BLE001
        ok = False
    return rc == 0 and ok, {
        "exec_rc": rc,
        "metallib_used": str(metallib) if metallib else None,
        "receipt": parsed if parsed else out[-800:],
    }


def gate_s4c4_projection(ctx: Ctx) -> tuple[bool, dict[str, Any]]:
    ok, rc, out, doc = probe_fusion_s4_projection(ctx)
    schema = doc.get("schema")
    nested_schema = None
    if isinstance(doc.get("projection_s4"), dict):
        nested_schema = doc["projection_s4"].get("schema")
    return ok, {"http_rc": rc, "schema": schema, "projection_schema": nested_schema, "tail": out[-400:]}


def gate_mesh_connectivity(ctx: Ctx) -> tuple[bool, dict[str, Any]]:
    ok, rc, out, doc = probe_sovereign_mesh(ctx)
    panels = doc.get("panels") if isinstance(doc, dict) else {}
    return ok, {"http_rc": rc, "has_mesh_cells": isinstance(panels, dict) and "mesh_cells" in panels}


def gate_arango_query(ctx: Ctx) -> tuple[bool, dict[str, Any]]:
    rc, out = run_cmd(["bash", "-lc", "docker ps --format '{{.Names}}'"], cwd=ctx.root, timeout=20)
    names = [x.strip() for x in out.splitlines() if x.strip()]
    ok = rc == 0 and any("arangodb" in n for n in names)
    return ok, {"docker_rc": rc, "arangodb_present": ok, "names_sample": names[:20]}


def gate_gnn_inference(ctx: Ctx) -> tuple[bool, dict[str, Any]]:
    rc, out = run_cmd(["bash", "-lc", "docker ps --format '{{.Names}}'"], cwd=ctx.root, timeout=20)
    names = [x.strip() for x in out.splitlines() if x.strip()]
    container_ok = rc == 0 and any("akg" in n or "gnn" in n for n in names)
    binary_ok = (ctx.root / "services" / "akg_gnn" / "Cargo.toml").is_file()
    ok = container_ok or binary_ok
    return ok, {
        "docker_rc": rc,
        "gnn_container_present": container_ok,
        "gnn_source_present": binary_ok,
        "names_sample": names[:20],
    }


def gate_menu_coverage(ctx: Ctx, minimum: int) -> tuple[bool, dict[str, Any]]:
    p = ctx.root / "spec" / "native_fusion" / "menu_command_registry.json"
    if not p.is_file():
        return False, {"reason": "missing_registry", "path": str(p)}
    doc = json.loads(p.read_text(encoding="utf-8"))
    cmds = doc.get("commands") if isinstance(doc, dict) else []
    count = len(cmds) if isinstance(cmds, list) else 0
    return count >= minimum, {"command_count": count, "required_min": minimum, "path": str(p)}


def gate_sidecar_control_surface(ctx: Ctx) -> tuple[bool, dict[str, Any]]:
    bridge_file = ctx.root / "macos" / "GaiaFusion" / "GaiaFusion" / "FusionBridge.swift"
    menu_file = ctx.root / "macos" / "GaiaFusion" / "GaiaFusion" / "AppMenu.swift"
    if not bridge_file.is_file() or not menu_file.is_file():
        return False, {
            "reason": "missing_control_surface_files",
            "fusion_bridge_path": str(bridge_file),
            "app_menu_path": str(menu_file),
        }

    bridge = bridge_file.read_text(encoding="utf-8")
    menu = menu_file.read_text(encoding="utf-8")
    has_bridge = ("fusionBridge" in bridge) and ("window.fusionReceive" in bridge)
    has_menu = ("onSwapSelected" in menu) and (
        ("CommandMenu" in menu) or ("CommandGroup" in menu)
    )
    return (
        has_bridge and has_menu,
        {
            "fusion_bridge_path": str(bridge_file),
            "app_menu_path": str(menu_file),
            "has_fusion_bridge_binding": has_bridge,
            "has_menu_actions": has_menu,
        },
    )


def gate_plant_adapter(ctx: Ctx, min_kinds: int) -> tuple[bool, dict[str, Any]]:
    p = ctx.root / "spec" / "native_fusion" / "plant_adapters.json"
    if not p.is_file():
        return False, {"reason": "missing_adapter_contract", "path": str(p)}
    doc = json.loads(p.read_text(encoding="utf-8"))
    kinds = doc.get("kinds") if isinstance(doc, dict) else []
    count = len(kinds) if isinstance(kinds, list) else 0
    return count >= min_kinds, {"path": str(p), "adapter_kinds": count, "required_min": min_kinds}


def gate_plug_and_play_receipts(ctx: Ctx) -> tuple[bool, dict[str, Any]]:
    p = ctx.root / "evidence" / "native_fusion" / "plant_hot_swap_witness.json"
    if not p.is_file():
        return False, {"reason": "missing_hot_swap_receipt", "path": str(p)}
    doc = json.loads(p.read_text(encoding="utf-8"))
    ok = (
        doc.get("terminal") in {"CALORIE", "CURE"}
        and bool(doc.get("from_kind"))
        and bool(doc.get("to_kind"))
        and doc.get("from_kind") != doc.get("to_kind")
    )
    return ok, {"path": str(p), "from_kind": doc.get("from_kind"), "to_kind": doc.get("to_kind")}


def gate_file_contract(ctx: Ctx, filename: str, key: str) -> tuple[bool, dict[str, Any]]:
    p = ctx.root / "evidence" / "native_fusion" / filename
    if not p.is_file():
        return False, {"reason": "missing_receipt", "path": str(p)}
    doc = json.loads(p.read_text(encoding="utf-8"))
    ok = doc.get("terminal") in {"CALORIE", "CURE"} and bool(doc.get(key, True))
    return ok, {"path": str(p), "terminal": doc.get("terminal"), "key": key}


def gate_fusion_app_full_operational(ctx: Ctx) -> tuple[bool, dict[str, Any]]:
    """
    Final substantive gate: full Fusion operator surface is up (APIs + S⁴ page + fleet digest).
    Self-heal: on first failing round try ``start_fusion_local.sh`` (Popen) then ``ensure_fusion_ui_surface``;
    periodic ensure every 4 rounds thereafter.
    """
    max_rounds = int(os.environ.get("GAIAFTCL_INVARIANT_APP_HEALTH_RETRIES", "24"))
    delay = float(os.environ.get("GAIAFTCL_INVARIANT_APP_HEALTH_DELAY_SEC", "3"))
    post_script_sleep = float(os.environ.get("GAIAFTCL_INVARIANT_FUSION_UI_SCRIPT_HEAL_SEC", "10"))
    self_heal = os.environ.get("GAIAFTCL_INVARIANT_APP_SELF_HEAL", "1").strip() != "0"
    rounds: list[dict[str, Any]] = []
    start_script = ctx.root / "scripts" / "start_fusion_local.sh"

    def _snap(r: int) -> dict[str, Any]:
        s4_ok, _, _, _ = probe_fusion_s4_projection(ctx)
        mesh_ok, _, _, _ = probe_sovereign_mesh(ctx)
        page_ok, _, _ = probe_get_http_status(ctx, "/fusion-s4")
        fleet_ok, _, _ = probe_fleet_digest(ctx)
        surface_ok, page_source_rc, page_source = probe_fusion_s4_page_source(ctx)
        required_ui_ids = [
            "fusion-cell-grid",
            "fusion-plant-controls",
            "fusion-swap-panel",
            "fusion-topology-view",
            "fusion-projection-panel",
        ]
        ui_ids_present = {ui_id: (f'id="{ui_id}"' in page_source or f"id='{ui_id}'" in page_source) for ui_id in required_ui_ids}
        ui_bridge = ("fusionBridge" in page_source and "fusionReceive" in page_source) or _fusion_chunk_bridge_tokens_present(
            ctx,
            page_source,
        )
        return {
            "round": r,
            "s4_projection": s4_ok,
            "sovereign_mesh": mesh_ok,
            "fusion_s4_page": page_ok,
            "fleet_digest": fleet_ok,
            "fusion_s4_surface": surface_ok and all(ui_ids_present.values()) and ui_bridge,
            "fusion_s4_page_rc": page_source_rc,
            "fusion_s4_page_status": page_source_rc,
            "fusion_s4_page_source_len": len(page_source),
            "fusion_s4_page_source_head": page_source[:240],
            "fusion_s4_ui_ids": ui_ids_present,
            "fusion_s4_bridge_hooks": ui_bridge,
        }

    for r in range(1, max_rounds + 1):
        snap = _snap(r)

        if self_heal:
            need_heal = not (
                snap["s4_projection"]
                and snap["sovereign_mesh"]
                and snap["fusion_s4_page"]
                and snap["fleet_digest"]
                and snap["fusion_s4_surface"]
            )
            if need_heal and r == 1:
                heal_meta: dict[str, Any] = {}
                if start_script.is_file():
                    env = os.environ.copy()
                    env["GAIA_ROOT"] = str(ctx.root)
                    env["FUSION_UI_PORT"] = ctx.fusion_ui_port
                    subprocess.Popen(
                        ["/bin/bash", str(start_script)],
                        cwd=str(ctx.root),
                        env=env,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        start_new_session=True,
                    )
                    heal_meta["start_fusion_local_popen"] = str(start_script.relative_to(ctx.root))
                    time.sleep(post_script_sleep)
                sh_ok, sh_w = ensure_fusion_ui_surface(ctx)
                heal_meta["ensure_fusion_ui_surface"] = {"ok": sh_ok, "keys": list(sh_w.keys())}
                snap = _snap(r)
                snap["self_heal_round1"] = heal_meta
            elif need_heal and r > 1 and r % 4 == 0:
                sh_ok, sh_w = ensure_fusion_ui_surface(ctx)
                snap["self_heal_ensure"] = {"ok": sh_ok, "keys": list(sh_w.keys())}
                snap = _snap(r)

        rounds.append(snap)

        if (
            snap["s4_projection"]
            and snap["sovereign_mesh"]
            and snap["fusion_s4_page"]
            and snap["fleet_digest"]
            and snap["fusion_s4_surface"]
        ):
            return True, {
                "operational": True,
                "recovered_on_round": r,
                "rounds_sample": rounds[-min(12, len(rounds)) :],
                "final_checks": snap,
            }

        time.sleep(delay)

    last = rounds[-1] if rounds else {}
    sig_bits = [str(last.get(k, "")) for k in ("s4_projection", "sovereign_mesh", "fusion_s4_page", "fleet_digest", "fusion_s4_surface")]
    return False, {
        "operational": False,
        "reason": "operational_exhausted",
        "rounds_sample": rounds[-min(16, len(rounds)) :],
        "spin_signature": "fusion_op:" + ",".join(sig_bits),
        "heal_why": "Probed S4 / sovereign mesh / fusion-s4 page / fleet-digest; ran start_fusion_local.sh "
        "and ensure_fusion_ui_surface on round 1 when needed — still not operational.",
    }


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()


def _witness_bundle_sha256(evidence_dir: Path) -> tuple[str, list[dict[str, Any]]]:
    """Deterministic hash over sealed evidence JSON files (path, size, file_sha256)."""
    parts: list[bytes] = []
    entries: list[dict[str, Any]] = []
    for name in sorted(EVIDENCE_WITNESS_FILES_FOR_SEAL):
        p = evidence_dir / name
        if not p.is_file():
            continue
        raw = p.read_bytes()
        fh = _sha256_bytes(raw)
        parts.append(f"{name}\0{len(raw)}\0{fh}\n".encode())
        entries.append({"file": name, "bytes": len(raw), "sha256": fh})
    bundle = b"".join(parts)
    return _sha256_bytes(bundle), entries


def _s4_projection_accept(rc: int, out: str, doc: dict[str, Any]) -> bool:
    if rc != 0:
        return False
    schema = doc.get("schema")
    nested_schema = None
    if isinstance(doc.get("projection_s4"), dict):
        nested_schema = doc["projection_s4"].get("schema")
    return (
        schema == "gaiaftcl_fusion_s4_projection_ui_v1"
        or nested_schema == "gaiaftcl_fusion_s4_projection_ui_v1"
        or "fusion_moor_aggregate" in doc
        or "fusion_moor_aggregate" in out
    )


def _mesh_connectivity_accept(rc: int, doc: dict[str, Any]) -> bool:
    if rc != 0:
        return False
    panels = doc.get("panels") if isinstance(doc, dict) else {}
    return isinstance(panels, dict) and "mesh_cells" in panels


def gate_sub_sealing(
    ctx: Ctx,
    contract: dict[str, Any],
    prior_gate_results: list[dict[str, Any]],
    run_id: str,
) -> tuple[bool, dict[str, Any]]:
    """Final gate: contract fingerprint, evidence bundle hash, anti-entropy HTTP re-probes, seal files."""
    if len(prior_gate_results) != len(GATES):
        return False, {
            "reason": "gate_count_mismatch",
            "expected_gates": len(GATES),
            "got": len(prior_gate_results),
        }
    if not all(g.get("ok") for g in prior_gate_results):
        return False, {"reason": "prior_gate_failed", "failed_names": [g["gate"] for g in prior_gate_results if not g.get("ok")]}

    contract_sha = _sha256_file(ctx.contract_path)
    bundle_sha, bundle_entries = _witness_bundle_sha256(ctx.evidence_dir)
    if len(bundle_entries) != len(EVIDENCE_WITNESS_FILES_FOR_SEAL):
        missing = [n for n in EVIDENCE_WITNESS_FILES_FOR_SEAL if not (ctx.evidence_dir / n).is_file()]
        return False, {"reason": "witness_bundle_incomplete", "missing_files": missing}

    # Anti-entropy: re-probe local Fusion HTTP surface (same URLs as earlier gates).
    s4_ok, rc_s4, out_s4, doc_s4 = probe_fusion_s4_projection(ctx)
    mesh_ok, rc_m, out_m, doc_m = probe_sovereign_mesh(ctx)

    ok = s4_ok and mesh_ok
    seal_doc = {
        "schema": "gaiaftcl_native_fusion_sub_seal_v1",
        "invariant_id": INVARIANT_ID,
        "run_id": run_id,
        "terminal": EXIT_GATE_TERMINAL if ok else "REFUSED",
        "ts_utc": utc_now(),
        "contract_path": str(ctx.contract_path.relative_to(ctx.root)),
        "contract_sha256": contract_sha,
        "contract_schema": contract.get("schema"),
        "witness_bundle_sha256": bundle_sha,
        "witness_bundle_files": bundle_entries,
        "anti_entropy": {
            "s4_projection": {"http_rc": rc_s4, "closure_ok": s4_ok, "url": _fusion_s4_url(ctx)},
            "sovereign_mesh": {"http_rc": rc_m, "closure_ok": mesh_ok, "url": _fusion_mesh_url(ctx)},
        },
    }

    seal_path = ctx.evidence_dir / f"SUB_SEAL_{run_id}.json"
    latest_seal = ctx.evidence_dir / "LATEST_SUB_SEAL.json"
    seal_path.write_text(json.dumps(seal_doc, indent=2), encoding="utf-8")
    latest_seal.write_text(json.dumps(seal_doc, indent=2), encoding="utf-8")

    witness = {
        "seal_path": str(seal_path.relative_to(ctx.root)),
        "contract_sha256": contract_sha,
        "witness_bundle_sha256": bundle_sha,
        "witness_file_count": len(bundle_entries),
        "anti_entropy_s4_ok": s4_ok,
        "anti_entropy_mesh_ok": mesh_ok,
    }
    return ok, witness


def _policy_refused(witness: dict[str, Any]) -> bool:
    return witness.get("reason") == "refusal_keyword_detected"


def run_sub_seal_with_retries(
    ctx: Ctx,
    contract: dict[str, Any],
    gate_results: list[dict[str, Any]],
    run_id: str,
    refusal_keywords: list[str],
) -> tuple[bool, dict[str, Any]]:
    """subSealingGate must not single-fail: recover surface and re-probe."""
    budget = max(1, int(os.environ.get("GAIAFTCL_INVARIANT_SUBSEAL_RETRY_MAX", "12")))
    delay = float(os.environ.get("GAIAFTCL_INVARIANT_SUBSEAL_RETRY_DELAY_SEC", "3"))
    last_w: dict[str, Any] = {}
    for attempt in range(1, budget + 1):
        ok, witness = gate_sub_sealing(ctx, contract, gate_results, run_id)
        last_w = witness
        wtxt = json.dumps(witness, ensure_ascii=False)
        if contains_refusal_keywords(wtxt, refusal_keywords):
            witness["reason"] = "refusal_keyword_detected"
            return False, witness
        if ok:
            if attempt > 1:
                witness["recovered_on_attempt"] = attempt
            return True, witness
        ensure_fusion_ui_surface(ctx)
        time.sleep(delay)
    last_w["sub_seal_retry_exhausted"] = True
    last_w["attempts"] = budget
    return False, last_w


def run_one_invariant_pass(
    ctx: Ctx,
    contract: dict[str, Any],
    thresholds: dict[str, Any],
    refusal_keywords: list[str],
    pass_run_id: str,
    spin: SpinTracker,
) -> tuple[str, dict[str, Any], bool]:
    """
    Single full pass: toolbox + nine-cell mesh (no Fusion preflight) → Fusion UI preflight → remaining gates → sub-seal.
    Returns (terminal, result, policy_refusal). policy_refusal=True stops outer fix loop (constitutional).
    """
    if tuple(GATES[:2]) != GATES_BEFORE_PREFLIGHT:
        raise RuntimeError("GATES[:2] must match GATES_BEFORE_PREFLIGHT")

    gate_results: list[dict[str, Any]] = []
    _heartbeat_emit(ctx, "pass_start", pass_run_id=pass_run_id)

    early_fns: list[tuple[str, Callable[[], tuple[bool, dict[str, Any]]]]] = [
        ("invariantToolboxGate", lambda: gate_invariant_toolbox(ctx, contract)),
        ("nineCellMeshGreenGate", lambda: gate_nine_cell_mesh_green(ctx)),
    ]
    for name, gfn in early_fns:
        ok, witness = run_gate_with_retries(name, gfn, ctx, refusal_keywords, spin)
        gate_results.append({"gate": name, "ok": ok, "witness": witness})
        _heartbeat_emit(ctx, "gate_done", gate=name, phase="before_preflight", ok=ok)
        if _policy_refused(witness):
            _heartbeat_emit(ctx, "pass_end", terminal="REFUSED", failed_gate=name, policy_refusal=True)
            return (
                "REFUSED",
                {
                    "schema": "gaiaftcl_native_rust_fusion_invariant_receipt_v1",
                    "invariant_id": INVARIANT_ID,
                    "run_id": pass_run_id,
                    "terminal": "REFUSED",
                    "failed_gate": name,
                    "fusion_ui_bootstrap": {"note": "preflight_not_run_early_gate_policy_refusal"},
                    "gate_results": gate_results,
                    "ts_utc": utc_now(),
                    "policy_refusal": True,
                },
                True,
            )
        if witness.get("spin_stall"):
            _heartbeat_emit(ctx, "pass_end", terminal="REFUSED", failed_gate=name, spin_stall=True)
            return (
                "REFUSED",
                {
                    "schema": "gaiaftcl_native_rust_fusion_invariant_receipt_v1",
                    "invariant_id": INVARIANT_ID,
                    "run_id": pass_run_id,
                    "terminal": "REFUSED",
                    "failed_gate": name,
                    "spin_stall": True,
                    "fusion_ui_bootstrap": {"note": "preflight_not_run_spin_stall"},
                    "gate_results": gate_results,
                    "ts_utc": utc_now(),
                    "policy_refusal": False,
                },
                False,
            )
        if not ok:
            _heartbeat_emit(ctx, "pass_end", terminal="REFUSED", failed_gate=name, policy_refusal=False)
            return (
                "REFUSED",
                {
                    "schema": "gaiaftcl_native_rust_fusion_invariant_receipt_v1",
                    "invariant_id": INVARIANT_ID,
                    "run_id": pass_run_id,
                    "terminal": "REFUSED",
                    "failed_gate": name,
                    "fusion_ui_bootstrap": {"note": "preflight_not_run_early_gate_failed"},
                    "gate_results": gate_results,
                    "ts_utc": utc_now(),
                    "policy_refusal": False,
                },
                False,
            )

    bootstrap_ok, bootstrap_witness = run_preflight_phases(ctx, refusal_keywords)
    bw_txt = json.dumps(bootstrap_witness, ensure_ascii=False)
    if contains_refusal_keywords(bw_txt, refusal_keywords):
        bootstrap_ok = False
        bootstrap_witness["reason"] = "refusal_keyword_detected"

    if not bootstrap_ok:
        pol = bootstrap_witness.get("reason") == "refusal_keyword_detected"
        _heartbeat_emit(
            ctx,
            "preflight_done",
            ok=False,
            failed_gate="preflightFusionUi",
            policy_refusal=pol,
        )
        _heartbeat_emit(ctx, "pass_end", terminal="REFUSED", failed_gate="preflightFusionUi", policy_refusal=pol)
        return (
            "REFUSED",
            {
                "schema": "gaiaftcl_native_rust_fusion_invariant_receipt_v1",
                "invariant_id": INVARIANT_ID,
                "run_id": pass_run_id,
                "terminal": "REFUSED",
                "failed_gate": "preflightFusionUi",
                "fusion_ui_bootstrap": bootstrap_witness,
                "gate_results": gate_results,
                "ts_utc": utc_now(),
                "policy_refusal": pol,
            },
            pol,
        )

    _heartbeat_emit(ctx, "preflight_done", ok=True, failed_gate=None, policy_refusal=False)

    menu_min = int(thresholds.get("menu_command_count_min", 63))
    plant_min = int(thresholds.get("plant_adapter_kinds_min", 6))

    gate_fns: list[tuple[str, Callable[[], tuple[bool, dict[str, Any]]]]] = [
        ("macFusionAppBuildGate", lambda: gate_mac_fusion_app_build(ctx)),
        ("macFusionAppTestGate", lambda: gate_mac_fusion_app_test(ctx)),
        ("macFusionAppLiveRunGate", lambda: gate_mac_fusion_app_live_run(ctx)),
        ("moorOnboardGate", lambda: gate_moor_onboard_requirements(ctx)),
        ("rustAppBuildGate", lambda: gate_rust_app_build(ctx)),
        ("metalRuntimeGate", lambda: gate_metal_runtime(ctx)),
        ("macDiscordActivitiesGate", lambda: gate_mac_discord_activities(ctx)),
        ("macNatsTunnelContractGate", lambda: gate_mac_nats_tunnel_contract(ctx)),
        ("meshFleetSnapshotParityGate", lambda: gate_mesh_fleet_snapshot_parity(ctx)),
        ("s4c4ProjectionGate", lambda: gate_s4c4_projection(ctx)),
        ("meshConnectivityGate", lambda: gate_mesh_connectivity(ctx)),
        ("arangoQueryGate", lambda: gate_arango_query(ctx)),
        ("gnnInferenceGate", lambda: gate_gnn_inference(ctx)),
        ("nativeMenuActionCoverageGate", lambda: gate_menu_coverage(ctx, menu_min)),
        ("sidecarControlSurfaceGate", lambda: gate_sidecar_control_surface(ctx)),
        ("plantAdapterContractGate", lambda: gate_plant_adapter(ctx, plant_min)),
        ("plantHotSwapGate", lambda: gate_plug_and_play_receipts(ctx)),
        ("protectionInterlockGate", lambda: gate_file_contract(ctx, "protection_interlock_witness.json", "interlock_ok")),
        ("iso25010QualityGate", lambda: gate_file_contract(ctx, "iso25010_quality_witness.json", "quality_ok")),
        ("functionalSafetyLifecycleGate", lambda: gate_file_contract(ctx, "functional_safety_witness.json", "safety_ok")),
        ("facilityMiddlewareCompatGate", lambda: gate_file_contract(ctx, "facility_middleware_witness.json", "compat_ok")),
        ("fatConformanceGate", lambda: gate_file_contract(ctx, "fat_stage_witness.json", "fat_ok")),
        ("satNetworkSecurityGate", lambda: gate_file_contract(ctx, "sat_stage_witness.json", "sat_ok")),
        ("commissioningLoadGate", lambda: gate_file_contract(ctx, "commissioning_stage_witness.json", "commissioning_ok")),
        ("longSoakStabilityGate", lambda: gate_file_contract(ctx, "long_soak_stage_witness.json", "soak_ok")),
        ("fusionAppFullOperationalGate", lambda: gate_fusion_app_full_operational(ctx)),
    ]

    if len(gate_fns) != len(GATES) - 2:
        raise RuntimeError("gate_fns length must match GATES minus preflight pair")

    terminal = EXIT_GATE_TERMINAL
    failed_gate = None
    for name, gfn in gate_fns:
        ok, witness = run_gate_with_retries(name, gfn, ctx, refusal_keywords, spin)
        gate_results.append({"gate": name, "ok": ok, "witness": witness})
        _heartbeat_emit(ctx, "gate_done", gate=name, phase="after_preflight", ok=ok)
        if _policy_refused(witness):
            _heartbeat_emit(ctx, "pass_end", terminal="REFUSED", failed_gate=name, policy_refusal=True)
            return (
                "REFUSED",
                {
                    "schema": "gaiaftcl_native_rust_fusion_invariant_receipt_v1",
                    "invariant_id": INVARIANT_ID,
                    "run_id": pass_run_id,
                    "terminal": "REFUSED",
                    "failed_gate": name,
                    "fusion_ui_bootstrap": bootstrap_witness,
                    "gate_results": gate_results,
                    "ts_utc": utc_now(),
                    "policy_refusal": True,
                },
                True,
            )
        if witness.get("spin_stall"):
            _heartbeat_emit(ctx, "pass_end", terminal="REFUSED", failed_gate=name, spin_stall=True)
            return (
                "REFUSED",
                {
                    "schema": "gaiaftcl_native_rust_fusion_invariant_receipt_v1",
                    "invariant_id": INVARIANT_ID,
                    "run_id": pass_run_id,
                    "terminal": "REFUSED",
                    "failed_gate": name,
                    "spin_stall": True,
                    "fusion_ui_bootstrap": bootstrap_witness,
                    "gate_results": gate_results,
                    "ts_utc": utc_now(),
                    "policy_refusal": False,
                },
                False,
            )
        if not ok and failed_gate is None:
            failed_gate = name
            terminal = "REFUSED"

    if terminal == EXIT_GATE_TERMINAL:
        ok_seal, seal_witness = run_sub_seal_with_retries(ctx, contract, gate_results, pass_run_id, refusal_keywords)
        seal_txt = json.dumps(seal_witness, ensure_ascii=False)
        if contains_refusal_keywords(seal_txt, refusal_keywords):
            ok_seal = False
            seal_witness["reason"] = "refusal_keyword_detected"
        gate_results.append({"gate": "subSealingGate", "ok": ok_seal, "witness": seal_witness})
        _heartbeat_emit(ctx, "gate_done", gate="subSealingGate", phase="after_preflight", ok=ok_seal)
        if _policy_refused(seal_witness):
            _heartbeat_emit(
                ctx,
                "pass_end",
                terminal="REFUSED",
                failed_gate="subSealingGate",
                policy_refusal=True,
            )
            return (
                "REFUSED",
                {
                    "schema": "gaiaftcl_native_rust_fusion_invariant_receipt_v1",
                    "invariant_id": INVARIANT_ID,
                    "run_id": pass_run_id,
                    "terminal": "REFUSED",
                    "failed_gate": "subSealingGate",
                    "fusion_ui_bootstrap": bootstrap_witness,
                    "gate_results": gate_results,
                    "ts_utc": utc_now(),
                    "policy_refusal": True,
                },
                True,
            )
        if not ok_seal:
            failed_gate = "subSealingGate"
            terminal = "REFUSED"
    else:
        gate_results.append(
            {
                "gate": "subSealingGate",
                "ok": False,
                "witness": {
                    "reason": "skipped_prior_refused",
                    "note": "subSealingGate runs only after all prior gates pass (exit gate is CURE)",
                },
            }
        )
        _heartbeat_emit(
            ctx,
            "gate_done",
            gate="subSealingGate",
            phase="after_preflight",
            ok=False,
            skipped_prior_refused=True,
        )

    _heartbeat_emit(
        ctx,
        "pass_end",
        terminal=terminal,
        failed_gate=failed_gate,
        policy_refusal=False,
    )

    result: dict[str, Any] = {
        "schema": "gaiaftcl_native_rust_fusion_invariant_receipt_v1",
        "invariant_id": INVARIANT_ID,
        "run_id": pass_run_id,
        "terminal": terminal,
        "failed_gate": failed_gate,
        "fusion_ui_bootstrap": bootstrap_witness,
        "gate_results": gate_results,
        "ts_utc": utc_now(),
        "policy_refusal": False,
    }
    if terminal == EXIT_GATE_TERMINAL:
        result["sub_seal_artifacts"] = {
            "latest": str((ctx.evidence_dir / "LATEST_SUB_SEAL.json").relative_to(ctx.root)),
            "run_specific": str((ctx.evidence_dir / f"SUB_SEAL_{pass_run_id}.json").relative_to(ctx.root)),
        }
        result["klein_bottle"] = {
            "fold": "inside=outside",
            "exit_gate": EXIT_GATE_TERMINAL,
            "open_sore_rule": "Unrun files are not CURE — this receipt exists because gates executed in this run.",
            "note": "CURE = toolbox + nineCellMeshGreenGate (9/9 WAN :8803/health or skipped MESH_HEAL=0) → Fusion preflight → native Mac build/test/live → plasma (rust+Metal) → Activities/tunnel/fleet parity → S⁴ ops + sub-seal.",
        }
    return terminal, result, False


def _print_help() -> None:
    print(
        """Native Rust Fusion invariant runner — mesh-first, then local Mac / plasma / S⁴ gates.

There is no in-process session wall clock. Closure is CURE, REFUSED, or policy stop.

Do NOT wrap this Python process in a short shell timeout (e.g. timeout 120): mesh heal, deploy, and
cargo release builds routinely exceed 10–30+ minutes.

This script does not implement --max-cycles. Outer pass cap: GAIAFTCL_INVARIANT_OUTER_FIX_LOOP_MAX
(0 = unlimited until CURE, default 0).

Environment (selection):
  C4_INVARIANT_FULL_COVERAGE=1     print full-coverage banner; heartbeat records ack
  GAIAFTCL_INVARIANT_HEARTBEAT_JSONL=0   disable MAC_FUSION_SUB_HEARTBEAT_*.jsonl (default: emit)
  GAIAFTCL_INVARIANT_CARGO_RELEASE_BUILD_TIMEOUT_SEC   per cargo release build (default 7200)
  GAIAFTCL_INVARIANT_CARGO_TEST_TIMEOUT_SEC            macFusionAppTestGate (default 3600)
  GAIAFTCL_INVARIANT_SPIN_THRESHOLD                    identical-signature repeats before spin REFUSED (default 12)
  GAIAFTCL_INVARIANT_HEALING_GATE_MIN_RETRIES          floor retries for healing gates when C4_INVARIANT_FULL_COVERAGE=1
  C4_INVARIANT_MESH_NINE_CELL_OFFLINE=1                  skip WAN mesh gate (CI)
  C4_MESH_HEAL_MAX_ATTEMPTS / C4_MESH_HEAL_WAIT_SEC     mesh_healer rounds and SSH-restart settle time

Watch live:
  tail -f evidence/native_fusion/MAC_FUSION_SUB_HEARTBEAT_<run_id>.jsonl
"""
    )


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help", "help"):
        _print_help()
        return 0

    root = Path(__file__).resolve().parents[1]
    evidence = root / "evidence" / "native_fusion"
    evidence.mkdir(parents=True, exist_ok=True)
    base_run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    fusion_ui_port = (os.environ.get("FUSION_UI_PORT") or "8910").strip() or "8910"
    hb_path = evidence / f"MAC_FUSION_SUB_HEARTBEAT_{base_run_id}.jsonl"
    heartbeat = Heartbeat(hb_path, time.monotonic())
    ctx = Ctx(
        root=root,
        contract_path=root / "spec" / "native_rust_fusion_invariant_contract.json",
        receipt_path=evidence / f"NATIVE_RUST_FUSION_INVARIANT_{base_run_id}.json",
        latest_path=evidence / "LATEST_NATIVE_RUST_FUSION_RESULT.json",
        evidence_dir=evidence,
        fusion_ui_port=fusion_ui_port,
        heartbeat=heartbeat,
    )

    if os.environ.get("C4_INVARIANT_FULL_COVERAGE", "").strip() == "1":
        print(
            "C4_INVARIANT_FULL_COVERAGE=1 — full coverage mode: no session time limit inside this process; "
            "do not wrap with `timeout 120`. Mesh + cargo may run 30+ minutes.",
            flush=True,
        )
        heartbeat.emit(
            "full_coverage_ack",
            note="Klein bottle closes on terminal state, not a wall clock on the Python process",
        )
    try:
        contract = load_contract(ctx)
    except Exception as e:  # noqa: BLE001
        print(f"REFUSED contract invalid: {e}")
        return 1

    thresholds = contract.get("thresholds", {})
    refusal_keywords = [str(x) for x in contract.get("refusal_keywords", [])]

    max_outer = int(os.environ.get("GAIAFTCL_INVARIANT_OUTER_FIX_LOOP_MAX", "0"))
    outer_delay = float(os.environ.get("GAIAFTCL_INVARIANT_OUTER_FIX_LOOP_DELAY_SEC", "8"))
    if os.environ.get("C4_INVARIANT_FULL_COVERAGE", "").strip() == "1" and max_outer > 0:
        print(
            f"WARNING: C4_INVARIANT_FULL_COVERAGE=1 but GAIAFTCL_INVARIANT_OUTER_FIX_LOOP_MAX={max_outer} "
            f"(finite outer passes). For unlimited healing until CURE, set OUTER_FIX_LOOP_MAX=0.",
            file=sys.stderr,
            flush=True,
        )
    outer_log: list[dict[str, Any]] = []
    iteration = 0
    spin = SpinTracker()

    heartbeat.emit("session_start", base_run_id=base_run_id, heartbeat_path=str(hb_path.relative_to(root)))

    while True:
        iteration += 1
        pass_run_id = f"{base_run_id}_L{iteration:04d}"
        terminal, result, policy_stop = run_one_invariant_pass(
            ctx, contract, thresholds, refusal_keywords, pass_run_id, spin
        )
        result["outer_fix_loop"] = {
            "iteration": iteration,
            "max_configured": max_outer,
            "unlimited": max_outer <= 0,
        }
        receipt_path = evidence / f"NATIVE_RUST_FUSION_INVARIANT_{pass_run_id}.json"
        ctx.receipt_path = receipt_path
        receipt_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
        ctx.latest_path.write_text(json.dumps(result, indent=2), encoding="utf-8")

        heartbeat.emit(
            "outer_iteration_done",
            iteration=iteration,
            terminal=terminal,
            failed_gate=result.get("failed_gate"),
            policy_stop=policy_stop,
        )

        if terminal == EXIT_GATE_TERMINAL:
            result["outer_fix_loop"]["total_iterations"] = iteration
            result["outer_fix_loop"]["recovery_log"] = outer_log
            receipt_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
            ctx.latest_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
            heartbeat.emit("session_end", terminal=EXIT_GATE_TERMINAL, receipt=str(receipt_path.relative_to(root)))
            print(f"STATE: {EXIT_GATE_TERMINAL}")
            print(f"Receipt: {receipt_path}")
            print(f"Heartbeat: {hb_path.relative_to(root)}", flush=True)
            return 0

        if result.get("spin_stall"):
            result["outer_fix_loop"]["recovery_log"] = outer_log
            receipt_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
            ctx.latest_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
            heartbeat.emit(
                "session_end",
                terminal="REFUSED",
                reason="spin_stall",
                failed_gate=result.get("failed_gate"),
            )
            print(
                "STATE: REFUSED (spin stall — same failure signature repeated; "
                "fix substrate or raise GAIAFTCL_INVARIANT_SPIN_THRESHOLD)",
                flush=True,
            )
            print(f"Receipt: {receipt_path}")
            print(f"Heartbeat: {hb_path.relative_to(root)}", flush=True)
            return 1

        if policy_stop or result.get("policy_refusal"):
            heartbeat.emit("session_end", terminal="REFUSED", reason="policy_outer_stop")
            print(f"STATE: REFUSED (policy — outer loop stopped)")
            print(f"Receipt: {receipt_path}")
            print(f"Heartbeat: {hb_path.relative_to(root)}", flush=True)
            return 1

        if max_outer > 0 and iteration >= max_outer:
            result["outer_fix_loop"]["exhausted"] = True
            result["outer_fix_loop"]["recovery_log"] = outer_log
            receipt_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
            ctx.latest_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
            heartbeat.emit("session_end", terminal="REFUSED", reason="outer_fix_loop_cap", max_outer=max_outer)
            print("STATE: REFUSED (outer fix loop cap — set GAIAFTCL_INVARIANT_OUTER_FIX_LOOP_MAX=0 for unlimited)")
            print(f"Receipt: {receipt_path}")
            print(f"Heartbeat: {hb_path.relative_to(root)}", flush=True)
            return 1

        outer_log.append(
            {
                "iteration": iteration,
                "failed_gate": result.get("failed_gate"),
                "terminal": terminal,
            }
        )
        print(
            f"… recoverable REFUSED (iteration {iteration}); global heal → retry pass "
            f"(next: L{iteration + 1:04d}; cap={'∞' if max_outer <= 0 else max_outer})",
            flush=True,
        )
        _ok, _w = ensure_fusion_ui_surface(ctx)
        outer_log[-1]["post_heal_keys"] = list(_w.keys())
        time.sleep(outer_delay)


if __name__ == "__main__":
    sys.exit(main())
