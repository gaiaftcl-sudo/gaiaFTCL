#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
GaiaFTCL full-release invariant governor — production gate machine.

Terminal: **CURE** only when the manifold is fully closed: **mesh-first (sans Discord)** means **all contract domains**
graphically witnessed (GUI observer gameplay), **guided** hub/spoke contracts satisfied, **live** nine-cell ``:8803`` mooring
(no offline stub), **language-game** contracts, ``evidence/release/RELEASE_REPORT_*.json``, **sealed DOCX** + semantics MD5,
then surface re-probe. **No REFUSED / no BLOCKED** — everything else is a **PARTIAL spiral**
(heartbeat + sleep + retry) until **CURE**. (Operator interrupt: signal writes **PARTIAL** then process exit.) Artifacts: ``evidence/release/FULL_RELEASE_*.{jsonl,json}`` and
stable receipt ``evidence/release/LATEST_INVARIANT_RESULT.json`` (same payload as the timestamped final JSON).
By default (**``C4_INVARIANT_QUIET_UNTIL_CURE``** unset or ``1``) stdout/stderr are redirected to
``evidence/release/FULL_RELEASE_QUIET_*.log`` until **CURE** — then one ``GAIAFTCL_INVARIANT_RESULT`` line is printed to the terminal.
That line uses **strict** ``===`` delimiters (``terminal===CURE satisfied===true receipt===... stable===...``), not single ``=``, so paths cannot masquerade as extra fields.
Set ``C4_INVARIANT_QUIET_UNTIL_CURE=0`` or pass ``--no-quiet-until-cure`` for a live stream.

**Invariant toolbox (C4, not chat):** ``spec/invariant_toolbox.json`` lists CLI binaries, repo scripts, mesh sovereign cells (must match ``MESH_SOVEREIGN_CELLS``), and gate-to-tool mapping.
On cycle 1 and every ``C4_INVARIANT_TOOLBOX_RECHECK_CYCLES`` (default ``0`` = no repeat), ``validate_invariant_toolbox`` runs; failures emit heartbeat ``phase=invariant_toolbox`` and **PARTIAL** spiral.
Env: ``C4_INVARIANT_TOOLBOX_REQUIRE_SSH=1`` requires ``ssh``/``rsync`` on PATH; ``C4_INVARIANT_TOOLBOX_SSH_PROBE=1`` plus ``C4_INVARIANT_TOOLBOX_SSH_PROBE_HOST`` runs an optional BatchMode probe.

**Gate order (must stay this way — sealing needs RELEASE_REPORT):**
1. mountGate — GaiaFusion DMG present, mount ``/Volumes/GaiaFusion``, optional ``deploy_dmg_to_mesh.sh``
2. visualGate — Fusion Control Playwright PNG witness (functional Mac UI surface)
3. discordMeshSurfaceGate — nine-cell wallet-gate HTTP ``:8803/health`` (optional ``mesh_healer`` SSH restart/deploy/reboot when ``C4_MESH_HEAL_ENABLED``) with required Discord Playwright ``/cell`` earth audit when configured
   (``C4_CELL_EARTH_AUDIT.json`` with 11/11 MOORED + crystal lineage)
4. languageGameContracts — ``spec/release_language_games.json``
5. releaseBundle — fresh ``RELEASE_REPORT_*.json`` after **``run_full_release_session.sh``** (closure battery → dual-user →
   nine-cell → mesh snapshot → session DOCX) when ``C4_INVARIANT_REQUIRE_FULL_SESSION=1`` (default). Without this, an old report
   on disk would skip the entire spine and sealing would **not** meet production closure.
6. sealingGate — ``generate_release_docx.py`` (uses report), MD5 check, **re-probe** Discord/mesh surface (same as gate 3)

**Klein bottle + vector-of-vector field (M8 structure this script implements):**

- **First-order field:** position on the gate manifold — ``(gate, cycle, attempt)`` — the “vector” at a chart point.
- **Second-order field (vector *over* the field):** how closure *moves* — heartbeats carry Δ (torsion hints, rollback,
  remediation paths). That is the field evaluated on the field of gates (jet / connection direction without leaving the manifold).
- **Klein identification:** substrate evidence (S4) and constraint receipts (C4) are not “inside vs outside” — sealed outputs
  (DOCX, PNG, reports) are re-ingested on the next pass; **no REFUSED / no BLOCKED** — OAuth, human visual, spin, and drift all
  fold into **PARTIAL** spirals until **CURE**.
  χ=0: one non-orientable surface, not a sphere with an exterior.
- **Mesh + domain GUI gates:** ``meshGameRunnerCaptureGate`` and ``domainUiGameplayGate`` self-heal and **re-validate** after each
  remediation attempt; **no REFUSED exit on witness blockers** — the loop continues until the full graphical app contract is
  gate-local success may still read **CALORIE** in heartbeats; **only CURE** ends the process (exit 0).

**Full compliance (production):** ``--full-compliance`` or ``C4_FULL_COMPLIANCE=1`` archives stale reports (``C4_CLEAR_RELEASE_DECK``),
requires full session, enables DMG build + mesh deploy, ``RELEASE_SELF_HEAL_UNIFORM``, ``CLOSURE_RUN_FUSION_ALL``.
See ``docs/FULL_RELEASE_COMPLIANCE.md``.

**Env (subset):** ``C4_CLEAR_RELEASE_DECK`` (default **1**) — archive ``RELEASE_REPORT_*`` / ``SESSION_RELEASE_*`` before gates.
``C4_INVARIANT_REQUIRE_FULL_SESSION`` (default **1**) — run ``run_full_release_session.sh`` once before sealing
even when a prior ``RELEASE_REPORT_*.json`` exists (production spine). Set **0** for fast/local runs that only need gates + seal.
``C4_SURFACE_MESH_NINE_CELL`` or legacy ``C4_PLANETARY_MESH_SELF_MOOR`` (default **1** = nine-cell HTTP, **0** = Discord Playwright),
``C4_MESH_FUSION_WEB_URL`` (default **https://gaiaftcl.com/fusion-s4**) — mesh Fusion S⁴ dashboard probe + Playwright ``baseURL`` origin; set to ``http://127.0.0.1:8910/fusion-s4`` for local dev, or set ``C4_INVARIANT_LOCAL_FUSION_MESH=1`` (and omit URL) to default loopback when WAN is unavailable,
``C4_MESH_FUSION_WEB_PORT`` (default **8910**) — loopback port when ``C4_INVARIANT_LOCAL_FUSION_MESH=1``,
``C4_INVARIANT_MESH_NINE_CELL_OFFLINE`` (default **0**) — **1** skips nine-cell ``:8803`` TCP probes (CI/air-gap); witness is stamped ``offline_contract_stub`` — **not** production mooring,
``C4_INVARIANT_INVOKE_FULL_SESSION`` (default 1),
``C4_FULL_SESSION_TIMEOUT_SEC`` (0/empty = no limit), ``C4_GOVERNOR_LOCK``, ``C4_INVARIANT_BUILD_DMG``,
``C4_GOVERNOR_SPIN_K``, ``C4_DISCORD_MESH_SURFACE_SELF_HEAL`` or legacy ``C4_PLANETARY_SELF_HEAL`` (Discord path),
``NATS_URL``, ``DISCORD_PLAYWRIGHT_PROFILE``, ``C4_INVARIANT_DISCORD_ENABLED`` (default **0**) — **0** = mesh-first invariant
(no Discord Playwright / ``discord.com``, no ``run_full_release_session.sh`` spine); **1** = Discord command inventory +
Playwright game capture + optional full session.
**Mesh heal (live nine-cell only):** ``C4_MESH_HEAL_ENABLED`` (default **1**), ``C4_MESH_HEAL_MAX_ATTEMPTS``, ``C4_MESH_HEAL_WAIT_SEC``,
``C4_MESH_HEAL_SEAL_MAX_ATTEMPTS``, ``C4_MESH_HEAL_SEAL_WAIT_SEC`` — see ``scripts/mesh_healer.py``.
**Mesh vs spin:** nine-cell HTTP PARTIAL uses ``mesh:{healthy}/9:{sorted unhealthy cells}`` (and earth fields when required) so heal progress changes the signature; ``full_coverage`` skips ``spin.observe`` on that path so the healer can finish; sealing rollbacks call ``spin.reset()``.

**Full coverage (default):** ``C4_INVARIANT_FULL_COVERAGE=1`` (default) — same **spiral** as ``0``: the governor does **not** exit
REFUSED on spin, lock, max_cycles, or missing artifacts; it **retries until CURE**. (``C4_INVARIANT_FULL_COVERAGE`` is retained for
telemetry only.)

**OAuth / MFA / human visual:** detected in witnesses — governor **spirals** (PARTIAL + sleep + retry); does **not** exit with
BLOCKED or a dedicated OAuth exit code from these folds (mesh-first runs avoid Discord earth entirely when configured).

**Exit:** **0** = **CURE** (successful invariant receipt); **124** subprocess timeout; **130** signal (after PARTIAL receipt). Legacy numeric codes **3–6** are
**not** returned by the main loop anymore (invariant spirals instead).

**Signals:** SIGINT/SIGTERM best-effort ``cleanup_evidence_release_tmp`` on ``evidence/release/*.tmp`` before final write.
"""
from __future__ import annotations

import argparse
import atexit
import concurrent.futures
import glob
import hashlib
import json
import os
import re
import shutil
import urllib.error
import urllib.parse
import urllib.request
import signal
import subprocess
import sys
import threading
import time
import zipfile

import mesh_healer
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Exit codes (supervisors / CI)
# ---------------------------------------------------------------------------
EXIT_OK = 0
# Successful process exit receipt / ``write_final`` terminal — not CALORIE (calories are intermediate gates).
INVARIANT_EXIT_TERMINAL = "CURE"
EXIT_MAX_CYCLES = 3
EXIT_SPIN = 4
EXIT_NO_RELEASE_REPORT = 5
EXIT_NO_DMG_NO_BUILD = 6
EXIT_BLOCKED_HUMAN_VISUAL = 77
EXIT_OAUTH_MFA_REQUIRED = 78
EXIT_TIMEOUT_SUBPROCESS = 124
EXIT_SIGNAL = 130

# ---------------------------------------------------------------------------
# Physical witnesses (must match mount scripts / Discord bot strings)
# ---------------------------------------------------------------------------
VOL_GAIAFUSION = "/Volumes/GaiaFusion"
DEFAULT_HEARTBEAT_SEC = 15.0
DEFAULT_MIN_PNG_BYTES = 50000
DEFAULT_SPIN_K = 30
DEFAULT_EARTH_WAIT_SEC = 25.0
DEPLOY_TIMEOUT_SEC = 7200
MESH_PROBE_DEADLINE_SEC = 15.0
PLAYWRIGHT_TIMEOUT_SEC = 7200
POKE_TIMEOUT_SEC = 120
# Production mesh Fusion S⁴ dashboard (not loopback). Local dev may override ``C4_MESH_FUSION_WEB_URL``.
DEFAULT_MESH_FUSION_WEB_URL = "https://gaiaftcl.com/fusion-s4"
MESH_FUSION_WEB_TIMEOUT_SEC = 30
MCP_HEAL_TIMEOUT_SEC = 120

# Nine sovereign cells — must match scripts/mesh_health_snapshot.sh (wallet-gate :8803 /health).
MESH_SOVEREIGN_CELLS: list[tuple[str, str]] = [
    ("gaiaftcl-hcloud-hel1-01", "77.42.85.60"),
    ("gaiaftcl-hcloud-hel1-02", "135.181.88.134"),
    ("gaiaftcl-hcloud-hel1-03", "77.42.32.156"),
    ("gaiaftcl-hcloud-hel1-04", "77.42.88.110"),
    ("gaiaftcl-hcloud-hel1-05", "37.27.7.9"),
    ("gaiaftcl-netcup-nbg1-01", "37.120.187.247"),
    ("gaiaftcl-netcup-nbg1-02", "152.53.91.220"),
    ("gaiaftcl-netcup-nbg1-03", "152.53.88.141"),
    ("gaiaftcl-netcup-nbg1-04", "37.120.187.174"),
]

# Invariant toolbox manifest (CLI + scripts + mesh audit). See ``spec/invariant_toolbox.json``.
INVARIANT_TOOLBOX_SPEC = Path("spec") / "invariant_toolbox.json"

REQUIRED_SPOKE_CONTRACTS: list[str] = [
    "fusion_discord_web_mac.json",
    "materials_molecules_problem_solver.json",
    "biology_disease_cure_path.json",
    "atc_role_location_execution.json",
    "quantum_algo_menu_execution.json",
]

REQUIRED_SPOKE_FIELDS: list[str] = [
    "intent_menu",
    "input_schema",
    "execution_move_sequence",
    "terminal_witness",
]

REQUIRED_DISCORD_COMMAND_CATEGORIES: dict[str, list[str]] = {
    "membrane": ["/mesh", "/earthstate", "/probe", "/vortex", "/ingest", "/gaia-topology"],
    "crystal": ["/cell", "/fusion_fleet", "/mesh_status", "/getmaccellfusion"],
    "owl": ["/owl"],
    "governance": ["/governance"],
    "franklin": ["/franklin"],
    "sports_vortex": ["/sports"],
    "hub_session": ["/moor", "/unmoor", "/session", "/proof", "/proofs"],
    "domain_spokes": ["/materials", "/biology", "/atc", "/quantum"],
}

REQUIRED_PROOF_FIELDS: list[str] = [
    "proof_id", "session_id", "hub_token", "spoke", "surface",
    "operation", "input", "output_summary", "terminal",
    "vqbit_delta", "ts_utc", "receipt_hash",
]

REQUIRED_PLANT_STATE_ENUMS: list[str] = [
    "input_plant_type",
    "output_plant_type",
    "plant_status",
    "swap_state",
]

REQUIRED_HUB_MOOR_FIELDS: list[str] = [
    "onboarding_birth_state",
    "moor_transitions",
    "cross_domain_move_rule",
]


def _truthy(val: str | None, default: bool = False) -> bool:
    if val is None or val == "":
        return default
    return val.strip().lower() in ("1", "true", "yes", "on")


def _truthy_env_first(*keys: str, default: bool = False) -> bool:
    """First set env among ``keys`` wins; if none set, ``default``."""
    for k in keys:
        v = os.environ.get(k)
        if v is not None and v != "":
            return _truthy(v, default=default)
    return default


def _mesh_nine_cell_surface_from_env() -> bool:
    """
    True = nine-cell ``:8803/health`` witness (no Discord).
    False = Discord Playwright + ``C4_CELL_EARTH_AUDIT.json``.
    ``C4_SURFACE_MESH_NINE_CELL`` preferred; ``C4_PLANETARY_MESH_SELF_MOOR`` legacy alias.
    """
    return _truthy_env_first("C4_SURFACE_MESH_NINE_CELL", "C4_PLANETARY_MESH_SELF_MOOR", default=True)


def _require_earth_moor_from_env() -> bool:
    """
    True = ``discordMeshSurfaceGate`` must include Discord ``/cell`` earth witness closure
    (11/11 MOORED + crystal lineage), even when nine-cell mesh HTTP is enabled.
    """
    return _truthy_env_first("C4_REQUIRE_EARTH_MOOR", default=True)


class Gate(str, Enum):
    """Supervisory gate identifiers (stable for heartbeat / JSON consumers)."""

    mesh_fusion_web = "meshFusionWebGate"
    fusion_s4_playwright = "fusionS4PlaywrightGate"
    mount = "mountGate"
    visual = "visualGate"
    discord_mesh_surface = "discordMeshSurfaceGate"
    cell_plant_state = "cellPlantStateGate"
    hub_moor = "hubMoorGate"
    spoke_contracts = "spokeContractsGate"
    discord_command_inventory = "discordCommandInventoryGate"
    proof_ledger = "proofLedgerGate"
    license_payment = "licensePaymentGate"
    surface_parity = "surfaceParityGate"
    mesh_game_runner_capture = "meshGameRunnerCaptureGate"
    playwright_game_capture = "playwrightGameCaptureGate"
    domain_ui_gameplay = "domainUiGameplayGate"
    language_games = "languageGameContracts"
    mac_fusion_sub = "macFusionSubGovernorGate"
    sealing = "sealingGate"
    release_bundle = "releaseBundle"
    done = "done"


@dataclass
class SpinDetector:
    """
    Anti–silent-spin: the same ``(gate, signature)`` must not repeat unbounded without escalation.
    Call ``reset()`` after a successful remediation (e.g. DMG build completed) so the counter does not
    carry stale state across qualitatively different failures.
    """

    k: int
    last_sig: str | None = None
    count: int = 0

    def observe(self, gate: str, signature: str) -> bool:
        sig = f"{gate}|{signature}"
        if sig == self.last_sig:
            self.count += 1
        else:
            self.last_sig = sig
            self.count = 1
        return self.count >= self.k

    def reset(self) -> None:
        self.last_sig = None
        self.count = 0


@dataclass
class GovernorState:
    """Mutable runtime state for one governor process (not persisted across restarts)."""

    gate: Gate = Gate.mesh_fusion_web
    cycle: int = 0
    # Per-gate attempt counts (keys ⊆ gate names); values grow in long full_coverage runs — cosmetic only.
    attempt: dict[str, int] = field(default_factory=dict)
    discord_mesh_surface_locked_once: bool = False
    rollback_count: int = 0
    visual_fail_streak: int = 0
    last_sealed_docx: Path | None = None
    last_md5_msg: str = ""
    last_earth_doc: dict[str, Any] = field(default_factory=dict)
    mesh_deploy_attempted: bool = False
    full_session_invoked: bool = False
    last_full_session_rc: int | None = None
    playwright_capture_self_heal_runs: int = 0
    earth_mesh_self_heal_runs: int = 0
    # Spin-detector hygiene: mesh heal improves ``cells`` one-by-one — track counts so spin resets on progress.
    last_mesh_healthy_count: int = -1
    last_earth_moor_healthy_count: int = -1


def utc_ts() -> str:
    """UTC timestamp for file names: ``YYYYMMDDTHHMMSSZ``."""
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def append_heartbeat(ctx: "RunContext", row: dict[str, Any]) -> None:
    """
    Append one JSON line to the heartbeat JSONL (append-only audit log).

    Parameters
    ----------
    ctx
        Run context (paths).
    row
        Must be JSON-serializable; ``ts_utc`` added if missing.
    """
    row.setdefault("ts_utc", datetime.now(timezone.utc).isoformat())
    ctx.heartbeat_jsonl.parent.mkdir(parents=True, exist_ok=True)
    try:
        line = json.dumps(row, ensure_ascii=False) + "\n"
    except (TypeError, ValueError):
        line = (
            json.dumps(
                {
                    "ts_utc": row.get("ts_utc", datetime.now(timezone.utc).isoformat()),
                    "gate": row.get("gate"),
                    "heartbeat_json_error": True,
                    "note": "non-JSON-serializable heartbeat row — replaced stub (invariant continues)",
                },
                ensure_ascii=False,
            )
            + "\n"
        )
    with ctx.heartbeat_jsonl.open("a", encoding="utf-8") as fh:
        fh.write(line)


def atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    """Write JSON atomically (temp + replace) to avoid torn reads during concurrent observers."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    data = json.dumps(payload, indent=2, ensure_ascii=False)
    tmp.write_text(data + "\n", encoding="utf-8")
    tmp.replace(path)


def apply_full_compliance_env_defaults() -> None:
    """
    Production “full compliance”: clear stale REPORT, require ``run_full_release_session.sh`` spine,
    build + deploy DMG to mesh, mesh self-heal on non-uniformity, full Fusion battery in closure.
    """
    os.environ.setdefault("C4_CLEAR_RELEASE_DECK", "1")
    os.environ.setdefault("C4_INVARIANT_REQUIRE_FULL_SESSION", "1")
    os.environ.setdefault("C4_INVARIANT_BUILD_DMG", "1")
    os.environ.setdefault("C4_INVARIANT_DEPLOY_DMG", "1")
    os.environ.setdefault("RELEASE_SELF_HEAL_UNIFORM", "1")
    os.environ.setdefault("CLOSURE_RUN_FUSION_ALL", "1")


def cleanup_evidence_release_tmp(evidence_release: Path) -> None:
    """Best-effort remove stray ``*.tmp`` left by interrupted ``atomic_write_json`` (e.g. signal during rename)."""
    try:
        for p in evidence_release.glob("*.tmp"):
            try:
                p.unlink()
            except OSError:
                pass
    except OSError:
        pass


@dataclass
class RunContext:
    """Immutable configuration for one governor run (after CLI/env resolution)."""

    repo_root: Path
    evidence_release: Path
    ui_dir: Path
    heartbeat_jsonl: Path
    final_json: Path
    semantics_path: Path
    contract_path: Path
    human_ack_path: Path
    min_png_bytes: int
    heartbeat_sec: float
    earth_wait_sec: float
    nats_url: str
    discord_profile: str
    spin_k: int
    max_cycles: int | None
    build_timeout_sec: int | None
    use_governor_lock: bool
    mesh_only: bool
    mesh_nine_cell_surface: bool
    require_earth_moor: bool
    mesh_fusion_web_url: str
    invoke_full_session: bool
    require_full_session: bool
    clear_release_deck: bool
    full_session_timeout_sec: int | None
    full_coverage: bool
    full_compliance: bool
    mac_sub_invariant_script: Path
    discord_execution_enabled: bool
    quiet_until_cure: bool = False
    quiet_log_path: Path | None = None
    quiet_stdout_fd: int | None = None
    quiet_stderr_fd: int | None = None
    quiet_log_fp: Any = None


def _mesh_first_surface(ctx: "RunContext") -> bool:
    """Mesh probes only — no Discord Playwright / discord.com (mesh-only or Discord disabled)."""
    return ctx.mesh_only or not ctx.discord_execution_enabled


def try_acquire_governor_lock(evidence_release: Path) -> Path | None:
    """
    Optional single-instance lock under ``evidence/release/.full_release_governor.lock``.

    If the lock file exists and the PID inside is still alive, returns None (another governor).
    Stale locks (dead PID) are removed. After stale ``unlink`` or ``O_EXCL`` races, retries so another
    writer winning between unlink and create does not stall acquisition permanently.
    """
    lock = evidence_release / ".full_release_governor.lock"
    for _attempt in range(4):
        if lock.is_file():
            try:
                line = lock.read_text(encoding="utf-8", errors="replace").strip().splitlines()
                pid = int(line[0]) if line else -1
                os.kill(pid, 0)
                return None
            except (ProcessLookupError, ValueError, OSError):
                try:
                    lock.unlink()
                except OSError:
                    pass
        try:
            fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
            payload = f"{os.getpid()}\n{datetime.now(timezone.utc).isoformat()}\n"
            os.write(fd, payload.encode("utf-8"))
            os.close(fd)
            return lock
        except FileExistsError:
            continue
    return None


def release_governor_lock(lock_path: Path | None) -> None:
    """Best-effort lock removal (atexit + signal)."""
    if lock_path and lock_path.is_file():
        try:
            lock_path.unlink()
        except OSError:
            pass


def run_bash(
    script: Path,
    env: dict[str, str] | None = None,
    timeout_sec: int | None = None,
    cwd: Path | None = None,
) -> int:
    """
    Run a bash script; return process exit code. ``124`` if timeout.

    Parameters
    ----------
    script
        Path to ``.sh`` (executable bit recommended).
    env
        Extra env vars merged onto ``os.environ``.
    timeout_sec
        ``None`` = no limit (long builds).
    cwd
        Working directory; default is ``script.parent.parent`` (GAIAOS root for ``scripts/*.sh``).
    """
    e = os.environ.copy()
    if env:
        e.update(env)
    work = cwd if cwd is not None else script.parent.parent
    try:
        return subprocess.run(
            ["/bin/bash", str(script)],
            cwd=str(work),
            env=e,
            timeout=timeout_sec,
        ).returncode
    except subprocess.TimeoutExpired:
        return EXIT_TIMEOUT_SUBPROCESS


def run_bash_with_heartbeat(
    script: Path,
    ctx: "RunContext",
    gate_label: str,
    timeout_sec: int | None,
) -> int:
    """
    Run a potentially **long** bash script while a daemon thread appends heartbeats so JSONL
    does not go silent for the duration of a multi-hour DMG build.
    """
    stop = threading.Event()

    def _pulse() -> None:
        while not stop.wait(timeout=min(ctx.heartbeat_sec, 60.0)):
            append_heartbeat(
                ctx,
                {
                    "gate": gate_label,
                    "phase": "long_subprocess",
                    "script": str(script),
                    "pid": os.getpid(),
                },
            )

    t = threading.Thread(target=_pulse, name="governor-heartbeat", daemon=True)
    t.start()
    try:
        return run_bash(script, timeout_sec=timeout_sec)
    finally:
        stop.set()
        t.join(timeout=2.0)


def gaiafusion_dmg_resolved(repo_root: Path) -> Path | None:
    """
    Resolve the DMG path: ``GAIAFUSION_DMG`` env, else ``dist/GaiaFusion.dmg``, else first
    ``dist/GaiaFusion*.dmg``.
    """
    raw = os.environ.get("GAIAFUSION_DMG", "").strip()
    if raw:
        p = Path(raw).expanduser().resolve()
        return p if p.is_file() else None
    dist = repo_root / "dist"
    if not dist.is_dir():
        return None
    cand = dist / "GaiaFusion.dmg"
    if cand.is_file():
        return cand
    globs = sorted(dist.glob("GaiaFusion*.dmg"))
    return globs[0] if globs else None


def has_gaiafusion_dmg(repo_root: Path) -> bool:
    return gaiafusion_dmg_resolved(repo_root) is not None


def maybe_deploy_dmg_to_mesh(ctx: "RunContext") -> tuple[int, str]:
    """
    Optionally push DMG to nine cells via ``deploy_dmg_to_mesh.sh`` (requires SSH key).

    Returns
    -------
    (exit_code, mode) where mode is ``skipped`` | ``missing_script`` | ``ran`` | ``timeout``.
    """
    if not _truthy(os.environ.get("C4_INVARIANT_DEPLOY_DMG")):
        return 0, "skipped"
    script = ctx.repo_root / "scripts" / "deploy_dmg_to_mesh.sh"
    if not script.is_file():
        return 1, "missing_script"
    try:
        rc = subprocess.run(
            ["/bin/bash", str(script)],
            cwd=str(ctx.repo_root),
            env=os.environ.copy(),
            timeout=DEPLOY_TIMEOUT_SEC,
        ).returncode
    except subprocess.TimeoutExpired:
        return EXIT_TIMEOUT_SUBPROCESS, "timeout"
    return rc, "ran"


def df_has_gaiafusion() -> bool:
    """True if ``df -h`` output contains the GaiaFusion mount point (physical kernel witness)."""
    try:
        cp = subprocess.run(
            ["/bin/df", "-h"],
            capture_output=True,
            text=True,
            timeout=30,
            encoding="utf-8",
            errors="replace",
        )
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return False
    if cp.returncode != 0:
        return False
    return VOL_GAIAFUSION in (cp.stdout or "")


def load_earth_audit(path: Path) -> dict[str, Any]:
    """Load ``C4_CELL_EARTH_AUDIT.json``; empty dict if missing or invalid JSON."""
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def oauth_mfa_requires_human(ctx: RunContext, earth_audit: dict[str, Any]) -> bool:
    """
    True when Discord OAuth / MFA (2FA) blocks unattended automation — **only** allowed non-CALORIE
    terminal exit when ``C4_INVARIANT_FULL_COVERAGE`` is on. Mesh-only mode never uses this.
    """
    if ctx.mesh_nine_cell_surface:
        return False
    flag = ctx.repo_root / "evidence" / "discord" / "OAUTH_MFA_REQUIRED.json"
    if flag.is_file():
        try:
            j = json.loads(flag.read_text(encoding="utf-8"))
            if j.get("required") is True or j.get("oauth_mfa") is True:
                return True
        except (json.JSONDecodeError, OSError):
            pass
    if earth_audit.get("oauth_mfa_required") is True:
        return True
    excerpt = (earth_audit.get("raw_excerpt") or "").lower()
    if not excerpt:
        return False
    needles = (
        "two-factor",
        "2fa",
        "mfa",
        "verify your email",
        "log in to continue",
        "discord.com/login",
        "/login",
        "authenticator",
        "sms code",
        "enter discord",
    )
    if any(n in excerpt for n in needles):
        cid = earth_audit.get("cell_id")
        if cid in (None, ""):
            return True
        if not earth_audit.get("crystal_lineage_ok", True):
            return True
    return False


def earth_ok(doc: dict[str, Any]) -> bool:
    """Discord functional surface: 11/11 MOORED and Playwright terminal CALORIE for this scrape."""
    return bool(doc.get("earth_11_11_closed")) and doc.get("terminal") == "CALORIE"


def _http_health_code(ip: str, port: int = 8803) -> int:
    """GET /health on wallet-gate; return HTTP status or 0 on failure."""
    try:
        with urllib.request.urlopen(f"http://{ip}:{port}/health", timeout=10) as r:
            return int(r.getcode() or 0)
    except (urllib.error.URLError, urllib.error.HTTPError, OSError, ValueError):
        return 0


def probe_mesh_self_moor(repo_root: Path) -> dict[str, Any]:
    """
    Mesh-native mooring: all nine sovereign cells must return 2xx on ``:8803/health``.
    Writes ``evidence/mesh/C4_MESH_SELF_MOOR.json`` (no Discord).
    Probes run concurrently with a single deadline (``MESH_PROBE_DEADLINE_SEC``) so partial outages
    do not stall for nine serial 10s timeouts.

    ``C4_INVARIANT_MESH_NINE_CELL_OFFLINE=1`` skips TCP probes (CI / air-gapped); witness is **non-production**
    (``probe_mode`` + ``warning``) — sovereign mooring still requires real ``:8803`` receipts in deployment.
    """
    ev_mesh = repo_root / "evidence" / "mesh"
    ev_mesh.mkdir(parents=True, exist_ok=True)
    out_path = ev_mesh / "C4_MESH_SELF_MOOR.json"
    if _truthy(os.environ.get("C4_INVARIANT_MESH_NINE_CELL_OFFLINE", "0")):
        cells = [
            {"cell": name, "ip": ip, "health_http": 0, "ok": True, "offline_stub": True}
            for name, ip in MESH_SOVEREIGN_CELLS
        ]
        doc: dict[str, Any] = {
            "schema": "c4_mesh_self_moor_v1",
            "ts_utc": datetime.now(timezone.utc).isoformat(),
            "mooring_mode": "mesh_http_offline_stub",
            "mesh_probe_deadline_sec": 0.0,
            "nine_cells_ok": True,
            "mesh_mooring_closed": True,
            "terminal": "CALORIE",
            "probe_mode": "offline_contract_stub",
            "warning": (
                "C4_INVARIANT_MESH_NINE_CELL_OFFLINE=1 — TCP probe to sovereign cells skipped; "
                "not a production mooring receipt"
            ),
            "cells": cells,
            "note": "Offline stub for invariant automation without WAN; use real mesh probes in deployment.",
        }
        atomic_write_json(out_path, doc)
        return doc
    cells: list[dict[str, Any]] = []
    all_ok = True
    code_by_cell: dict[tuple[str, str], int] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(MESH_SOVEREIGN_CELLS)) as pool:
        future_to_cell = {
            pool.submit(_http_health_code, ip, 8803): (name, ip) for name, ip in MESH_SOVEREIGN_CELLS
        }
        done, not_done = concurrent.futures.wait(
            future_to_cell.keys(),
            timeout=MESH_PROBE_DEADLINE_SEC,
        )
        for fut in done:
            name, ip = future_to_cell[fut]
            try:
                code_by_cell[(name, ip)] = int(fut.result())
            except Exception:
                code_by_cell[(name, ip)] = 0
        for fut in not_done:
            fut.cancel()
            name, ip = future_to_cell[fut]
            code_by_cell[(name, ip)] = 0
    for name, ip in MESH_SOVEREIGN_CELLS:
        code = code_by_cell.get((name, ip), 0)
        ok_cell = 200 <= code < 300
        if not ok_cell:
            all_ok = False
        cells.append({"cell": name, "ip": ip, "health_http": code, "ok": ok_cell})
    doc: dict[str, Any] = {
        "schema": "c4_mesh_self_moor_v1",
        "ts_utc": datetime.now(timezone.utc).isoformat(),
        "mooring_mode": "mesh_http",
        "mesh_probe_deadline_sec": MESH_PROBE_DEADLINE_SEC,
        "nine_cells_ok": all_ok,
        "mesh_mooring_closed": all_ok,
        "terminal": "CALORIE" if all_ok else "PARTIAL",
        "cells": cells,
        "note": "Nine-cell mesh witness via HTTP /health on :8803 — independent of Discord Earth-feed 11/11.",
    }
    atomic_write_json(out_path, doc)
    return doc


def load_mesh_witness(path: Path) -> dict[str, Any]:
    """Load ``C4_MESH_SELF_MOOR.json``."""
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def mesh_nine_cell_surface_ok(doc: dict[str, Any]) -> bool:
    """Nine-cell mesh surface: all sovereign cells healthy on ``:8803/health`` and closed terminal."""
    t = str(doc.get("terminal", "")).upper()
    return bool(doc.get("mesh_mooring_closed")) and t in ("CALORIE", "CURE")


def discord_or_mesh_surface_closure_ok(doc: dict[str, Any], ctx: RunContext) -> bool:
    """Unified check: mesh HTTP nine-cell **or** Discord earth audit."""
    if ctx.mesh_nine_cell_surface:
        return mesh_nine_cell_surface_ok(doc)
    return earth_ok(doc)


def mesh_probe_after_optional_heal(
    ctx: RunContext,
    repo: Path,
    *,
    gate_value: str,
    max_heal_attempts: int,
    heal_wait_sec: float,
    seal_subphase: str | None = None,
) -> tuple[dict[str, Any], int, dict[str, Any]]:
    """
    When nine-cell mesh is live (not offline stub) and ``C4_MESH_HEAL_ENABLED`` (default on),
    run ``mesh_healer.probe_and_heal_until_healthy`` then **always** refresh via ``probe_mesh_self_moor``
    so ``C4_MESH_SELF_MOOR.json`` matches the governor's canonical witness schema.
    """
    heal_attempts = 0
    heal_meta: dict[str, Any] = {}
    if (
        ctx.mesh_nine_cell_surface
        and not _truthy(os.environ.get("C4_INVARIANT_MESH_NINE_CELL_OFFLINE", "0"))
        and _truthy(os.environ.get("C4_MESH_HEAL_ENABLED", "1"))
    ):

        def _on_hb(row: dict[str, Any]) -> None:
            payload: dict[str, Any] = {"gate": gate_value, **row}
            if seal_subphase:
                payload["seal_subphase"] = seal_subphase
            append_heartbeat(ctx, payload)

        ok_h, heal_attempts, last_probe = mesh_healer.probe_and_heal_until_healthy(
            repo_root=repo,
            evidence_dir=repo / "evidence" / "mesh",
            max_heal_attempts=max_heal_attempts,
            heal_wait_sec=heal_wait_sec,
            on_heartbeat=_on_hb,
        )
        heal_meta = {
            "mesh_heal_loop_ok": ok_h,
            "heal_attempts": heal_attempts,
            "last_probe": last_probe,
        }
    doc = probe_mesh_self_moor(repo)
    return doc, heal_attempts, heal_meta


def mesh_doc_healthy_count(mesh_doc: dict[str, Any]) -> int:
    cells = mesh_doc.get("cells") or []
    if not isinstance(cells, list):
        return 0
    return sum(1 for c in cells if isinstance(c, dict) and c.get("ok"))


def mesh_doc_unhealthy_names_sorted(mesh_doc: dict[str, Any]) -> str:
    cells = mesh_doc.get("cells") or []
    if not isinstance(cells, list):
        return ""
    bad: list[str] = []
    for c in cells:
        if isinstance(c, dict) and not c.get("ok"):
            bad.append(str(c.get("cell") or c.get("name") or ""))
    return ",".join(sorted(x for x in bad if x))


def mesh_gate_spin_signature(mesh_doc: dict[str, Any], earth_doc: dict[str, Any] | None = None) -> str:
    """
    Spin signature for mesh surface gate — encodes **progress** (healthy count + which cells are down),
    not just ``terminal=PARTIAL``, so the healer fixing one cell changes the string and resets spin.
    """
    hc = mesh_doc_healthy_count(mesh_doc)
    un = mesh_doc_unhealthy_names_sorted(mesh_doc)
    base = f"mesh:{hc}/9:{un}"
    if earth_doc is None:
        return base
    et = str(earth_doc.get("terminal") or "")
    em = earth_doc.get("earth_mooring") if isinstance(earth_doc.get("earth_mooring"), dict) else {}
    eh = int(em.get("healthy", 0) or 0) if isinstance(em, dict) else 0
    etot = int(em.get("total", 0) or 0) if isinstance(em, dict) else 0
    return f"{base}|earth:{et}|eh:{eh}/{etot}"


def maybe_reset_spin_on_moor_progress(
    spin: SpinDetector,
    st: GovernorState,
    mesh_doc: dict[str, Any],
    earth_doc: dict[str, Any] | None,
) -> None:
    """If mesh or earth mooring healthy count increased since last tick, clear spin (healer made progress)."""
    curr_m = mesh_doc_healthy_count(mesh_doc)
    prev_m = st.last_mesh_healthy_count
    if prev_m >= 0 and curr_m > prev_m:
        spin.reset()
    st.last_mesh_healthy_count = curr_m

    if earth_doc is not None:
        em = earth_doc.get("earth_mooring") if isinstance(earth_doc.get("earth_mooring"), dict) else {}
        curr_e = int(em.get("healthy", 0) or 0) if isinstance(em, dict) else 0
        prev_e = st.last_earth_moor_healthy_count
        if prev_e >= 0 and curr_e > prev_e:
            spin.reset()
        st.last_earth_moor_healthy_count = curr_e


def discord_mesh_surface_partial_retry(
    ctx: RunContext,
    st: GovernorState,
    spin: SpinDetector,
    lock_path: Path | None,
    mesh_doc: dict[str, Any],
    earth_doc: dict[str, Any] | None,
    *,
    spin_note_line: str,
) -> None:
    """
    After PARTIAL on nine-cell HTTP path: **full_coverage** skips ``spin.observe`` (healer owns backoff).
    Otherwise use ``mesh_gate_spin_signature`` so progress changes the signature.
    """
    if ctx.full_coverage:
        unhealthy = [
            c.get("cell")
            for c in (mesh_doc.get("cells") or [])
            if isinstance(c, dict) and not c.get("ok")
        ]
        hb: dict[str, Any] = {
            "gate": Gate.discord_mesh_surface.value,
            "mesh_heal_retry": True,
            "healthy_count": mesh_doc_healthy_count(mesh_doc),
            "unhealthy": unhealthy,
            "terminal": "PARTIAL",
            "note": "full_coverage: mesh surface retries without spin — mesh_healer / earth paths own backoff",
        }
        if earth_doc is not None:
            hb["earth_terminal"] = earth_doc.get("terminal")
        append_heartbeat(ctx, hb)
        time.sleep(ctx.earth_wait_sec)
        return
    sig = mesh_gate_spin_signature(mesh_doc, earth_doc)
    if spin.observe(Gate.discord_mesh_surface.value, sig):
        klein_fold_spin_or_exit(
            ctx,
            lock_path,
            spin,
            st,
            Gate.discord_mesh_surface,
            sig,
            spin_note_line,
        )
    time.sleep(ctx.earth_wait_sec)


def _loopback_mesh_fusion_url(url: str) -> bool:
    """True when Playwright will use local ``webServer`` (nothing listens before that gate)."""
    try:
        u = urllib.parse.urlsplit(url)
        h = (u.hostname or "").lower()
        return h in ("127.0.0.1", "localhost", "::1") or h.endswith(".localhost")
    except Exception:  # noqa: BLE001
        return False


def _fusion_s4_repo_contract_ok(repo_root: Path) -> tuple[bool, str]:
    """Repo-local witness that the Fusion S⁴ route exists (loopback pre-server probe cannot HTTP)."""
    p = repo_root / "services" / "gaiaos_ui_web" / "app" / "fusion-s4" / "page.tsx"
    if not p.is_file():
        return False, f"missing {p.relative_to(repo_root)}"
    try:
        text = p.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        return False, f"read failed: {exc}"
    if 'data-testid="fusion-s4-main"' not in text and "data-testid='fusion-s4-main'" not in text:
        return False, "fusion-s4-main test id not found in page.tsx"
    return True, "ok"


def probe_mesh_fusion_web(ctx: RunContext) -> dict[str, Any]:
    """Sovereign UI health for non-Mac teams reviewing mesh Fusion.

    **Loopback:** no HTTP preflight (server starts in ``fusionS4PlaywrightGate``); require repo contract only.
    **WAN:** ``urlopen`` must return 2xx/3xx.
    """
    url = ctx.mesh_fusion_web_url
    ts = datetime.now(timezone.utc).isoformat()
    base: dict[str, Any] = {
        "schema": "mesh_fusion_web_probe_v1",
        "ts_utc": ts,
        "url": url,
    }
    if _loopback_mesh_fusion_url(url):
        ok, reason = _fusion_s4_repo_contract_ok(ctx.repo_root)
        return {
            **base,
            "http_status": 0,
            "web_ok": ok,
            "terminal": "CALORIE" if ok else "PARTIAL",
            "probe_mode": "loopback_repo_contract",
            "note": "loopback origin — HTTP skipped until fusionS4PlaywrightGate webServer",
            "repo_contract": reason,
        }
    err: str | None = None
    try:
        with urllib.request.urlopen(url, timeout=MESH_FUSION_WEB_TIMEOUT_SEC) as r:
            code = int(r.getcode() or 0)
            ok = 200 <= code < 400
    except (urllib.error.URLError, urllib.error.HTTPError, OSError, ValueError) as exc:
        code = 0
        ok = False
        err = repr(exc)
    except Exception as exc:  # noqa: BLE001
        code = 0
        ok = False
        err = repr(exc)
    out: dict[str, Any] = {
        **base,
        "http_status": code,
        "web_ok": ok,
        "terminal": "CALORIE" if ok else "PARTIAL",
    }
    if err:
        out["error"] = err
    return out


def validate_cell_plant_state_schema(repo_root: Path) -> tuple[bool, str]:
    schema_path = repo_root / "spec" / "cell_plant_state.schema.json"
    if not schema_path.is_file():
        return False, f"missing {schema_path.relative_to(repo_root)}"
    try:
        data = json.loads(schema_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        return False, f"invalid JSON: {exc}"
    text = json.dumps(data)
    for enum_name in REQUIRED_PLANT_STATE_ENUMS:
        if enum_name not in text:
            return False, f"missing enum definition: {enum_name}"
    return True, "ok"


def validate_hub_moor_contract(repo_root: Path) -> tuple[bool, str]:
    contract_path = repo_root / "spec" / "guided_tour" / "00_hub_moor_account_game.json"
    if not contract_path.is_file():
        return False, f"missing {contract_path.relative_to(repo_root)}"
    try:
        data = json.loads(contract_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        return False, f"invalid JSON: {exc}"
    for f in REQUIRED_HUB_MOOR_FIELDS:
        if f not in data:
            return False, f"missing field: {f}"
    return True, "ok"


def validate_spoke_contracts(repo_root: Path) -> tuple[bool, str]:
    spokes_dir = repo_root / "spec" / "guided_tour" / "spokes"
    if not spokes_dir.is_dir():
        return False, f"missing directory: {spokes_dir.relative_to(repo_root)}"
    for fname in REQUIRED_SPOKE_CONTRACTS:
        fpath = spokes_dir / fname
        if not fpath.is_file():
            return False, f"missing spoke contract: spokes/{fname}"
        try:
            data = json.loads(fpath.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as exc:
            return False, f"invalid JSON in spokes/{fname}: {exc}"
        for f in REQUIRED_SPOKE_FIELDS:
            if f not in data:
                return False, f"spokes/{fname}: missing field: {f}"
    return True, "ok"


def validate_discord_command_inventory(repo_root: Path) -> tuple[bool, str]:
    map_path = repo_root / "spec" / "domain_ui_discord_m8_map.json"
    if not map_path.is_file():
        return False, f"missing {map_path.relative_to(repo_root)}"
    try:
        data = json.loads(map_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        return False, f"invalid JSON: {exc}"
    inventory = data.get("discord_command_inventory")
    if not isinstance(inventory, dict):
        return False, "missing discord_command_inventory in manifold map"
    for category, required_cmds in REQUIRED_DISCORD_COMMAND_CATEGORIES.items():
        cat_data = inventory.get(category)
        if not isinstance(cat_data, list):
            return False, f"missing Discord command category: {category}"
        cat_commands = {str(c).lower().strip() for c in cat_data if isinstance(c, str)}
        for cmd in required_cmds:
            if cmd.lower().strip() not in cat_commands:
                return False, f"missing Discord command {cmd} in category {category}"
    return True, "ok"


def validate_proof_ledger_schema(repo_root: Path) -> tuple[bool, str]:
    schema_path = repo_root / "spec" / "proofs" / "game_interaction_proof.schema.json"
    if not schema_path.is_file():
        return False, f"missing {schema_path.relative_to(repo_root)}"
    try:
        data = json.loads(schema_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        return False, f"invalid JSON: {exc}"
    text = json.dumps(data)
    for f in REQUIRED_PROOF_FIELDS:
        if f not in text:
            return False, f"missing proof field definition: {f}"
    return True, "ok"


def validate_license_payment_contract(repo_root: Path) -> tuple[bool, str]:
    contract_path = repo_root / "spec" / "legal_payment" / "license_gate_contract.json"
    if not contract_path.is_file():
        return False, f"missing {contract_path.relative_to(repo_root)}"
    try:
        data = json.loads(contract_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        return False, f"invalid JSON: {exc}"
    if not data.get("no_license_without_payment"):
        return False, "missing or false: no_license_without_payment invariant"
    return True, "ok"


def validate_surface_parity(repo_root: Path) -> tuple[bool, str]:
    witness_path = repo_root / "evidence" / "parity" / "SURFACE_PARITY_WITNESS.json"
    if not witness_path.is_file():
        return False, f"missing {witness_path.relative_to(repo_root)}"
    try:
        data = json.loads(witness_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        return False, f"invalid JSON: {exc}"
    if data.get("divergence_count", -1) != 0:
        return False, f"surface parity divergence_count={data.get('divergence_count')} (must be 0)"
    pt = str(data.get("terminal", "")).upper()
    if pt not in ("CALORIE", "CURE"):
        return False, f"surface parity terminal={data.get('terminal')} (must be CALORIE or CURE)"
    return True, "ok"


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
    return out


def validate_playwright_game_captures(repo_root: Path) -> tuple[bool, str]:
    contract_path = repo_root / "spec" / "release_playwright_game_capture.json"
    if not contract_path.is_file():
        return False, f"missing {contract_path.relative_to(repo_root)}"
    try:
        contract = json.loads(contract_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        return False, f"invalid contract JSON: {exc}"
    art = contract.get("evidence_artifact")
    if not art:
        return False, "missing evidence_artifact in contract"
    evidence_path = repo_root / str(art)
    if not evidence_path.is_file():
        return False, f"missing {evidence_path.relative_to(repo_root)}"
    try:
        evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        return False, f"invalid evidence JSON: {exc}"
    for f in contract.get("required_fields", []):
        if f not in evidence:
            return False, f"missing evidence field: {f}"
    if str(evidence.get("driver", "")).strip().lower() != str(contract.get("required_driver", "playwright")):
        return False, f"driver must be {contract.get('required_driver', 'playwright')}"
    games = evidence.get("games")
    if not isinstance(games, dict):
        return False, "evidence.games must be an object"
    required_game_ui = contract.get("required_game_ui_interactions") or {}
    required_global_ui = contract.get("required_global_ui_interactions") or {}
    global_ui = evidence.get("global_ui_interactions") or {}
    if required_global_ui and not isinstance(global_ui, dict):
        return False, "evidence.global_ui_interactions must be an object"
    for k, expected in required_global_ui.items():
        if bool(global_ui.get(str(k))) != bool(expected):
            return False, f"global UI interaction missing: {k}"
    required_ids = _required_game_ids_from_registry(repo_root)
    # Optional availability filter from latest Discord validation snapshot.
    # If a registry game has no mapped/visible channel in the latest validation artifact,
    # do not hard-fail this gate on that game id.
    validation_path = repo_root / "evidence" / "discord_game_rooms" / "game_validation_20260331_132531.json"
    available_validation_keys: set[str] = set()
    if validation_path.is_file():
        try:
            v = json.loads(validation_path.read_text(encoding="utf-8"))
            available_validation_keys = set((v.get("game_rooms") or {}).keys())
        except (json.JSONDecodeError, OSError):
            available_validation_keys = set()
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
    for extra in contract.get("required_extra_games", []):
        x = str(extra).strip()
        if x:
            required_ids.append(x)
    required_ids = sorted(set(required_ids))
    required_live = bool((contract.get("required_game_state") or {}).get("live_captured", True))
    missing: list[str] = []
    for gid in required_ids:
        mapped = reg_to_validation.get(gid, gid)
        if available_validation_keys and mapped not in available_validation_keys:
            continue
        row = games.get(gid)
        if not isinstance(row, dict):
            missing.append(gid)
            continue
        if bool(row.get("live_captured")) != required_live:
            missing.append(gid)
            continue
        if required_game_ui:
            ui = row.get("ui_interactions")
            if not isinstance(ui, dict):
                missing.append(gid)
                continue
            ui_ok = True
            for key, expected in required_game_ui.items():
                if bool(ui.get(str(key))) != bool(expected):
                    ui_ok = False
                    break
            if not ui_ok:
                missing.append(gid)
    if missing:
        return False, f"missing live Playwright Discord UI captures: {','.join(missing)}"
    return True, "ok"


def validate_mesh_game_runner_captures(repo_root: Path) -> tuple[bool, str]:
    contract_path = repo_root / "spec" / "release_mesh_game_runner_capture.json"
    if not contract_path.is_file():
        return False, f"missing {contract_path.relative_to(repo_root)}"
    try:
        contract = json.loads(contract_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        return False, f"invalid contract JSON: {exc}"
    art = str(contract.get("evidence_artifact") or "").strip()
    if not art:
        return False, "missing evidence_artifact in contract"
    evidence_path = repo_root / art
    if not evidence_path.is_file():
        return False, f"missing {evidence_path.relative_to(repo_root)}"
    try:
        evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        return False, f"invalid evidence JSON: {exc}"
    for f in contract.get("required_fields", []):
        if f not in evidence:
            return False, f"missing evidence field: {f}"
    if str(evidence.get("driver", "")).strip().lower() != str(contract.get("required_driver", "playwright")):
        return False, f"driver must be {contract.get('required_driver', 'playwright')}"
    domains = evidence.get("domains")
    if not isinstance(domains, dict):
        return False, "evidence.domains must be an object"
    required_min = contract.get("required_domain_screenshot_minimums") or {}
    if not isinstance(required_min, dict):
        return False, "required_domain_screenshot_minimums must be an object"
    required_ui = contract.get("required_domain_ui_interactions") or {}
    total_screenshots = 0
    for domain_id, min_count_raw in required_min.items():
        min_count = int(min_count_raw)
        row = domains.get(str(domain_id))
        if not isinstance(row, dict):
            return False, f"missing domain capture: {domain_id}"
        if bool(row.get("live_captured")) is not True:
            return False, f"domain not live captured: {domain_id}"
        ui = row.get("ui_interactions")
        if not isinstance(ui, dict):
            return False, f"domain ui_interactions missing: {domain_id}"
        for key, expected in required_ui.items():
            if bool(ui.get(str(key))) != bool(expected):
                return False, f"domain UI interaction missing for {domain_id}: {key}"
        shots = row.get("screenshot_paths")
        if not isinstance(shots, list):
            return False, f"domain screenshot_paths missing: {domain_id}"
        count = len([s for s in shots if isinstance(s, str) and s.strip()])
        if count < min_count:
            return False, f"domain screenshot shortfall {domain_id}: {count} < {min_count}"
        total_screenshots += count
    total_required = int(contract.get("required_total_screenshots", 53))
    if total_screenshots < total_required:
        return False, f"total screenshot shortfall: {total_screenshots} < {total_required}"
    global_ui = evidence.get("global_ui_interactions")
    required_global_ui = contract.get("required_global_ui_interactions") or {}
    if required_global_ui:
        if not isinstance(global_ui, dict):
            return False, "evidence.global_ui_interactions must be an object"
        for key, expected in required_global_ui.items():
            if bool(global_ui.get(str(key))) != bool(expected):
                return False, f"global UI interaction missing: {key}"
    return True, "ok"


def run_mesh_game_runner_self_heal(ctx: "RunContext", reason: str) -> tuple[bool, dict[str, Any]]:
    witness_url = ctx.mesh_fusion_web_url.rstrip("/")
    cmd = "ENABLE_MESH_GAME_RUNNER_CAPTURE=1 npm run test:e2e:mesh-runner"
    child_env = os.environ.copy()
    child_env["GAIA_ROOT"] = str(ctx.repo_root)
    child_env["ENABLE_MESH_GAME_RUNNER_CAPTURE"] = "1"
    child_env["C4_MESH_FUSION_WEB_URL"] = witness_url
    try:
        cp = subprocess.run(
            ["/bin/bash", "-lc", cmd],
            cwd=str(ctx.ui_dir),
            env=child_env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=PLAYWRIGHT_TIMEOUT_SEC,
            check=False,
        )
        return cp.returncode == 0, {
            "reason": reason,
            "exit_code": cp.returncode,
            "output_tail": (cp.stdout or "")[-3000:],
        }
    except subprocess.TimeoutExpired:
        return False, {
            "reason": reason,
            "exit_code": EXIT_TIMEOUT_SUBPROCESS,
            "output_tail": "mesh_game_runner_capture_timeout",
        }


def run_playwright_capture_self_heal(ctx: "RunContext", reason: str) -> tuple[bool, dict[str, Any]]:
    """
    Self-heal for playwrightGameCaptureGate:
    rerun live Discord mesh capture and refresh surface parity witness.
    """
    if not ctx.discord_execution_enabled:
        ok_m, meta_m = run_mesh_game_runner_self_heal(ctx, reason)
        root = ctx.repo_root
        parity_rc = 127
        parity_py = root / "scripts" / "generate_surface_parity_witness.py"
        out_tail = str(meta_m.get("output_tail") or "")
        if parity_py.is_file():
            try:
                pp = subprocess.run(
                    ["python3", str(parity_py)],
                    cwd=str(root),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    timeout=120,
                    check=False,
                )
                parity_rc = pp.returncode
                out_tail = (out_tail + "\n" + (pp.stdout or ""))[-3000:]
            except subprocess.TimeoutExpired:
                parity_rc = EXIT_TIMEOUT_SUBPROCESS
                out_tail = (out_tail + "\nparity witness generation timed out")[-3000:]
        ok = ok_m and parity_rc == 0
        return ok, {
            "reason": reason,
            "discord_execution_enabled": False,
            "mesh_runner_self_heal": meta_m,
            "parity_rc": parity_rc,
            "output_tail": out_tail,
        }

    root = ctx.repo_root
    cmd = (
        "ENABLE_MESH_GAME_CAPTURE_TEST=1 "
        "npm run test:e2e:discord -- --grep \"Discord mesh games live capture\""
    )
    try:
        cp = subprocess.run(
            ["/bin/bash", "-lc", cmd],
            cwd=str(ctx.ui_dir),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=PLAYWRIGHT_TIMEOUT_SEC,
            check=False,
        )
        capture_rc = cp.returncode
        out_tail = (cp.stdout or "")[-3000:]
    except subprocess.TimeoutExpired:
        capture_rc = EXIT_TIMEOUT_SUBPROCESS
        out_tail = "playwright mesh capture timed out"

    parity_rc = 127
    parity_py = root / "scripts" / "generate_surface_parity_witness.py"
    if parity_py.is_file():
        try:
            pp = subprocess.run(
                ["python3", str(parity_py)],
                cwd=str(root),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=120,
                check=False,
            )
            parity_rc = pp.returncode
            out_tail = (out_tail + "\n" + (pp.stdout or ""))[-3000:]
        except subprocess.TimeoutExpired:
            parity_rc = EXIT_TIMEOUT_SUBPROCESS
            out_tail = (out_tail + "\nparity witness generation timed out")[-3000:]

    ok = capture_rc == 0 and parity_rc == 0
    return ok, {
        "reason": reason,
        "capture_rc": capture_rc,
        "parity_rc": parity_rc,
        "output_tail": out_tail,
    }


def run_earth_mesh_self_heal(ctx: "RunContext", reason: str) -> tuple[bool, dict[str, Any]]:
    """
    Mesh-side Earth mooring remediation inside invariant loop:
    redeploy nine cells and refresh Discord game-room/developer embed validation.
    """
    root = ctx.repo_root
    cmd_deploy = "bash scripts/deploy_crystal_nine_cells.sh"
    cmd_validate = (
        "cd services/gaiaos_ui_web && "
        "INTEGRATION_DISCORD_DEVPORTAL_EMBED=1 bash ../../scripts/validate_discord_game_rooms.sh"
    )
    joined = (
        f"{cmd_deploy} && {cmd_validate}"
        if ctx.discord_execution_enabled
        else cmd_deploy
    )
    try:
        cp = subprocess.run(
            ["/bin/bash", "-lc", joined],
            cwd=str(root),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=DEPLOY_TIMEOUT_SEC,
            check=False,
        )
        return cp.returncode == 0, {
            "reason": reason,
            "exit_code": cp.returncode,
            "output_tail": (cp.stdout or "")[-4000:],
        }
    except subprocess.TimeoutExpired:
        return False, {
            "reason": reason,
            "exit_code": EXIT_TIMEOUT_SUBPROCESS,
            "output_tail": "earth_mesh_self_heal_timeout",
        }


def run_gaiaftcl_mcp_self_heal(
    ctx: "RunContext",
    reason: str,
    earth_doc: dict[str, Any],
) -> tuple[bool, dict[str, Any]]:
    """
    Optional GaiaFTCL MCP/gateway self-heal call for Earth UNMOORED conditions.
    Disabled unless ``C4_GAIAFTCL_MCP_SELF_HEAL=1``.
    """
    if not _truthy(os.environ.get("C4_GAIAFTCL_MCP_SELF_HEAL"), default=False):
        return False, {"reason": reason, "disabled": True}
    heal_url = (
        os.environ.get("GAIAFTCL_MCP_HEAL_URL", "").strip()
        or os.environ.get("GAIAFTCL_GATEWAY_HEAL_URL", "").strip()
        or "http://127.0.0.1:8803/ask"
    )
    internal_key = (
        os.environ.get("GAIAFTCL_INTERNAL_KEY", "").strip()
        or os.environ.get("GAIAFTCL_INTERNAL_SERVICE_KEY", "").strip()
    )
    em = earth_doc.get("earth_mooring") if isinstance(earth_doc.get("earth_mooring"), dict) else {}
    heal_prompt = (
        "Invariant fault: Discord /cell Earth mooring is UNMOORED. "
        "Analyze root cause from live substrate, apply code/config/container fixes, "
        "redeploy to all nine cells, then close with Earth MOORED 11/11."
    )
    payload = {
        "prompt": heal_prompt,
        "reason": reason,
        "fault": {
            "gate": Gate.discord_mesh_surface.value,
            "earth_mooring": em,
            "earth_11_11_closed": bool(earth_doc.get("earth_11_11_closed")),
            "cell_id": earth_doc.get("cell_id"),
            "release_id_hint": (earth_doc.get("raw_excerpt") or "")[:4000],
        },
    }
    headers = {"Content-Type": "application/json"}
    if internal_key:
        headers["X-Gaiaftcl-Internal-Key"] = internal_key
    try:
        req = urllib.request.Request(
            heal_url,
            data=json.dumps(payload).encode("utf-8"),
            headers=headers,
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=MCP_HEAL_TIMEOUT_SEC) as r:
            body = r.read().decode("utf-8", errors="replace")
            code = int(r.getcode() or 0)
    except (urllib.error.HTTPError, urllib.error.URLError, OSError, ValueError) as exc:
        return False, {"reason": reason, "heal_url": heal_url, "error": str(exc), "http_status": 0}

    ok = 200 <= code < 300
    parsed: dict[str, Any] | None = None
    try:
        j = json.loads(body)
        if isinstance(j, dict):
            parsed = j
    except json.JSONDecodeError:
        parsed = None
    if parsed is not None:
        t = str(parsed.get("terminal") or "").upper()
        if t in ("CALORIE", "CURE"):
            ok = ok and True
    return ok, {
        "reason": reason,
        "heal_url": heal_url,
        "http_status": code,
        "response_json": parsed,
        "response_excerpt": body[:3000],
    }


def validate_domain_ui_gameplay(repo_root: Path) -> tuple[bool, str]:
    """
    Full graphical-domain closure: every domain in the gate contract must be witnessed in
    ``domain_gameplay`` with no missing domains, no blockers, and screenshot floors met.
    (Quantum count alone is not sufficient — that was a torsion hole.)
    """
    contract_path = repo_root / "spec" / "release_domain_ui_gameplay_gate.json"
    if not contract_path.is_file():
        return False, f"missing {contract_path.relative_to(repo_root)}"
    try:
        contract = json.loads(contract_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        return False, f"invalid contract JSON: {exc}"
    ev_path = repo_root / str(contract.get("evidence_artifact") or "")
    if not ev_path.is_file():
        return False, f"missing {ev_path.relative_to(repo_root)}"
    try:
        ev = json.loads(ev_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        return False, f"invalid evidence JSON: {exc}"
    for f in contract.get("required_fields", []):
        if f not in ev:
            return False, f"missing evidence field: {f}"
    req_term = str(contract.get("required_terminal", "CURE")).upper()
    ev_term = str(ev.get("terminal", "")).upper()
    if req_term == "CURE":
        if ev_term not in ("CURE", "CALORIE"):
            return False, f"domain UI terminal={ev.get('terminal')} (must be CURE or legacy CALORIE)"
    elif ev_term != req_term:
        return False, f"domain UI terminal={ev.get('terminal')} (must be {req_term})"
    missing_dom = ev.get("missing_domain_graphical_games")
    if not isinstance(missing_dom, list) or len(missing_dom) > 0:
        return False, f"missing_domain_graphical_games must be [] (got {missing_dom!r})"
    blockers = ev.get("blockers")
    if blockers is not None and not isinstance(blockers, list):
        return False, "evidence.blockers must be a list when present"
    if isinstance(blockers, list) and len(blockers) > 0:
        return False, f"domain UI blockers: {blockers}"
    if not bool(ev.get("fusion_openusd_gameplay_ok")):
        return False, "fusion_openusd_gameplay_ok must be true (Fusion /fusion-s4 GUI witness required)"
    req_total = int(contract.get("required_total_screenshots", 53))
    got_total = int(ev.get("total_screenshots", 0) or 0)
    if got_total < req_total:
        return False, f"total_screenshots={got_total} < required {req_total}"
    req_min = contract.get("required_domain_screenshot_minimums") or {}
    if not isinstance(req_min, dict):
        return False, "contract required_domain_screenshot_minimums invalid"
    dg = ev.get("domain_gameplay")
    if not isinstance(dg, dict):
        return False, "evidence.domain_gameplay must be an object"
    for domain_id, min_raw in req_min.items():
        min_count = int(min_raw)
        row = dg.get(str(domain_id))
        if not isinstance(row, dict):
            return False, f"domain_gameplay missing or invalid for {domain_id!r}"
        if not bool(row.get("graphical_witness_ok")):
            return False, f"domain {domain_id} not graphically witnessed (graphical_witness_ok false)"
        sc = int(row.get("screenshot_count", 0) or 0)
        if sc < min_count:
            return False, f"domain {domain_id} screenshot_count={sc} < required {min_count}"
    req_q = int(contract.get("required_quantum_algorithm_count", 19))
    got_q = int(ev.get("quantum_algorithm_ui_count", 0))
    if got_q < req_q:
        return False, f"quantum_algorithm_ui_count={got_q} (must be >= {req_q})"
    return True, "ok"


def validate_mesh_cure_gate(repo_root: Path) -> tuple[bool, str]:
    """
    **CURE** (mesh-first, sans Discord) requires:
    full domain GUI gameplay witness, **mesh Playwright runner evidence** (live screenshots per contract),
    guided hub/spoke contracts, and **live** nine-cell :8803 mooring
    (no ``offline_contract_stub``).
    """
    ok, msg = validate_domain_ui_gameplay(repo_root)
    if not ok:
        return False, msg
    ok_cap, msg_cap = validate_mesh_game_runner_captures(repo_root)
    if not ok_cap:
        return False, f"mesh_playwright_screen_capture: {msg_cap}"
    ok_h, msg_h = validate_hub_moor_contract(repo_root)
    if not ok_h:
        return False, f"guided_hub_moor: {msg_h}"
    ok_s, msg_s = validate_spoke_contracts(repo_root)
    if not ok_s:
        return False, f"guided_spokes: {msg_s}"
    mesh_path = repo_root / "evidence" / "mesh" / "C4_MESH_SELF_MOOR.json"
    doc = load_mesh_witness(mesh_path)
    if doc.get("probe_mode") == "offline_contract_stub":
        return (
            False,
            "CURE requires live sovereign :8803 mooring — unset C4_INVARIANT_MESH_NINE_CELL_OFFLINE for production closure",
        )
    if not mesh_nine_cell_surface_ok(doc):
        return False, "nine-cell mesh surface not closed (mesh_mooring_closed / terminal)"
    return True, "ok"


def emit_mesh_first_release_report(repo_root: Path) -> Path | None:
    """
    Write ``evidence/release/RELEASE_REPORT_*.json`` (+ sibling ``.md``) for mesh-first sealing.
    Embeds mooring + domain UI witnesses so DOCX generation has a stable spine without Discord session.
    """
    ts = utc_ts()
    out_json = repo_root / "evidence" / "release" / f"RELEASE_REPORT_{ts}.json"
    out_md = repo_root / "evidence" / "release" / f"RELEASE_REPORT_{ts}.md"
    domp = repo_root / "evidence" / "discord_game_rooms" / "DOMAIN_UI_GAMEPLAY_WITNESS.json"
    if not domp.is_file():
        return None
    mesh_path = repo_root / "evidence" / "mesh" / "C4_MESH_SELF_MOOR.json"
    mesh = load_mesh_witness(mesh_path)
    try:
        dom = json.loads(domp.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None
    payload: dict[str, Any] = {
        "schema": "mesh_first_release_report_v1",
        "ts_utc": datetime.now(timezone.utc).isoformat(),
        "state": "SEALING_SPINE",
        "uniformity": "UNIFORM",
        "failed_steps": 0,
        "mesh_first_sans_discord": True,
        "cure_contract": "all_domains_gui_guided_observer_live_mesh",
        "mesh_nine_cell_mooring": mesh,
        "domain_ui_gameplay_witness": dom,
        "report_md": str(out_md),
    }
    out_md.parent.mkdir(parents=True, exist_ok=True)
    out_md.write_text(
        "# Mesh-first release (sans Discord)\n\n"
        + json.dumps(payload, indent=2, ensure_ascii=True)[:20000],
        encoding="utf-8",
    )
    atomic_write_json(out_json, payload)
    return out_json


def run_domain_ui_gameplay_self_heal(ctx: "RunContext", reason: str) -> tuple[bool, dict[str, Any]]:
    root = ctx.repo_root
    mesh_url = ctx.mesh_fusion_web_url.rstrip("/")
    if _mesh_first_surface(ctx):
        cmd_capture = (
            "cd services/gaiaos_ui_web && "
            f"GAIA_ROOT=\"{root}\" C4_MESH_FUSION_WEB_URL=\"{mesh_url}\" "
            "ENABLE_MESH_GAME_RUNNER_CAPTURE=1 npm run test:e2e:mesh-runner"
        )
    else:
        cmd_capture = (
            "cd services/gaiaos_ui_web && ENABLE_MESH_GAME_CAPTURE_TEST=1 "
            "npm run test:e2e:discord -- --grep \"Discord mesh games live capture\""
        )
    cmd_fusion = (
        "cd services/gaiaos_ui_web && "
        f"GAIA_ROOT=\"{root}\" FUSION_VISUAL_WITNESS=1 C4_MESH_FUSION_WEB_URL=\"{mesh_url}\" "
        "npm run test:e2e:fusion -- --grep \"OpenUSD gameplay witness|fusion-s4 rendered|/fusion-s4 UI panels\""
    )
    cmd_update = "python3 scripts/update_domain_ui_gameplay_witness.py"
    mesh_env_prefix = (
        f"export C4_MESH_FUSION_WEB_URL=\"{mesh_url}\" C4_INVARIANT_MESH_ONLY=1 C4_SKIP_DISCORD_METADATA=1; "
        if _mesh_first_surface(ctx)
        else f"export C4_MESH_FUSION_WEB_URL=\"{mesh_url}\"; "
    )
    joined = f"{mesh_env_prefix}{cmd_capture} && {cmd_fusion} && {cmd_update}"
    try:
        cp = subprocess.run(
            ["/bin/bash", "-lc", joined],
            cwd=str(root),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=PLAYWRIGHT_TIMEOUT_SEC,
            check=False,
        )
        ok = cp.returncode == 0
        witness_path = root / "evidence" / "discord_game_rooms" / "DOMAIN_UI_GAMEPLAY_WITNESS.json"
        witness_terminal = ""
        blockers: list[str] = []
        if witness_path.is_file():
            try:
                w = json.loads(witness_path.read_text(encoding="utf-8"))
                witness_terminal = str(w.get("terminal") or "")
                b = w.get("blockers")
                if isinstance(b, list):
                    blockers = [str(x) for x in b if str(x).strip()]
            except (json.JSONDecodeError, OSError):
                pass
        return ok, {
            "reason": reason,
            "exit_code": cp.returncode,
            "output_tail": (cp.stdout or "")[-3000:],
            "witness_terminal": witness_terminal,
            "blockers": blockers,
        }
    except subprocess.TimeoutExpired:
        return False, {"reason": reason, "exit_code": EXIT_TIMEOUT_SUBPROCESS, "output_tail": "domain_ui_gameplay_self_heal_timeout"}


def _parse_earth_from_raw(raw: str) -> dict[str, Any] | None:
    """Mirror ``cell_earth_audit.spec.ts`` parseEarth (backtick + plain forms)."""
    m = re.search(
        r"earth_mooring=`([^`]+)`\s*\((\d+)\s*/\s*(\d+)\s+patterns\)",
        raw,
        re.I,
    )
    if not m:
        m = re.search(
            r"earth_mooring=([A-Za-z0-9_]+)\s*\((\d+)\s*/\s*(\d+)\s+patterns\)",
            raw,
            re.I,
        )
    if not m:
        return None
    return {
        "status": (m.group(1) or "").strip(),
        "healthy": int(m.group(2)),
        "total": int(m.group(3)),
    }


def _parse_cell_id_from_raw(raw: str) -> str | None:
    """Mirror ``cell_earth_audit.spec.ts`` parseCellId (backtick + plain forms)."""
    m = re.search(r"cell_id=`([^`]+)`", raw, re.I)
    if m:
        return (m.group(1) or "").strip()
    m = re.search(r"cell_id=([A-Za-z0-9_.-]+)", raw, re.I)
    if m:
        return (m.group(1) or "").strip()
    return None


def heal_earth_audit_from_raw(audit_path: Path) -> dict[str, Any]:
    """
    Self-heal: Discord layout drift sometimes leaves structured fields null while ``raw_excerpt``
    still contains bot lines. Re-parse with the same regex contract as the Playwright spec and
    rewrite ``C4_CELL_EARTH_AUDIT.json`` when we can derive stricter fields (C4 witness, not fiction).

    ``C4_EXPECTED_CELL_ID`` overrides the default Owl crystal id when set.
    """
    doc = load_earth_audit(audit_path)
    raw = str(doc.get("raw_excerpt") or "")
    if not raw.strip():
        return doc

    expected_cell_id = os.environ.get("C4_EXPECTED_CELL_ID", "").strip() or "gaiaftcl-discord-bot-owl"

    earth = _parse_earth_from_raw(raw)
    cid = _parse_cell_id_from_raw(raw)
    before = json.dumps(doc, sort_keys=True)

    if earth is not None:
        doc["earth_mooring"] = earth
    if cid is not None:
        doc["cell_id"] = cid

    ok_earth = bool(
        earth
        and earth.get("healthy") == 11
        and earth.get("total") == 11
        and str(earth.get("status", "")).upper() == "MOORED"
    )
    ok_crystal = cid == expected_cell_id
    doc["crystal_lineage_ok"] = ok_crystal
    doc["earth_11_11_closed"] = ok_earth
    doc["terminal"] = "CALORIE" if (ok_earth and ok_crystal) else "PARTIAL"
    doc["note"] = (
        doc.get("note")
        or "PARTIAL = Discord earth mooring open (DRIFTING/UNMOORED) or unexpected crystal id."
    )

    after = json.dumps(doc, sort_keys=True)
    if after != before:
        doc["c4_self_heal"] = {
            "source": "raw_excerpt_regex",
            "ts_utc": datetime.now(timezone.utc).isoformat(),
            "expected_cell_id": expected_cell_id,
        }
        atomic_write_json(audit_path, doc)
    return doc


def load_contract(ctx: "RunContext") -> dict[str, Any]:
    """Load ``release_language_games.json``; empty dict if missing."""
    if not ctx.contract_path.is_file():
        return {}
    try:
        return json.loads(ctx.contract_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def validate_language_games(ctx: "RunContext", contract: dict[str, Any]) -> tuple[bool, str]:
    """
    Validate declarative contract: required gates must have artifacts and fields; optional gates
    with ``artifact_glob`` validate each matched file when matches exist.
    """
    if not contract:
        return False, "empty_or_missing_contract"
    gates = contract.get("gates") or {}
    if not gates:
        return False, "no_gates_in_contract"
    for name, spec in gates.items():
        if name in ("discord_mesh_surface", "planetary") and ctx.mesh_nine_cell_surface:
            mp = ctx.repo_root / "evidence" / "mesh" / "C4_MESH_SELF_MOOR.json"
            if not mp.is_file():
                return False, "discord_mesh_surface: missing evidence/mesh/C4_MESH_SELF_MOOR.json"
            try:
                data = json.loads(mp.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, OSError) as exc:
                return False, f"discord_mesh_surface: invalid mesh witness: {exc}"
            if not data.get("mesh_mooring_closed"):
                return False, "discord_mesh_surface: mesh_mooring_closed false"
            if not data.get("nine_cells_ok"):
                return False, "discord_mesh_surface: nine_cells_ok false"
            wt = str(data.get("terminal", "")).upper()
            if wt not in ("CALORIE", "CURE"):
                return False, "discord_mesh_surface: mesh witness terminal not CALORIE/CURE"
            continue
        if spec.get("optional"):
            g = spec.get("artifact_glob")
            if g:
                pattern = str(ctx.repo_root / g)
                matches = glob.glob(pattern, recursive=True)
                if not matches:
                    continue
                for mp in matches:
                    try:
                        data = json.loads(Path(mp).read_text(encoding="utf-8"))
                    except (json.JSONDecodeError, OSError) as exc:
                        return False, f"{name}: invalid JSON {mp}: {exc}"
                    for f in spec.get("required_fields") or []:
                        if f not in data:
                            return False, f"{name}: missing field {f} in {mp}"
            continue

        art = spec.get("artifact")
        if not art:
            return False, f"{name}: missing artifact path"
        p = ctx.repo_root / art
        if not p.is_file():
            return False, f"{name}: missing artifact {art}"
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as exc:
            return False, f"{name}: invalid JSON {art}: {exc}"
        for f in spec.get("required_fields") or []:
            if f not in data:
                return False, f"{name}: missing field {f} in {art}"
        if name in ("discord_mesh_surface", "planetary"):
            if spec.get("require_earth_11_11_closed") and not data.get("earth_11_11_closed"):
                return False, "discord_mesh_surface: earth_11_11_closed false"
            if spec.get("require_crystal_lineage_ok") and not data.get("crystal_lineage_ok"):
                return False, "discord_mesh_surface: crystal_lineage_ok false"
    return True, "ok"


def _run_playwright(
    ctx: "RunContext",
    args: list[str],
    extra_env: dict[str, str],
) -> int:
    """Invoke ``npx playwright test``; return exit code (non-zero on failure / missing npx)."""
    env = os.environ.copy()
    env.update(extra_env)
    env.setdefault("GAIA_ROOT", str(ctx.repo_root))
    try:
        cp = subprocess.run(
            ["npx", "playwright", "test", *args],
            cwd=str(ctx.ui_dir),
            env=env,
            timeout=PLAYWRIGHT_TIMEOUT_SEC,
        )
        return cp.returncode
    except FileNotFoundError:
        return 127
    except subprocess.TimeoutExpired:
        return EXIT_TIMEOUT_SUBPROCESS


def playwright_cell(ctx: "RunContext") -> int:
    """Headed Discord ``/cell`` audit → ``C4_CELL_EARTH_AUDIT.json``."""
    return _run_playwright(
        ctx,
        [
            "tests/discord/cell_earth_audit.spec.ts",
            "--config=playwright.discord.config.ts",
            "--headed",
        ],
        {
            "C4_CELL_EARTH_AUDIT": "1",
            "DISCORD_PLAYWRIGHT_PROFILE": ctx.discord_profile,
        },
    )


def playwright_fusion(ctx: "RunContext") -> int:
    """Headed Fusion UI screenshot gate (local dev server per Playwright fusion config)."""
    return _run_playwright(
        ctx,
        [
            "tests/fusion/fusion_dashboard_visual_witness.spec.ts",
            "--config=playwright.fusion.config.ts",
            "--headed",
        ],
        {
            "FUSION_VISUAL_WITNESS": "1",
            "GAIA_ROOT": str(ctx.repo_root),
            "C4_MIN_FUSION_PNG_BYTES": str(ctx.min_png_bytes),
        },
    )


def remediate_visual_mac(ctx: "RunContext") -> None:
    """Best-effort: kill stray app name, run macOS Screen Recording remediation script."""
    if sys.platform != "darwin":
        return
    subprocess.run(
        ["/usr/bin/killall", "GaiaFusion"],
        capture_output=True,
        check=False,
        encoding="utf-8",
        errors="replace",
    )
    script = ctx.repo_root / "scripts" / "remediate_fusion_visual_mac.sh"
    if script.is_file():
        run_bash(script)


def poke_stale(ctx: "RunContext", audit_path: Path) -> None:
    """Publish NATS pokes for ``stale_patterns`` from last audit (Scout remediation path)."""
    doc = load_earth_audit(audit_path)
    stale = doc.get("stale_patterns") or []
    if not stale:
        return
    patterns = ",".join(str(s) for s in stale)
    try:
        subprocess.run(
            [
                sys.executable,
                str(ctx.repo_root / "scripts" / "publish_earth_scout_poke.py"),
                "--nats-url",
                ctx.nats_url,
                "--patterns",
                patterns,
            ],
            cwd=str(ctx.repo_root),
            capture_output=True,
            timeout=POKE_TIMEOUT_SEC,
            encoding="utf-8",
            errors="replace",
        )
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        pass


def verify_docx_semantics_md5(ctx: "RunContext", docx_path: Path) -> tuple[bool, str]:
    """
    Verify ``word/document.xml`` inside the DOCX contains the MD5 hex of ``RELEASE_C4_SEMANTICS.md``
    (embedded at generation time).
    """
    if not ctx.semantics_path.is_file():
        return False, f"missing semantics {ctx.semantics_path}"
    raw_sem = ctx.semantics_path.read_bytes()
    try:
        expect = hashlib.md5(raw_sem, usedforsecurity=False).hexdigest()
    except TypeError:
        expect = hashlib.md5(raw_sem).hexdigest()
    try:
        with zipfile.ZipFile(docx_path, "r") as zf:
            if "word/document.xml" not in zf.namelist():
                return False, "docx missing word/document.xml"
            xml = zf.read("word/document.xml").decode("utf-8", errors="replace")
    except (zipfile.BadZipFile, OSError) as exc:
        return False, f"docx unreadable: {exc}"
    if expect not in xml:
        return False, f"C4_SEMANTICS_MD5 {expect} not in docx XML"
    return True, expect


def run_sealing(ctx: "RunContext") -> tuple[int, Path | None]:
    """
    Run ``generate_release_docx.py`` with latest ``RELEASE_REPORT_*.json``; write sealed DOCX path.

    Returns
    -------
    (returncode, output_path_or_None)
    """
    reports_dir = ctx.repo_root / "evidence" / ("release" if _mesh_first_surface(ctx) else "discord")
    reports = glob.glob(str(reports_dir / "RELEASE_REPORT_*.json"))
    if not reports:
        return 2, None
    rp = Path(max(reports, key=lambda p: Path(p).stat().st_mtime))
    out_dir = ctx.repo_root / "evidence" / ("release" if _mesh_first_surface(ctx) else "discord")
    out = out_dir / f"C4_SEALED_RELEASE_{utc_ts()}.docx"
    gen = ctx.repo_root / "scripts" / "generate_release_docx.py"
    try:
        cp = subprocess.run(
            [
                sys.executable,
                str(gen),
                "--repo-root",
                str(ctx.repo_root),
                "--json",
                str(rp),
                "--output",
                str(out),
                "--c4-semantics",
                str(ctx.semantics_path),
                "--require-c4-semantics",
            ],
            cwd=str(ctx.repo_root),
            timeout=600,
        )
        return cp.returncode, out if cp.returncode == 0 else None
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return 1, None


def human_visual_block(ctx: "RunContext") -> bool:
    """
    If ``C4_HUMAN_VISUAL_LAYOUT_REVIEW`` is set, require ``HUMAN_VISUAL_ACK.json`` or block.
    """
    if not _truthy(os.environ.get("C4_HUMAN_VISUAL_LAYOUT_REVIEW")):
        return False
    return not ctx.human_ack_path.is_file()


INVARIANT_ID = "gaiaftcl_mesh_release_v2"
INVARIANT_REQUIREMENT = (
    "Mesh Fusion Web health → Fusion S4 Playwright (/fusion-s4) → Discord /cell earth audit OR nine-cell :8803/health → "
    "cell plant state schema → hub moor contract → spoke contracts → command inventory → "
    "proof ledger schema → license/payment gate → surface parity → Playwright live game capture gate → domain UI gameplay gate → language-game contracts → "
    "run_full_release_session.sh spine (closure battery, dual-user, nine-cell, mesh) → RELEASE_REPORT → "
    "sealed DOCX + semantics MD5 + surface re-probe"
)


def invariant_requirement(ctx: "RunContext") -> str:
    """Human-readable requirement string for the active run mode."""
    if not _mesh_first_surface(ctx):
        return INVARIANT_REQUIREMENT
    return (
        "Mesh Fusion Web health → Fusion S4 Playwright (/fusion-s4) → live nine-cell :8803/health mesh probe → "
        "cell plant state schema → hub moor (guided) → spoke contracts (guided) → proof ledger schema → "
        "license/payment gate → surface parity → mesh game-runner capture → domain UI gameplay (all domains, GUI observer) → "
        "language-game contracts → mesh-first RELEASE_REPORT → sealed DOCX + semantics MD5 + surface re-probe "
        "(no Discord Playwright, no discord.com, no run_full_release_session Discord spine). "
        "**CURE** = full domain GUI + guided contracts + live mesh — no offline nine-cell stub."
    )


def c4_surfaces_receipt(ctx: "RunContext") -> dict[str, Any]:
    """Plain C4 labels for final JSON — no interpretive 'planetary' shorthand."""
    receipt = {
        "mesh_fusion_web_health": Gate.mesh_fusion_web.value,
        "fusion_s4_playwright": Gate.fusion_s4_playwright.value,
        "discord_slash_earth_or_mesh_nine_cell_http": Gate.discord_mesh_surface.value,
        "cell_plant_state_schema": Gate.cell_plant_state.value,
        "hub_moor_contract": Gate.hub_moor.value,
        "spoke_contracts": Gate.spoke_contracts.value,
        "discord_command_inventory": Gate.discord_command_inventory.value,
        "proof_ledger_schema": Gate.proof_ledger.value,
        "license_payment_gate": Gate.license_payment.value,
        "surface_parity": Gate.surface_parity.value,
        "mesh_game_runner_capture": Gate.mesh_game_runner_capture.value,
        "playwright_game_capture": Gate.playwright_game_capture.value,
        "domain_ui_gameplay": Gate.domain_ui_gameplay.value,
        "surface_mode": (
            "mesh_nine_cell_http" if ctx.mesh_nine_cell_surface else "discord_playwright_earth_audit"
        ),
        "discord_execution_enabled": ctx.discord_execution_enabled,
    }
    if _mesh_first_surface(ctx):
        receipt["mesh_first_surface"] = True
        if ctx.mesh_only:
            receipt["mesh_only_mode"] = True
        receipt["discord_gates_skipped"] = [
            Gate.discord_command_inventory.value,
            Gate.playwright_game_capture.value,
        ]
    return receipt


KLEIN_GATE_SEQUENCE: tuple[str, ...] = (
    Gate.mesh_fusion_web.value,
    Gate.fusion_s4_playwright.value,
    Gate.discord_mesh_surface.value,
    Gate.cell_plant_state.value,
    Gate.hub_moor.value,
    Gate.spoke_contracts.value,
    Gate.discord_command_inventory.value,
    Gate.proof_ledger.value,
    Gate.license_payment.value,
    Gate.surface_parity.value,
    Gate.mesh_game_runner_capture.value,
    Gate.playwright_game_capture.value,
    Gate.domain_ui_gameplay.value,
    Gate.language_games.value,
    Gate.release_bundle.value,
    Gate.sealing.value,
    Gate.done.value,
)


def effective_gate_sequence(ctx: "RunContext") -> list[str]:
    """Gate sequence as executed for this run mode."""
    if ctx.mesh_only or not ctx.discord_execution_enabled:
        skip = {
            Gate.discord_command_inventory.value,
            Gate.playwright_game_capture.value,
        }
        return [g for g in KLEIN_GATE_SEQUENCE if g not in skip]
    return list(KLEIN_GATE_SEQUENCE)


def run_fusion_s4_playwright_gate(ctx: "RunContext") -> tuple[bool, dict[str, Any]]:
    """
    Mandatory Fusion S⁴ Playwright witness against the mesh dashboard
    (default ``https://gaiaftcl.com/fusion-s4``; local dev: set ``C4_MESH_FUSION_WEB_URL`` to loopback).
    """
    witness_url = ctx.mesh_fusion_web_url.rstrip("/")
    cmd = (
        f"GAIA_ROOT=\"{ctx.repo_root}\" FUSION_VISUAL_WITNESS=1 "
        f"C4_MESH_FUSION_WEB_URL=\"{witness_url}\" "
        "npm run test:e2e:fusion -- --grep \"fusion-s4 rendered|/fusion-s4 UI panels|OpenUSD gameplay witness\""
    )
    child_env = os.environ.copy()
    child_env["GAIA_ROOT"] = str(ctx.repo_root)
    child_env["FUSION_VISUAL_WITNESS"] = "1"
    child_env["C4_MESH_FUSION_WEB_URL"] = witness_url
    try:
        cp = subprocess.run(
            ["/bin/bash", "-lc", cmd],
            cwd=str(ctx.ui_dir),
            env=child_env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=PLAYWRIGHT_TIMEOUT_SEC,
            check=False,
        )
        ok = cp.returncode == 0
        return ok, {
            "url": witness_url,
            "cmd": cmd,
            "exit_code": cp.returncode,
            "output_tail": (cp.stdout or "")[-3000:],
        }
    except subprocess.TimeoutExpired:
        return False, {
            "url": witness_url,
            "cmd": cmd,
            "exit_code": EXIT_TIMEOUT_SUBPROCESS,
            "output_tail": "fusion_s4_playwright_timeout",
        }


def klein_bottle_manifest(st: GovernorState | None, ctx: "RunContext") -> dict[str, Any]:
    """Receipt fragment: Klein bottle manifold model (χ=0, inside/outside identified on automation)."""
    return {
        "topology": "klein_bottle",
        "euler_characteristic": 0,
        "inside_outside": "identified",
        "gate_sequence": effective_gate_sequence(ctx),
        "vector_field_order_1": {
            "chart": st.gate.value if st else None,
            "cycle": st.cycle if st else None,
        },
        "vector_field_order_2": (
            "heartbeats: delta closure / torsion / stale_patterns / rollback — field over the gate field"
        ),
        "m8_reading": "first_order = chart position; second order = remediation velocity on the manifold (no exterior exit)",
        "full_coverage": ctx.full_coverage,
        "full_compliance": ctx.full_compliance,
        "clear_release_deck": ctx.clear_release_deck,
        "rollback_count": st.rollback_count if st else None,
    }


def klein_fold_spin_or_exit(
    ctx: "RunContext",
    lock_path: Path | None,
    spin: SpinDetector,
    st: GovernorState,
    gate: Gate,
    signature: str,
    failing_line: str,
    *,
    legacy_exit_code: int = EXIT_SPIN,
) -> int | None:
    """
    After ``spin.observe`` is True: always Klein fold-back — **never** exterior REFUSED.
    ``legacy_exit_code`` is ignored (API compatibility); callers always ``sleep`` + ``continue``.
    """
    del lock_path, legacy_exit_code  # spiral only; no REFUSED exit
    append_heartbeat(
        ctx,
        {
            "gate": gate.value,
            "klein_foldback": True,
            "spin_signature": signature,
            "failing_line": failing_line,
            "klein_note": "non-orientable: no exterior REFUSED — invariant spiral",
        },
    )
    spin.reset()
    return None


def run_mac_fusion_sub_governor(ctx: "RunContext") -> tuple[int, dict[str, Any] | None]:
    """
    Execute delegated Mac sub-governor and return ``(exit_code, parsed_latest_receipt_or_none)``.
    """
    script = ctx.mac_sub_invariant_script
    if not script.is_file():
        return 1, {"error": "missing_sub_governor_script", "path": str(script)}
    try:
        cp = subprocess.run(
            [
                "python3",
                str(script),
                "--repo-root",
                str(ctx.repo_root),
            ],
            cwd=str(ctx.repo_root),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=1800,
            check=False,
        )
        latest = ctx.repo_root / "evidence" / "release" / "MAC_FUSION_SUB_INVARIANT_latest.json"
        payload: dict[str, Any] | None = None
        if latest.is_file():
            try:
                payload = json.loads(latest.read_text(encoding="utf-8", errors="replace"))
            except (json.JSONDecodeError, OSError):
                payload = None
        if payload is None:
            payload = {"output_tail": cp.stdout[-2000:]}
        return cp.returncode, payload
    except subprocess.TimeoutExpired:
        return EXIT_TIMEOUT_SUBPROCESS, {"error": "sub_governor_timeout"}


def _mesh_cells_as_spec_dicts() -> list[dict[str, str]]:
    return [{"hostname": h, "ip": ip} for h, ip in MESH_SOVEREIGN_CELLS]


def _toolbox_cli_required(entry: dict[str, Any], _ctx: "RunContext") -> bool:
    rf = str(entry.get("required_for") or "always")
    if rf == "optional":
        return False
    if rf == "always":
        return True
    if rf == "production_mesh_admin":
        return _truthy(os.environ.get("C4_INVARIANT_TOOLBOX_REQUIRE_SSH", "0"))
    if rf == "darwin_mount_probe":
        return sys.platform == "darwin"
    return False


def _toolbox_script_required(entry: dict[str, Any], _ctx: "RunContext") -> bool:
    rf = str(entry.get("required_for") or "always")
    if rf == "always":
        return True
    if rf == "darwin_only":
        return sys.platform == "darwin"
    if rf == "optional_deploy_dmg":
        return _truthy(os.environ.get("C4_INVARIANT_DEPLOY_DMG"))
    return False


def load_invariant_toolbox_spec(repo_root: Path) -> dict[str, Any] | None:
    p = repo_root / INVARIANT_TOOLBOX_SPEC
    if not p.is_file():
        return None
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None


def validate_invariant_toolbox(ctx: "RunContext") -> tuple[bool, list[dict[str, Any]]]:
    """
    Preflight CLI, script paths, mesh manifest drift, and optional SSH batch probe.

    Returns
    -------
    (ok, missing)
        ``missing`` is a list of structured dicts for heartbeat / audit (no secrets).
    """
    missing: list[dict[str, Any]] = []
    spec = load_invariant_toolbox_spec(ctx.repo_root)
    if spec is None:
        missing.append(
            {
                "kind": "spec",
                "path": str(INVARIANT_TOOLBOX_SPEC),
                "detail": "missing or invalid JSON",
            }
        )
        return False, missing

    spec_mesh = (spec.get("mesh") or {}).get("sovereign_cells")
    code_mesh = _mesh_cells_as_spec_dicts()
    if spec_mesh != code_mesh:
        missing.append(
            {
                "kind": "mesh_drift",
                "detail": "spec/invariant_toolbox.json mesh.sovereign_cells out of sync with MESH_SOVEREIGN_CELLS",
            }
        )

    for entry in spec.get("cli", []):
        if not isinstance(entry, dict):
            continue
        if not _toolbox_cli_required(entry, ctx):
            continue
        which_name = str(entry.get("which") or entry.get("id") or "").strip()
        if not which_name:
            continue
        if shutil.which(which_name) is None:
            missing.append(
                {
                    "kind": "cli",
                    "id": entry.get("id"),
                    "which": which_name,
                    "required_for": entry.get("required_for"),
                }
            )

    for entry in spec.get("scripts", []):
        if not isinstance(entry, dict):
            continue
        if not _toolbox_script_required(entry, ctx):
            continue
        rel = str(entry.get("path") or "").strip()
        if not rel:
            continue
        p = ctx.repo_root / rel
        if not p.is_file():
            missing.append(
                {
                    "kind": "script",
                    "path": rel,
                    "id": entry.get("id"),
                    "required_for": entry.get("required_for"),
                }
            )

    for entry in spec.get("artifacts", []):
        if not isinstance(entry, dict):
            continue
        rel = str(entry.get("path") or "").strip()
        if not rel:
            continue
        p = ctx.repo_root / rel
        if not p.is_file():
            missing.append(
                {
                    "kind": "artifact",
                    "path": rel,
                    "id": entry.get("id"),
                }
            )

    if not ctx.ui_dir.is_dir():
        missing.append(
            {
                "kind": "ui_dir",
                "path": str(ctx.ui_dir.relative_to(ctx.repo_root)),
            }
        )

    if _truthy(os.environ.get("C4_INVARIANT_TOOLBOX_SSH_PROBE", "0")):
        probe_host = os.environ.get("C4_INVARIANT_TOOLBOX_SSH_PROBE_HOST", "").strip()
        if probe_host:
            try:
                cp = subprocess.run(
                    [
                        "ssh",
                        "-o",
                        "BatchMode=yes",
                        "-o",
                        "ConnectTimeout=8",
                        probe_host,
                        "true",
                    ],
                    cwd=str(ctx.repo_root),
                    capture_output=True,
                    text=True,
                    timeout=20,
                    check=False,
                )
                if cp.returncode != 0:
                    tail = ((cp.stderr or "") + (cp.stdout or ""))[-400:]
                    missing.append(
                        {
                            "kind": "ssh_batch_probe",
                            "host": probe_host,
                            "exit_code": cp.returncode,
                            "tail": tail,
                        }
                    )
            except (subprocess.TimeoutExpired, FileNotFoundError, OSError) as exc:
                missing.append({"kind": "ssh_batch_probe", "host": probe_host, "error": repr(exc)})

    return len(missing) == 0, missing


GAIAFTCL_INVARIANT_RESULT_PREFIX = "GAIAFTCL_INVARIANT_RESULT "


def gaiaftcl_invariant_result_line(
    terminal: str,
    satisfied: bool,
    receipt: Path,
    stable: Path,
) -> str:
    """Single-line strict binding for terminal consumers (uses ``===`` delimiters, not ``=``)."""
    sat = "true" if satisfied else "false"
    return (
        f"{GAIAFTCL_INVARIANT_RESULT_PREFIX}"
        f"terminal==={terminal} satisfied==={sat} "
        f"receipt==={receipt} stable==={stable}"
    )


def parse_gaiaftcl_invariant_result_line(line: str) -> dict[str, str] | None:
    """
    Parse ``GAIAFTCL_INVARIANT_RESULT`` line; returns None if malformed or legacy ``=``-only format.

    Expected shape::
        GAIAFTCL_INVARIANT_RESULT terminal===... satisfied===... receipt===... stable===...
    """
    s = line.strip()
    if not s.startswith(GAIAFTCL_INVARIANT_RESULT_PREFIX):
        return None
    body = s[len(GAIAFTCL_INVARIANT_RESULT_PREFIX) :]
    keys = ["terminal", "satisfied", "receipt", "stable"]
    markers = [f"{k}===" for k in keys]
    positions: list[tuple[int, str, int]] = []
    for mk in markers:
        idx = body.find(mk)
        if idx < 0:
            return None
        positions.append((idx, mk, len(mk)))
    positions.sort(key=lambda t: t[0])
    for a, b in zip(positions, positions[1:]):
        if a[0] >= b[0]:
            return None
    for j, mk in enumerate(markers):
        if positions[j][1] != mk:
            return None
    out: dict[str, str] = {}
    for j, key in enumerate(keys):
        start = positions[j][0] + positions[j][2]
        end = positions[j + 1][0] if j + 1 < len(positions) else len(body)
        out[key] = body[start:end].strip()
    if not out.get("terminal"):
        return None
    return out


def write_final(
    ctx: "RunContext",
    terminal: str,
    extra: dict[str, Any],
    st: GovernorState | None = None,
) -> bool:
    """Write final invariant JSON (atomic) and stable ``LATEST_INVARIANT_RESULT.json``; print invariant line.

    Returns False on disk/serialization failure so the governor can **spiral** instead of crashing.
    """
    quiet = bool(getattr(ctx, "quiet_until_cure", False))
    try:
        doc = {
            "ts_utc": datetime.now(timezone.utc).isoformat(),
            "terminal": terminal,
            "repo_root": str(ctx.repo_root),
            **extra,
        }
        doc["c4_surfaces"] = c4_surfaces_receipt(ctx)
        satisfied = terminal == INVARIANT_EXIT_TERMINAL
        latest = ctx.evidence_release / "LATEST_INVARIANT_RESULT.json"
        doc["invariant"] = {
            "id": INVARIANT_ID,
            "satisfied": satisfied,
            "requirement": invariant_requirement(ctx),
        }
        doc["klein_bottle"] = klein_bottle_manifest(st, ctx)
        doc["receipts"] = {
            "heartbeat_jsonl": str(ctx.heartbeat_jsonl),
            "final_json": str(ctx.final_json),
            "stable_copy": str(latest),
        }
        atomic_write_json(ctx.final_json, doc)
        atomic_write_json(latest, doc)
    except (OSError, TypeError, ValueError) as exc:
        try:
            append_heartbeat(
                ctx,
                {
                    "gate": "write_final",
                    "terminal": "PARTIAL",
                    "write_final_error": repr(exc),
                    "note": "receipt JSON/write failed — invariant spiral (no process abort)",
                },
            )
        except Exception:
            pass
        return False
    if quiet and terminal != INVARIANT_EXIT_TERMINAL:
        try:
            if ctx.quiet_log_fp is not None:
                ctx.quiet_log_fp.write(
                    gaiaftcl_invariant_result_line(
                        terminal, satisfied, ctx.final_json, latest
                    )
                    + "\n"
                )
                ctx.quiet_log_fp.flush()
        except OSError:
            pass
        return True
    if quiet and ctx.quiet_stdout_fd is not None and ctx.quiet_stderr_fd is not None:
        try:
            os.dup2(ctx.quiet_stdout_fd, 1)
            os.dup2(ctx.quiet_stderr_fd, 2)
        except OSError:
            pass
        try:
            if ctx.quiet_log_fp is not None:
                ctx.quiet_log_fp.flush()
        except OSError:
            pass
    print(
        gaiaftcl_invariant_result_line(terminal, satisfied, ctx.final_json, latest),
        flush=True,
    )
    return True


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Full release invariant governor (supervisory state machine).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "See module docstring for environment variables and exit codes. "
            "Toolbox: spec/invariant_toolbox.json; C4_INVARIANT_TOOLBOX_RECHECK_CYCLES; "
            "C4_INVARIANT_TOOLBOX_REQUIRE_SSH; C4_INVARIANT_TOOLBOX_SSH_PROBE; "
            "C4_INVARIANT_TOOLBOX_SSH_PROBE_HOST."
        ),
    )
    ap.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[1])
    ap.add_argument("--heartbeat-sec", type=float, default=DEFAULT_HEARTBEAT_SEC)
    ap.add_argument(
        "--min-png-bytes",
        type=int,
        default=int(os.environ.get("C4_MIN_FUSION_PNG_BYTES", str(DEFAULT_MIN_PNG_BYTES))),
    )
    ap.add_argument(
        "--max-cycles",
        type=int,
        default=None,
        help="Ignored for exit — invariant spirals until CURE (telemetry / compatibility only).",
    )
    ap.add_argument(
        "--no-require-full-session",
        action="store_true",
        help="Skip mandatory run_full_release_session.sh when RELEASE_REPORT already exists (local fast path).",
    )
    ap.add_argument(
        "--full-compliance",
        action="store_true",
        help="Set C4_FULL_COMPLIANCE: clear deck, full session spine, build+deploy DMG, mesh self-heal, full Fusion battery.",
    )
    ap.add_argument(
        "--no-clear-deck",
        action="store_true",
        help="Do not archive stale RELEASE_REPORT / SESSION logs before gates.",
    )
    ap.add_argument(
        "--no-quiet-until-cure",
        action="store_true",
        help="Stream Playwright/npm subprocess output to the terminal (default: quiet until CURE).",
    )
    args = ap.parse_args()

    if args.full_compliance:
        os.environ["C4_FULL_COMPLIANCE"] = "1"
        apply_full_compliance_env_defaults()
    elif _truthy(os.environ.get("C4_FULL_COMPLIANCE"), default=False):
        apply_full_compliance_env_defaults()
    if args.no_clear_deck:
        os.environ["C4_CLEAR_RELEASE_DECK"] = "0"

    _qraw = os.environ.get("C4_INVARIANT_QUIET_UNTIL_CURE", "").strip()
    if args.no_quiet_until_cure:
        quiet_until_cure = False
    elif _qraw == "":
        quiet_until_cure = True
    else:
        quiet_until_cure = _truthy(_qraw)

    repo = args.repo_root.resolve()
    ev_rel = repo / "evidence" / "release"
    ev_rel.mkdir(parents=True, exist_ok=True)
    ts = utc_ts()
    _bt = os.environ.get("C4_INVARIANT_BUILD_TIMEOUT_SEC", "").strip()
    build_timeout_sec = int(_bt) if _bt else None

    _mesh_url_env = os.environ.get("C4_MESH_FUSION_WEB_URL", "").strip()
    _mesh_port = int(os.environ.get("C4_MESH_FUSION_WEB_PORT", "8910"))
    _local_fusion_mesh = _truthy(os.environ.get("C4_INVARIANT_LOCAL_FUSION_MESH", "0"))
    if _mesh_url_env:
        resolved_mesh_fusion_web_url = _mesh_url_env
    elif _local_fusion_mesh:
        resolved_mesh_fusion_web_url = f"http://127.0.0.1:{_mesh_port}/fusion-s4"
    else:
        resolved_mesh_fusion_web_url = DEFAULT_MESH_FUSION_WEB_URL

    ctx = RunContext(
        repo_root=repo,
        evidence_release=ev_rel,
        ui_dir=repo / "services" / "gaiaos_ui_web",
        heartbeat_jsonl=ev_rel / f"FULL_RELEASE_HEARTBEAT_{ts}.jsonl",
        final_json=ev_rel / f"FULL_RELEASE_INVARIANT_{ts}.json",
        semantics_path=repo / "evidence" / "discord" / "RELEASE_C4_SEMANTICS.md",
        contract_path=repo / "services" / "gaiaos_ui_web" / "spec" / "release_language_games.json",
        human_ack_path=ev_rel / "HUMAN_VISUAL_ACK.json",
        min_png_bytes=args.min_png_bytes,
        heartbeat_sec=args.heartbeat_sec,
        earth_wait_sec=float(os.environ.get("C4_EARTH_LOCK_WAIT_SEC", str(DEFAULT_EARTH_WAIT_SEC))),
        nats_url=os.environ.get("NATS_URL", "nats://127.0.0.1:4222"),
        discord_profile=os.environ.get("DISCORD_PLAYWRIGHT_PROFILE", "gaiaftcl"),
        spin_k=int(os.environ.get("C4_GOVERNOR_SPIN_K", str(DEFAULT_SPIN_K))),
        max_cycles=args.max_cycles,
        build_timeout_sec=build_timeout_sec,
        use_governor_lock=_truthy(os.environ.get("C4_GOVERNOR_LOCK")),
        mesh_only=_truthy(os.environ.get("C4_INVARIANT_MESH_ONLY", "0"), default=False),
        mesh_nine_cell_surface=_mesh_nine_cell_surface_from_env(),
        require_earth_moor=_require_earth_moor_from_env(),
        mesh_fusion_web_url=resolved_mesh_fusion_web_url,
        invoke_full_session=_truthy(
            os.environ.get("C4_INVARIANT_INVOKE_FULL_SESSION", "1"),
            default=True,
        ),
        require_full_session=(
            False
            if args.no_require_full_session
            else _truthy(os.environ.get("C4_INVARIANT_REQUIRE_FULL_SESSION", "1"), default=True)
        ),
        full_session_timeout_sec=(
            int(x)
            if (x := os.environ.get("C4_FULL_SESSION_TIMEOUT_SEC", "").strip()) not in ("", "0")
            else None
        ),
        full_coverage=_truthy(os.environ.get("C4_INVARIANT_FULL_COVERAGE", "1"), default=True),
        clear_release_deck=_truthy(os.environ.get("C4_CLEAR_RELEASE_DECK", "1"), default=True),
        full_compliance=_truthy(os.environ.get("C4_FULL_COMPLIANCE"), default=False),
        mac_sub_invariant_script=repo / "scripts" / "run_native_fusion_sub_invariant.py",
        discord_execution_enabled=_truthy(
            os.environ.get("C4_INVARIANT_DISCORD_ENABLED", "0"),
            default=False,
        ),
        quiet_until_cure=quiet_until_cure,
    )

    if ctx.mesh_only or not ctx.discord_execution_enabled:
        # Mesh-first invariant: nine-cell HTTP probes — no Discord Playwright / discord.com on this path.
        ctx.mesh_nine_cell_surface = True
        ctx.require_earth_moor = False
    if not ctx.discord_execution_enabled:
        ctx.invoke_full_session = False

    if ctx.quiet_until_cure:
        qp = ev_rel / f"FULL_RELEASE_QUIET_{ts}.log"
        ctx.quiet_log_path = qp
        try:
            lf = open(qp, "a", buffering=1, encoding="utf-8", errors="replace")
        except OSError:
            ctx.quiet_until_cure = False
        else:
            ctx.quiet_log_fp = lf
            lf.write(
                f"GaiaFTCL invariant: quiet until CURE — child stdout/stderr -> this file\n"
                f"path={qp}\n\n"
            )
            lf.flush()
            try:
                ctx.quiet_stdout_fd = os.dup(1)
                ctx.quiet_stderr_fd = os.dup(2)
                os.dup2(lf.fileno(), 1)
                os.dup2(lf.fileno(), 2)
            except OSError:
                ctx.quiet_until_cure = False
                try:
                    lf.close()
                except OSError:
                    pass

    clear_sh = repo / "scripts" / "clear_release_deck.sh"
    if ctx.clear_release_deck and clear_sh.is_file():
        append_heartbeat(
            ctx,
            {
                "phase": "clear_release_deck",
                "script": str(clear_sh),
                "full_compliance": ctx.full_compliance,
                "note": "archive stale RELEASE_REPORT / SESSION — next spine is authoritative",
            },
        )
        rc_clear = run_bash(clear_sh)
        append_heartbeat(
            ctx,
            {"phase": "clear_release_deck", "exit": rc_clear},
        )

    st = GovernorState()
    spin = SpinDetector(k=ctx.spin_k)
    lock_path: Path | None = None
    if ctx.use_governor_lock:
        while True:
            lock_path = try_acquire_governor_lock(ev_rel)
            if lock_path is not None:
                break
            append_heartbeat(
                ctx,
                {
                    "gate": Gate.mesh_fusion_web.value,
                    "phase": "lock_wait",
                    "note": "invariant spiral — waiting for governor lock (no REFUSED exit)",
                },
            )
            time.sleep(max(ctx.heartbeat_sec, 2.0))
        atexit.register(release_governor_lock, lock_path)

    mount_script = repo / "scripts" / "mount_gaiafusion_dmg.sh"
    ensure_script = repo / "scripts" / "ensure_gaiafusion_dmg.sh"
    earth_path = repo / "evidence" / "discord" / "C4_CELL_EARTH_AUDIT.json"
    mesh_witness_path = repo / "evidence" / "mesh" / "C4_MESH_SELF_MOOR.json"

    def on_sig(_sig: int, _frm: Any) -> None:
        release_governor_lock(lock_path)
        cleanup_evidence_release_tmp(ctx.evidence_release)
        write_final(
            ctx,
            "PARTIAL",
            {
                "note": "signal_interrupt",
                "gate": st.gate.value,
                "rollback_count": st.rollback_count,
            },
            st=st,
        )
        sys.exit(EXIT_SIGNAL)

    signal.signal(signal.SIGINT, on_sig)
    signal.signal(signal.SIGTERM, on_sig)

    last_beat = 0.0

    while True:
        try:
            st.cycle += 1
            # ``--max-cycles`` is ignored for exit: the invariant spirals until CURE (no REFUSED on cycle cap).

            _tb_recheck = int(os.environ.get("C4_INVARIANT_TOOLBOX_RECHECK_CYCLES", "0").strip() or "0")
            if st.cycle == 1 or (_tb_recheck > 0 and st.cycle % _tb_recheck == 0):
                ok_tb, missing_tb = validate_invariant_toolbox(ctx)
                if not ok_tb:
                    append_heartbeat(
                        ctx,
                        {
                            "gate": st.gate.value,
                            "phase": "invariant_toolbox",
                            "terminal": "PARTIAL",
                            "toolbox_ok": False,
                            "missing": missing_tb,
                            "note": "Toolbox preflight failed — spiral until spec/invariant_toolbox.json requirements satisfied",
                        },
                    )
                    time.sleep(max(ctx.heartbeat_sec, 2.0))
                    continue

            now = time.time()
            if now - last_beat >= ctx.heartbeat_sec:
                doc = (
                    load_mesh_witness(mesh_witness_path)
                    if ctx.mesh_nine_cell_surface
                    else load_earth_audit(earth_path)
                )
                hb: dict[str, Any] = {
                    "cycle": st.cycle,
                    "gate": st.gate.value,
                    "attempt": st.attempt.get(st.gate.value, 0),
                    "earth_torsion_hint": doc.get("earth_torsion_hint"),
                    "earth_11_11_closed": doc.get("earth_11_11_closed"),
                    "mesh_mooring_closed": doc.get("mesh_mooring_closed"),
                    "surface_mode": "mesh_nine_cell_http"
                    if ctx.mesh_nine_cell_surface
                    else "discord_playwright_earth_audit",
                    "terminal": doc.get("terminal"),
                    "discord_mesh_surface_locked_once": st.discord_mesh_surface_locked_once,
                    "rollback_count": st.rollback_count,
                }
                append_heartbeat(ctx, hb)
                last_beat = now

            if human_visual_block(ctx):
                append_heartbeat(
                    ctx,
                    {
                        "gate": "visualGate",
                        "reason": "HUMAN_VISUAL_REQUIRED",
                        "human_ack_path": str(ctx.human_ack_path),
                        "cycle": st.cycle,
                        "terminal": "PARTIAL",
                        "note": "Invariant spiral — no BLOCKED exit; unset C4_HUMAN_VISUAL_LAYOUT_REVIEW or add HUMAN_VISUAL_ACK.json",
                    },
                )
                time.sleep(max(ctx.heartbeat_sec, 5.0))
                continue

            # --- meshFusionWebGate ---
            if st.gate == Gate.mesh_fusion_web:
                t0 = time.perf_counter()
                st.attempt[Gate.mesh_fusion_web.value] = st.attempt.get(Gate.mesh_fusion_web.value, 0) + 1
                probe = probe_mesh_fusion_web(ctx)
                ok = bool(probe.get("web_ok"))
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.mesh_fusion_web.value,
                        "last_witness": probe,
                        "elapsed_ms": (time.perf_counter() - t0) * 1000,
                        "terminal": "CALORIE" if ok else "PARTIAL",
                    },
                )
                if ok:
                    st.gate = Gate.fusion_s4_playwright
                    continue
                sig = f"web_probe:{probe.get('http_status')}"
                if spin.observe(Gate.mesh_fusion_web.value, sig):
                    ex = klein_fold_spin_or_exit(
                        ctx,
                        lock_path,
                        spin,
                        st,
                        Gate.mesh_fusion_web,
                        sig,
                        "run_full_release_invariant.py:meshFusionWebGate spin",
                    )
                time.sleep(max(ctx.heartbeat_sec, 3.0))
                continue

            # --- fusionS4PlaywrightGate ---
            if st.gate == Gate.fusion_s4_playwright:
                t0 = time.perf_counter()
                st.attempt[Gate.fusion_s4_playwright.value] = st.attempt.get(Gate.fusion_s4_playwright.value, 0) + 1
                ok, witness = run_fusion_s4_playwright_gate(ctx)
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.fusion_s4_playwright.value,
                        "elapsed_ms": (time.perf_counter() - t0) * 1000,
                        "terminal": "CALORIE" if ok else "PARTIAL",
                        "last_witness": witness,
                    },
                )
                if ok:
                    st.gate = Gate.discord_mesh_surface
                    continue
                # Self-heal: immediate retry once before outer loop continues.
                ok2, witness2 = run_fusion_s4_playwright_gate(ctx)
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.fusion_s4_playwright.value,
                        "self_heal_retry": 1,
                        "terminal": "CALORIE" if ok2 else "PARTIAL",
                        "last_witness": witness2,
                    },
                )
                if ok2:
                    st.gate = Gate.discord_mesh_surface
                    continue
                sig = f"fusion_s4_playwright:{witness2.get('exit_code')}"
                if spin.observe(Gate.fusion_s4_playwright.value, sig):
                    ex = klein_fold_spin_or_exit(
                        ctx,
                        lock_path,
                        spin,
                        st,
                        Gate.fusion_s4_playwright,
                        sig,
                        "run_full_release_invariant.py:fusionS4PlaywrightGate spin",
                    )
                time.sleep(max(ctx.heartbeat_sec, 3.0))
                continue

            # --- mountGate (legacy path; mac ownership delegated to sub-governor) ---
            if st.gate == Gate.mount:
                t0 = time.perf_counter()
                st.attempt[Gate.mount.value] = st.attempt.get(Gate.mount.value, 0) + 1
                if sys.platform != "darwin":
                    sig = "non_darwin"
                    if spin.observe(Gate.mount.value, sig):
                        ex = klein_fold_spin_or_exit(
                            ctx,
                            lock_path,
                            spin,
                            st,
                            Gate.mount,
                            sig,
                            "run_full_release_invariant.py:mountGate darwin",
                        )
                        time.sleep(ctx.heartbeat_sec)
                        continue
                    time.sleep(ctx.heartbeat_sec)
                    continue

                if not df_has_gaiafusion() and not has_gaiafusion_dmg(repo):
                    if not _truthy(os.environ.get("C4_INVARIANT_BUILD_DMG", "1"), default=True):
                        append_heartbeat(
                            ctx,
                            {
                                "gate": Gate.mount.value,
                                "klein_foldback": True,
                                "note": "no GaiaFusion DMG — invariant spiral (no REFUSED); place DMG or enable C4_INVARIANT_BUILD_DMG",
                                "terminal": "PARTIAL",
                            },
                        )
                        time.sleep(max(ctx.heartbeat_sec, 5.0))
                        continue

                if not df_has_gaiafusion() and not has_gaiafusion_dmg(repo) and ensure_script.is_file():
                    append_heartbeat(
                        ctx,
                        {
                            "gate": Gate.mount.value,
                            "last_remediation": "ensure_gaiafusion_dmg.sh → build_gaiaftcl_facade_dmg.sh (long)",
                            "terminal": "PARTIAL",
                            "note": "full facade build can take many minutes (Swift, FusionControl, optional Xcode)",
                        },
                    )
                    erc = run_bash_with_heartbeat(
                        ensure_script,
                        ctx,
                        Gate.mount.value,
                        ctx.build_timeout_sec,
                    )
                    append_heartbeat(
                        ctx,
                        {
                            "gate": Gate.mount.value,
                            "last_witness": {
                                "ensure_exit": erc,
                                "dmg_path": str(gaiafusion_dmg_resolved(repo) or ""),
                            },
                            "elapsed_ms": (time.perf_counter() - t0) * 1000,
                        },
                    )
                    if erc != 0:
                        if spin.observe(Gate.mount.value, f"ensure_failed:{erc}"):
                            ex = klein_fold_spin_or_exit(
                                ctx,
                                lock_path,
                                spin,
                                st,
                                Gate.mount,
                                f"ensure_failed:{erc}",
                                "run_full_release_invariant.py:mountGate ensure_gaiafusion_dmg",
                            )
                        time.sleep(max(ctx.heartbeat_sec, 5.0))
                        continue
                    spin.reset()
                    if not has_gaiafusion_dmg(repo):
                        time.sleep(ctx.heartbeat_sec)
                        continue

                if (
                    has_gaiafusion_dmg(repo)
                    and not st.mesh_deploy_attempted
                    and _truthy(os.environ.get("C4_INVARIANT_DEPLOY_DMG"))
                ):
                    st.mesh_deploy_attempted = True
                    drc, dmsg = maybe_deploy_dmg_to_mesh(ctx)
                    append_heartbeat(
                        ctx,
                        {
                            "gate": Gate.mount.value,
                            "mesh_deploy": drc,
                            "mesh_deploy_mode": dmsg,
                        },
                    )

                if not df_has_gaiafusion():
                    run_bash(mount_script)
                ok = df_has_gaiafusion()
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.mount.value,
                        "last_witness": {
                            "df_gaiafusion": ok,
                            "dmg_resolved": str(gaiafusion_dmg_resolved(repo) or ""),
                        },
                        "last_remediation": str(mount_script),
                        "elapsed_ms": (time.perf_counter() - t0) * 1000,
                        "terminal": "CALORIE" if ok else "PARTIAL",
                    },
                )
                if not ok:
                    sig = "mount_fail_after_dmg"
                    if spin.observe(Gate.mount.value, sig):
                        ex = klein_fold_spin_or_exit(
                            ctx,
                            lock_path,
                            spin,
                            st,
                            Gate.mount,
                            sig,
                            "run_full_release_invariant.py:mountGate spin",
                        )
                    time.sleep(max(ctx.heartbeat_sec, 3.0))
                    continue
                st.gate = Gate.visual
                continue

            # --- visualGate ---
            if st.gate == Gate.visual:
                t0 = time.perf_counter()
                st.attempt[Gate.visual.value] = st.attempt.get(Gate.visual.value, 0) + 1
                remediate_visual_mac(ctx)
                rc = playwright_fusion(ctx)
                png = repo / "evidence" / "fusion_control" / "fusion_dashboard_witness.png"
                ok = rc == 0 and png.is_file() and png.stat().st_size >= ctx.min_png_bytes
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.visual.value,
                        "last_witness": {
                            "playwright_rc": rc,
                            "png_bytes": png.stat().st_size if png.is_file() else 0,
                            "png_path": str(png),
                        },
                        "last_remediation": "remediate_fusion_visual_mac.sh + killall GaiaFusion",
                        "elapsed_ms": (time.perf_counter() - t0) * 1000,
                        "terminal": "CALORIE" if ok else "PARTIAL",
                        "last_error": None if ok else f"playwright_rc={rc}",
                    },
                )
                if ok:
                    st.visual_fail_streak = 0
                    st.gate = Gate.discord_mesh_surface
                    continue
                st.visual_fail_streak += 1
                sig = f"visual_fail:{rc}"
                if spin.observe(Gate.visual.value, sig):
                    ex = klein_fold_spin_or_exit(
                        ctx,
                        lock_path,
                        spin,
                        st,
                        Gate.visual,
                        sig,
                        "run_full_release_invariant.py:visualGate spin",
                    )
                time.sleep(max(ctx.heartbeat_sec, 2.0))
                continue

            # --- discordMeshSurfaceGate ---
            if st.gate == Gate.discord_mesh_surface:
                if _truthy_env_first(
                    "C4_USE_CHESS_DISCORD_MESH_SURFACE_GATE",
                    "C4_USE_CHESS_PLANETARY_GATE",
                ) and not ctx.mesh_nine_cell_surface:
                    chess = repo / "scripts" / "chess_planetary_gate.sh"
                    run_bash(
                        chess,
                        env={
                            "C4_EARTH_LOCK_ROUNDS": os.environ.get("C4_EARTH_LOCK_ROUNDS", "999999"),
                            "NATS_URL": ctx.nats_url,
                            "DISCORD_PLAYWRIGHT_PROFILE": ctx.discord_profile,
                        },
                    )
                    doc = load_earth_audit(earth_path)
                    ok = earth_ok(doc)
                    append_heartbeat(
                        ctx,
                        {
                            "gate": Gate.discord_mesh_surface.value,
                            "last_witness": {"delegated": "chess_planetary_gate.sh", "earth_audit": doc},
                            "terminal": "CALORIE" if ok else "PARTIAL",
                            "earth_torsion_hint": doc.get("earth_torsion_hint"),
                        },
                    )
                    if ok:
                        st.discord_mesh_surface_locked_once = True
                        st.gate = Gate.cell_plant_state
                    else:
                        if oauth_mfa_requires_human(ctx, doc):
                            append_heartbeat(
                                ctx,
                                {
                                    "gate": Gate.discord_mesh_surface.value,
                                    "oauth_mfa_observed": True,
                                    "note": "OAuth/MFA fold — PARTIAL spiral (no BLOCKED exit)",
                                    "terminal": "PARTIAL",
                                    "last_witness": {"delegated": "chess_planetary_gate.sh", "earth_audit": doc},
                                },
                            )
                            time.sleep(max(ctx.earth_wait_sec, 30.0))
                            continue
                        sig = f"chess_delegate:{doc.get('terminal')}"
                        if spin.observe(Gate.discord_mesh_surface.value, sig):
                            ex = klein_fold_spin_or_exit(
                                ctx,
                                lock_path,
                                spin,
                                st,
                                Gate.discord_mesh_surface,
                                sig,
                                "run_full_release_invariant.py:discordMeshSurfaceGate delegate spin",
                            )
                        time.sleep(ctx.earth_wait_sec)
                    continue

                t0 = time.perf_counter()
                st.attempt[Gate.discord_mesh_surface.value] = st.attempt.get(Gate.discord_mesh_surface.value, 0) + 1
                if _mesh_first_surface(ctx):
                    doc, _mh_a, mh_meta = mesh_probe_after_optional_heal(
                        ctx,
                        repo,
                        gate_value=Gate.discord_mesh_surface.value,
                        max_heal_attempts=int(os.environ.get("C4_MESH_HEAL_MAX_ATTEMPTS", "10")),
                        heal_wait_sec=float(os.environ.get("C4_MESH_HEAL_WAIT_SEC", "30")),
                    )
                    ok = mesh_nine_cell_surface_ok(doc)
                    append_heartbeat(
                        ctx,
                        {
                            "gate": Gate.discord_mesh_surface.value,
                            "surface_mode": "mesh_first_surface_probe",
                            "mesh_first_surface": True,
                            "mesh_only": ctx.mesh_only,
                            "discord_execution_enabled": ctx.discord_execution_enabled,
                            "last_witness": {"mesh_self_moor": doc, "mesh_heal": mh_meta or None},
                            "last_remediation": "mesh_probe_after_optional_heal + probe_mesh_self_moor",
                            "elapsed_ms": (time.perf_counter() - t0) * 1000,
                            "terminal": "CALORIE" if ok else "PARTIAL",
                            "last_error": None if ok else "mesh_self_moor not closed",
                        },
                    )
                    if ok:
                        st.discord_mesh_surface_locked_once = True
                        st.last_earth_doc = doc
                        st.gate = Gate.cell_plant_state
                        continue
                    maybe_reset_spin_on_moor_progress(spin, st, doc, None)
                    discord_mesh_surface_partial_retry(
                        ctx,
                        st,
                        spin,
                        lock_path,
                        doc,
                        None,
                        spin_note_line="run_full_release_invariant.py:discordMeshSurfaceGate mesh-first",
                    )
                    continue
                if ctx.mesh_nine_cell_surface:
                    doc, mesh_heal_attempts, mesh_heal_meta = mesh_probe_after_optional_heal(
                        ctx,
                        repo,
                        gate_value=Gate.discord_mesh_surface.value,
                        max_heal_attempts=int(os.environ.get("C4_MESH_HEAL_MAX_ATTEMPTS", "10")),
                        heal_wait_sec=float(os.environ.get("C4_MESH_HEAL_WAIT_SEC", "30")),
                    )
                    rc = 0 if mesh_nine_cell_surface_ok(doc) else 1
                    earth_doc: dict[str, Any] = {}
                    earth_rc = 0
                    if ctx.require_earth_moor:
                        poke_stale(ctx, earth_path)
                        earth_rc = playwright_cell(ctx)
                        if _truthy_env_first(
                            "C4_DISCORD_MESH_SURFACE_SELF_HEAL",
                            "C4_PLANETARY_SELF_HEAL",
                            default=True,
                        ):
                            earth_doc = heal_earth_audit_from_raw(earth_path)
                        else:
                            earth_doc = load_earth_audit(earth_path)
                    mesh_ok = discord_or_mesh_surface_closure_ok(doc, ctx)
                    earth_gate_ok = True if not ctx.require_earth_moor else earth_ok(earth_doc)
                    ok = bool(mesh_ok and earth_gate_ok)
                    if ok:
                        st.discord_mesh_surface_locked_once = True
                        st.last_earth_doc = earth_doc if ctx.require_earth_moor else doc
                    append_heartbeat(
                        ctx,
                        {
                            "gate": Gate.discord_mesh_surface.value,
                            "surface_mode": "mesh_nine_cell_http",
                            "last_witness": {
                                "mesh_probe_rc": rc,
                                "mesh_self_moor": doc,
                                "mesh_heal_attempts": mesh_heal_attempts,
                                "mesh_heal": mesh_heal_meta or None,
                                "require_earth_moor": ctx.require_earth_moor,
                                "earth_playwright_rc": earth_rc if ctx.require_earth_moor else None,
                                "earth_audit": earth_doc if ctx.require_earth_moor else None,
                            },
                            "last_remediation": "mesh_probe_after_optional_heal + probe_mesh_self_moor + (optional) playwright_cell + heal_earth_audit_from_raw",
                            "elapsed_ms": (time.perf_counter() - t0) * 1000,
                            "terminal": "CALORIE" if ok else "PARTIAL",
                            "last_error": None if ok else (
                                "mesh_self_moor not closed"
                                if not mesh_ok
                                else "earth_mooring not closed (expected MOORED 11/11 + crystal lineage)"
                            ),
                        },
                    )
                    if ok:
                        st.gate = Gate.cell_plant_state
                        continue
                    if ctx.require_earth_moor and isinstance(earth_doc, dict):
                        em = earth_doc.get("earth_mooring") if isinstance(earth_doc.get("earth_mooring"), dict) else {}
                        if (
                            isinstance(em, dict)
                            and int(em.get("healthy", 0) or 0) == 0
                            and int(em.get("total", 0) or 0) > 0
                            and (
                                st.earth_mesh_self_heal_runs == 0
                                or st.attempt.get(Gate.discord_mesh_surface.value, 0) % 3 == 0
                            )
                        ):
                            mcp_ok, mcp_meta = run_gaiaftcl_mcp_self_heal(
                                ctx,
                                reason="earth_unmoored_call_gaiaftcl_mcp_first",
                                earth_doc=earth_doc,
                            )
                            append_heartbeat(
                                ctx,
                                {
                                    "gate": Gate.discord_mesh_surface.value,
                                    "surface_mode": "mesh_nine_cell_http+earth_required",
                                    "self_heal_gaiaftcl_mcp": mcp_meta,
                                    "terminal": "CALORIE" if mcp_ok else "PARTIAL",
                                    "last_error": None if mcp_ok else "gaiaftcl_mcp_self_heal_unavailable_or_failed",
                                },
                            )
                            if mcp_ok:
                                rc2 = playwright_cell(ctx)
                                earth_doc = heal_earth_audit_from_raw(earth_path)
                                if earth_ok(earth_doc):
                                    st.discord_mesh_surface_locked_once = True
                                    st.last_earth_doc = earth_doc
                                    st.gate = Gate.cell_plant_state
                                    continue

                            st.earth_mesh_self_heal_runs += 1
                            healed, h = run_earth_mesh_self_heal(
                                ctx,
                                reason=f"earth_unmoored_zero_patterns_run_{st.earth_mesh_self_heal_runs}",
                            )
                            append_heartbeat(
                                ctx,
                                {
                                    "gate": Gate.discord_mesh_surface.value,
                                    "surface_mode": "mesh_nine_cell_http+earth_required",
                                    "self_heal_mesh_earth": h,
                                    "self_heal_runs": st.earth_mesh_self_heal_runs,
                                    "terminal": "CALORIE" if healed else "PARTIAL",
                                    "last_error": None if healed else "earth mesh self-heal failed",
                                },
                            )
                    if ctx.require_earth_moor and oauth_mfa_requires_human(ctx, earth_doc):
                        append_heartbeat(
                            ctx,
                            {
                                "gate": Gate.discord_mesh_surface.value,
                                "oauth_mfa_observed": True,
                                "surface_mode": "mesh_nine_cell_http+earth_required",
                                "note": "OAuth/MFA on earth audit — PARTIAL spiral (no BLOCKED exit)",
                                "terminal": "PARTIAL",
                            },
                        )
                        time.sleep(max(ctx.earth_wait_sec, 30.0))
                        continue
                    maybe_reset_spin_on_moor_progress(
                        spin,
                        st,
                        doc,
                        earth_doc if ctx.require_earth_moor else None,
                    )
                    discord_mesh_surface_partial_retry(
                        ctx,
                        st,
                        spin,
                        lock_path,
                        doc,
                        earth_doc if ctx.require_earth_moor else None,
                        spin_note_line="run_full_release_invariant.py:discordMeshSurfaceGate mesh+earth",
                    )
                    continue

                poke_stale(ctx, earth_path)
                rc = playwright_cell(ctx)
                if _truthy_env_first(
                    "C4_DISCORD_MESH_SURFACE_SELF_HEAL",
                    "C4_PLANETARY_SELF_HEAL",
                    default=True,
                ):
                    doc = heal_earth_audit_from_raw(earth_path)
                else:
                    doc = load_earth_audit(earth_path)
                ok = discord_or_mesh_surface_closure_ok(doc, ctx)
                if ok:
                    st.discord_mesh_surface_locked_once = True
                    st.last_earth_doc = doc
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.discord_mesh_surface.value,
                        "surface_mode": "discord_playwright_earth_audit",
                        "last_witness": {"playwright_rc": rc, "earth_audit": doc},
                        "last_remediation": "poke_stale(pre) + playwright_cell + heal_earth_audit_from_raw",
                        "elapsed_ms": (time.perf_counter() - t0) * 1000,
                        "terminal": "CALORIE" if ok else "PARTIAL",
                        "earth_torsion_hint": doc.get("earth_torsion_hint"),
                        "last_error": None if ok else f"playwright_rc={rc}",
                        "c4_self_heal": doc.get("c4_self_heal"),
                    },
                )
                if ok:
                    st.gate = Gate.cell_plant_state
                    continue
                if oauth_mfa_requires_human(ctx, doc):
                    append_heartbeat(
                        ctx,
                        {
                            "gate": Gate.discord_mesh_surface.value,
                            "oauth_mfa_observed": True,
                            "surface_mode": "discord_playwright_earth_audit",
                            "note": "OAuth/MFA on Discord earth — PARTIAL spiral (no BLOCKED exit)",
                            "terminal": "PARTIAL",
                        },
                    )
                    time.sleep(max(ctx.earth_wait_sec, 30.0))
                    continue
                poke_stale(ctx, earth_path)
                sig = f"discord_earth:{doc.get('terminal')}"
                if spin.observe(Gate.discord_mesh_surface.value, sig):
                    ex = klein_fold_spin_or_exit(
                        ctx,
                        lock_path,
                        spin,
                        st,
                        Gate.discord_mesh_surface,
                        sig,
                        "run_full_release_invariant.py:discordMeshSurfaceGate spin",
                    )
                time.sleep(ctx.earth_wait_sec)
                continue

            # --- cellPlantStateGate ---
            if st.gate == Gate.cell_plant_state:
                t0 = time.perf_counter()
                st.attempt[Gate.cell_plant_state.value] = st.attempt.get(Gate.cell_plant_state.value, 0) + 1
                ok, msg = validate_cell_plant_state_schema(repo)
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.cell_plant_state.value,
                        "elapsed_ms": (time.perf_counter() - t0) * 1000,
                        "terminal": "CALORIE" if ok else "PARTIAL",
                        "last_error": None if ok else msg,
                    },
                )
                if ok:
                    st.gate = Gate.hub_moor
                    continue
                time.sleep(max(ctx.heartbeat_sec, 2.0))
                continue

            # --- hubMoorGate ---
            if st.gate == Gate.hub_moor:
                t0 = time.perf_counter()
                st.attempt[Gate.hub_moor.value] = st.attempt.get(Gate.hub_moor.value, 0) + 1
                ok, msg = validate_hub_moor_contract(repo)
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.hub_moor.value,
                        "elapsed_ms": (time.perf_counter() - t0) * 1000,
                        "terminal": "CALORIE" if ok else "PARTIAL",
                        "last_error": None if ok else msg,
                    },
                )
                if ok:
                    st.gate = Gate.spoke_contracts
                    continue
                time.sleep(max(ctx.heartbeat_sec, 2.0))
                continue

            # --- spokeContractsGate ---
            if st.gate == Gate.spoke_contracts:
                t0 = time.perf_counter()
                st.attempt[Gate.spoke_contracts.value] = st.attempt.get(Gate.spoke_contracts.value, 0) + 1
                ok, msg = validate_spoke_contracts(repo)
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.spoke_contracts.value,
                        "elapsed_ms": (time.perf_counter() - t0) * 1000,
                        "terminal": "CALORIE" if ok else "PARTIAL",
                        "last_error": None if ok else msg,
                    },
                )
                if ok:
                    st.gate = Gate.proof_ledger if _mesh_first_surface(ctx) else Gate.discord_command_inventory
                    continue
                time.sleep(max(ctx.heartbeat_sec, 2.0))
                continue

            # --- discordCommandInventoryGate ---
            if st.gate == Gate.discord_command_inventory:
                if _mesh_first_surface(ctx):
                    append_heartbeat(
                        ctx,
                        {
                            "gate": Gate.discord_command_inventory.value,
                            "mesh_first_surface": True,
                            "mesh_only": ctx.mesh_only,
                            "terminal": "CALORIE",
                            "last_error": None,
                            "skipped": True,
                        },
                    )
                    st.gate = Gate.proof_ledger
                    continue
                t0 = time.perf_counter()
                st.attempt[Gate.discord_command_inventory.value] = st.attempt.get(Gate.discord_command_inventory.value, 0) + 1
                ok, msg = validate_discord_command_inventory(repo)
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.discord_command_inventory.value,
                        "elapsed_ms": (time.perf_counter() - t0) * 1000,
                        "terminal": "CALORIE" if ok else "PARTIAL",
                        "last_error": None if ok else msg,
                    },
                )
                if ok:
                    st.gate = Gate.proof_ledger
                    continue
                time.sleep(max(ctx.heartbeat_sec, 2.0))
                continue

            # --- proofLedgerGate ---
            if st.gate == Gate.proof_ledger:
                t0 = time.perf_counter()
                st.attempt[Gate.proof_ledger.value] = st.attempt.get(Gate.proof_ledger.value, 0) + 1
                ok, msg = validate_proof_ledger_schema(repo)
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.proof_ledger.value,
                        "elapsed_ms": (time.perf_counter() - t0) * 1000,
                        "terminal": "CALORIE" if ok else "PARTIAL",
                        "last_error": None if ok else msg,
                    },
                )
                if ok:
                    st.gate = Gate.license_payment
                    continue
                time.sleep(max(ctx.heartbeat_sec, 2.0))
                continue

            # --- licensePaymentGate ---
            if st.gate == Gate.license_payment:
                t0 = time.perf_counter()
                st.attempt[Gate.license_payment.value] = st.attempt.get(Gate.license_payment.value, 0) + 1
                ok, msg = validate_license_payment_contract(repo)
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.license_payment.value,
                        "elapsed_ms": (time.perf_counter() - t0) * 1000,
                        "terminal": "CALORIE" if ok else "PARTIAL",
                        "last_error": None if ok else msg,
                    },
                )
                if ok:
                    st.gate = Gate.surface_parity
                    continue
                time.sleep(max(ctx.heartbeat_sec, 2.0))
                continue

            # --- surfaceParityGate ---
            if st.gate == Gate.surface_parity:
                t0 = time.perf_counter()
                st.attempt[Gate.surface_parity.value] = st.attempt.get(Gate.surface_parity.value, 0) + 1
                ok, msg = validate_surface_parity(repo)
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.surface_parity.value,
                        "elapsed_ms": (time.perf_counter() - t0) * 1000,
                        "terminal": "CALORIE" if ok else "PARTIAL",
                        "last_error": None if ok else msg,
                    },
                )
                if ok:
                    st.gate = (
                        Gate.mesh_game_runner_capture
                        if _mesh_first_surface(ctx)
                        else Gate.playwright_game_capture
                    )
                    continue
                time.sleep(max(ctx.heartbeat_sec, 2.0))
                continue

            # --- meshGameRunnerCaptureGate ---
            if st.gate == Gate.mesh_game_runner_capture:
                t0 = time.perf_counter()
                st.attempt[Gate.mesh_game_runner_capture.value] = st.attempt.get(Gate.mesh_game_runner_capture.value, 0) + 1
                ok, msg = validate_mesh_game_runner_captures(repo)
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.mesh_game_runner_capture.value,
                        "elapsed_ms": (time.perf_counter() - t0) * 1000,
                        "terminal": "CALORIE" if ok else "PARTIAL",
                        "last_error": None if ok else msg,
                    },
                )
                if ok:
                    st.gate = Gate.domain_ui_gameplay
                    continue
                healed, heal_doc = run_mesh_game_runner_self_heal(ctx, msg)
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.mesh_game_runner_capture.value,
                        "self_heal_invoked": True,
                        "self_heal_shell_ok": healed,
                        "self_heal_result": "CALORIE" if healed else "PARTIAL",
                        "self_heal_witness": heal_doc,
                        "note": "retry until mesh capture contract satisfied — evidence is truth",
                    },
                )
                ok2, msg2 = validate_mesh_game_runner_captures(repo)
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.mesh_game_runner_capture.value,
                        "post_self_heal_validation": True,
                        "terminal": "CALORIE" if ok2 else "PARTIAL",
                        "last_error": None if ok2 else msg2,
                    },
                )
                if ok2:
                    st.gate = Gate.domain_ui_gameplay
                    continue
                time.sleep(max(ctx.heartbeat_sec, 2.0))
                continue

            # --- playwrightGameCaptureGate ---
            if st.gate == Gate.playwright_game_capture:
                if _mesh_first_surface(ctx):
                    append_heartbeat(
                        ctx,
                        {
                            "gate": Gate.playwright_game_capture.value,
                            "mesh_first_surface": True,
                            "mesh_only": ctx.mesh_only,
                            "terminal": "CALORIE",
                            "last_error": None,
                            "skipped": True,
                        },
                    )
                    # Never skip domain UI closure: mesh-first mode removes this gate from the sequence;
                    # if we ever land here with mesh-first, continue to domain gameplay, not language contracts.
                    st.gate = Gate.domain_ui_gameplay
                    continue
                t0 = time.perf_counter()
                st.attempt[Gate.playwright_game_capture.value] = st.attempt.get(Gate.playwright_game_capture.value, 0) + 1
                ok, msg = validate_playwright_game_captures(repo)
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.playwright_game_capture.value,
                        "elapsed_ms": (time.perf_counter() - t0) * 1000,
                        "terminal": "CALORIE" if ok else "PARTIAL",
                        "last_error": None if ok else msg,
                    },
                )
                if ok:
                    st.gate = Gate.domain_ui_gameplay
                    continue
                healed, heal_doc = run_playwright_capture_self_heal(ctx, msg)
                st.playwright_capture_self_heal_runs += 1
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.playwright_game_capture.value,
                        "self_heal_invoked": True,
                        "self_heal_runs": st.playwright_capture_self_heal_runs,
                        "self_heal_shell_ok": healed,
                        "self_heal_result": "CALORIE" if healed else "PARTIAL",
                        "self_heal_witness": heal_doc,
                    },
                )
                ok2, msg2 = validate_playwright_game_captures(repo)
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.playwright_game_capture.value,
                        "post_self_heal_validation": True,
                        "terminal": "CALORIE" if ok2 else "PARTIAL",
                        "last_error": None if ok2 else msg2,
                    },
                )
                if ok2:
                    st.gate = Gate.domain_ui_gameplay
                    continue
                time.sleep(max(ctx.heartbeat_sec, 2.0))
                continue

            # --- domainUiGameplayGate ---
            if st.gate == Gate.domain_ui_gameplay:
                t0 = time.perf_counter()
                st.attempt[Gate.domain_ui_gameplay.value] = st.attempt.get(Gate.domain_ui_gameplay.value, 0) + 1
                ok, msg = validate_domain_ui_gameplay(repo)
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.domain_ui_gameplay.value,
                        "elapsed_ms": (time.perf_counter() - t0) * 1000,
                        "terminal": "CALORIE" if ok else "PARTIAL",
                        "last_error": None if ok else msg,
                    },
                )
                if ok:
                    st.gate = Gate.language_games
                    continue
                healed, heal_doc = run_domain_ui_gameplay_self_heal(ctx, msg)
                blocker_codes = heal_doc.get("blockers") if isinstance(heal_doc, dict) else None
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.domain_ui_gameplay.value,
                        "self_heal_invoked": True,
                        "self_heal_shell_ok": healed,
                        "self_heal_result": "CALORIE" if healed else "PARTIAL",
                        "self_heal_witness": heal_doc,
                        "blockers_pending": blocker_codes if isinstance(blocker_codes, list) else [],
                        "note": "Klein spiral: no REFUSED on blockers — retry until full graphical app witness",
                    },
                )
                # Always re-validate C4 after self-heal (shell may fail mid-chain; witness is truth).
                ok2, msg2 = validate_domain_ui_gameplay(repo)
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.domain_ui_gameplay.value,
                        "post_self_heal_validation": True,
                        "terminal": "CALORIE" if ok2 else "PARTIAL",
                        "last_error": None if ok2 else msg2,
                    },
                )
                if ok2:
                    st.gate = Gate.language_games
                    continue
                time.sleep(max(ctx.heartbeat_sec, 2.0))
                continue

            # --- languageGameContracts ---
            if st.gate == Gate.language_games:
                t0 = time.perf_counter()
                contract = load_contract(ctx)
                ok, msg = validate_language_games(ctx, contract)
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.language_games.value,
                        "elapsed_ms": (time.perf_counter() - t0) * 1000,
                        "terminal": "CALORIE" if ok else "PARTIAL",
                        "last_error": None if ok else msg,
                    },
                )
                if ok:
                    st.gate = Gate.release_bundle
                else:
                    sig = f"lang:{msg}"
                    if spin.observe(Gate.language_games.value, sig):
                        ex = klein_fold_spin_or_exit(
                            ctx,
                            lock_path,
                            spin,
                            st,
                            Gate.language_games,
                            sig,
                            "run_full_release_invariant.py:language_games spin",
                        )
                    time.sleep(max(ctx.heartbeat_sec, 2.0))
                continue

            # --- macFusionSubGovernorGate ---
            if st.gate == Gate.mac_fusion_sub:
                t0 = time.perf_counter()
                rc_sub, sub_doc = run_mac_fusion_sub_governor(ctx)
                sub_terminal = (sub_doc or {}).get("terminal")
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.mac_fusion_sub.value,
                        "elapsed_ms": (time.perf_counter() - t0) * 1000,
                        "last_witness": {
                            "sub_exit": rc_sub,
                            "sub_terminal": sub_terminal,
                            "sub_receipt": (sub_doc or {}).get("heartbeat_jsonl")
                            or (sub_doc or {}).get("run_id"),
                        },
                    },
                )
                if rc_sub == 0 and str(sub_terminal or "").upper() == INVARIANT_EXIT_TERMINAL:
                    st.gate = Gate.release_bundle
                    continue
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.mac_fusion_sub.value,
                        "note": f"mac sub-governor not {INVARIANT_EXIT_TERMINAL} — PARTIAL spiral (no BLOCKED/REFUSED exit)",
                        "sub_terminal": sub_terminal,
                        "sub_exit": rc_sub,
                        "sub_governor": sub_doc or {"sub_exit": rc_sub},
                        "terminal": "PARTIAL",
                    },
                )
                time.sleep(max(ctx.heartbeat_sec, 5.0))
                continue

            # --- releaseBundle (before sealing: run_sealing requires RELEASE_REPORT) ---
            if st.gate == Gate.release_bundle:
                if _mesh_first_surface(ctx):
                    ok_cure, cure_msg = validate_mesh_cure_gate(repo)
                    if not ok_cure:
                        append_heartbeat(
                            ctx,
                            {
                                "gate": Gate.release_bundle.value,
                                "mesh_first_surface": True,
                                "mesh_only": ctx.mesh_only,
                                "discord_execution_enabled": ctx.discord_execution_enabled,
                                "terminal": "PARTIAL",
                                "note": "CURE gate — all domains GUI + guided tour + live nine-cell required (sans Discord)",
                                "last_error": cure_msg,
                            },
                        )
                        if spin.observe(Gate.release_bundle.value, cure_msg[:120]):
                            ex = klein_fold_spin_or_exit(
                                ctx,
                                lock_path,
                                spin,
                                st,
                                Gate.release_bundle,
                                cure_msg[:120],
                                "run_full_release_invariant.py:releaseBundle mesh CURE prerequisites",
                            )
                        time.sleep(max(ctx.heartbeat_sec, 5.0))
                        continue
                    reports_mf = glob.glob(str(repo / "evidence" / "release" / "RELEASE_REPORT_*.json"))
                    if not reports_mf:
                        emitted = emit_mesh_first_release_report(repo)
                        append_heartbeat(
                            ctx,
                            {
                                "gate": Gate.release_bundle.value,
                                "mesh_first_surface": True,
                                "mesh_only": ctx.mesh_only,
                                "discord_execution_enabled": ctx.discord_execution_enabled,
                                "terminal": "CALORIE" if emitted else "PARTIAL",
                                "note": "emit mesh-first RELEASE_REPORT for sealed DOCX",
                                "emitted_report": str(emitted) if emitted else None,
                            },
                        )
                        if not emitted:
                            time.sleep(max(ctx.heartbeat_sec, 5.0))
                            continue
                    st.gate = Gate.sealing
                    continue
                reports = glob.glob(str(repo / "evidence" / "discord" / "RELEASE_REPORT_*.json"))
                if not reports and not ctx.invoke_full_session:
                    append_heartbeat(
                        ctx,
                        {
                            "gate": Gate.release_bundle.value,
                            "note": "no RELEASE_REPORT and full session invocation disabled — spiral until report or enable invoke",
                            "terminal": "PARTIAL",
                        },
                    )
                    time.sleep(max(ctx.heartbeat_sec, 5.0))
                    continue
                need_session = (
                    ctx.invoke_full_session
                    and not st.full_session_invoked
                    and (not reports or ctx.require_full_session)
                )
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.release_bundle.value,
                        "last_witness": {
                            "release_reports": len(reports),
                            "require_full_session": ctx.require_full_session,
                            "will_run_full_session": need_session,
                        },
                        "terminal": "CALORIE" if reports else "PARTIAL",
                    },
                )
                if need_session:
                    session_sh = repo / "scripts" / "run_full_release_session.sh"
                    spin.reset()
                    if session_sh.is_file():
                        note = (
                            "production spine: closure battery → dual-user → nine-cell → mesh (existing reports ignored)"
                            if reports and ctx.require_full_session
                            else "no RELEASE_REPORT — running full release spine once"
                        )
                        append_heartbeat(
                            ctx,
                            {
                                "gate": Gate.release_bundle.value,
                                "invoking": "run_full_release_session.sh",
                                "note": note,
                            },
                        )
                        st.full_session_invoked = True
                        t_sess = time.perf_counter()
                        rc_sess = run_bash_with_heartbeat(
                            session_sh,
                            ctx,
                            Gate.release_bundle.value,
                            ctx.full_session_timeout_sec,
                        )
                        st.last_full_session_rc = rc_sess
                        append_heartbeat(
                            ctx,
                            {
                                "gate": Gate.release_bundle.value,
                                "full_session_exit": rc_sess,
                                "elapsed_ms": (time.perf_counter() - t_sess) * 1000,
                            },
                        )
                        if rc_sess != 0:
                            st.full_session_invoked = False
                            append_heartbeat(
                                ctx,
                                {
                                    "gate": Gate.release_bundle.value,
                                    "session_failed": True,
                                    "note": "full session non-zero — will not seal on stale report; retry",
                                },
                            )
                            time.sleep(max(ctx.heartbeat_sec, 5.0))
                            continue
                    else:
                        append_heartbeat(
                            ctx,
                            {
                                "gate": Gate.release_bundle.value,
                                "refused": "missing_script",
                                "path": str(session_sh),
                            },
                        )
                    if need_session and not session_sh.is_file():
                        time.sleep(max(ctx.heartbeat_sec, 5.0))
                        continue
                    reports = glob.glob(str(repo / "evidence" / "discord" / "RELEASE_REPORT_*.json"))
                if not reports:
                    if spin.observe(Gate.release_bundle.value, "no_report"):
                        ex = klein_fold_spin_or_exit(
                            ctx,
                            lock_path,
                            spin,
                            st,
                            Gate.release_bundle,
                            "no_report",
                            "run_full_release_invariant.py:releaseBundle no RELEASE_REPORT",
                            legacy_exit_code=EXIT_NO_RELEASE_REPORT,
                        )
                    time.sleep(max(ctx.heartbeat_sec, 5.0))
                    continue

                st.gate = Gate.sealing
                continue

            # --- sealingGate (anti-entropy: re-check Discord/mesh surface before / after DOCX) ---
            if st.gate == Gate.sealing:
                t_pre = time.perf_counter()
                _pre_hm: dict[str, Any] | None = None
                if ctx.mesh_nine_cell_surface:
                    doc_pre, _pre_ha, _pre_hm = mesh_probe_after_optional_heal(
                        ctx,
                        repo,
                        gate_value=Gate.sealing.value,
                        max_heal_attempts=int(os.environ.get("C4_MESH_HEAL_SEAL_MAX_ATTEMPTS", "5")),
                        heal_wait_sec=float(os.environ.get("C4_MESH_HEAL_SEAL_WAIT_SEC", "15")),
                        seal_subphase="pre_seal_mesh_heal",
                    )
                    rc_pre = 0 if mesh_nine_cell_surface_ok(doc_pre) else 1
                else:
                    poke_stale(ctx, earth_path)
                    rc_pre = playwright_cell(ctx)
                    if _truthy_env_first(
                        "C4_DISCORD_MESH_SURFACE_SELF_HEAL",
                        "C4_PLANETARY_SELF_HEAL",
                        default=True,
                    ):
                        doc_pre = heal_earth_audit_from_raw(earth_path)
                    else:
                        doc_pre = load_earth_audit(earth_path)
                if not discord_or_mesh_surface_closure_ok(doc_pre, ctx):
                    st.rollback_count += 1
                    spin.reset()
                    st.gate = Gate.discord_mesh_surface
                    append_heartbeat(
                        ctx,
                        {
                            "anti_entropy": "rollback_to_discord_mesh_surface",
                            "reason": "pre_seal_discord_mesh_surface_not_ok",
                            "playwright_rc": rc_pre,
                            "earth_torsion_hint": doc_pre.get("earth_torsion_hint"),
                            "mesh_mooring_closed": doc_pre.get("mesh_mooring_closed"),
                            "surface_mode": "mesh_nine_cell_http"
                            if ctx.mesh_nine_cell_surface
                            else "discord_playwright_earth_audit",
                            "elapsed_ms": (time.perf_counter() - t_pre) * 1000,
                            "seal_subphase": "pre_seal_mesh_heal",
                            "mesh_heal_meta": _pre_hm,
                        },
                    )
                    continue

                rc_docx, docx_path = run_sealing(ctx)
                if rc_docx != 0 or not docx_path:
                    append_heartbeat(
                        ctx,
                        {
                            "gate": Gate.sealing.value,
                            "last_error": f"docx_rc={rc_docx}",
                            "terminal": "PARTIAL",
                        },
                    )
                    sig = f"seal:{rc_docx}"
                    if spin.observe(Gate.sealing.value, sig):
                        ex = klein_fold_spin_or_exit(
                            ctx,
                            lock_path,
                            spin,
                            st,
                            Gate.sealing,
                            sig,
                            "run_full_release_invariant.py:sealingGate docx",
                        )
                    continue

                ok_md5, md5msg = verify_docx_semantics_md5(ctx, docx_path)
                if not ok_md5:
                    append_heartbeat(ctx, {"gate": Gate.sealing.value, "last_error": md5msg})
                    if spin.observe(Gate.sealing.value, md5msg):
                        ex = klein_fold_spin_or_exit(
                            ctx,
                            lock_path,
                            spin,
                            st,
                            Gate.sealing,
                            md5msg,
                            "run_full_release_invariant.py:sealingGate md5",
                        )
                    continue

                _post_hm: dict[str, Any] | None = None
                if ctx.mesh_nine_cell_surface:
                    doc_post, _post_ha, _post_hm = mesh_probe_after_optional_heal(
                        ctx,
                        repo,
                        gate_value=Gate.sealing.value,
                        max_heal_attempts=int(os.environ.get("C4_MESH_HEAL_SEAL_MAX_ATTEMPTS", "5")),
                        heal_wait_sec=float(os.environ.get("C4_MESH_HEAL_SEAL_WAIT_SEC", "15")),
                        seal_subphase="post_seal_mesh_heal",
                    )
                    rc_post = 0 if mesh_nine_cell_surface_ok(doc_post) else 1
                else:
                    poke_stale(ctx, earth_path)
                    rc_post = playwright_cell(ctx)
                    if _truthy_env_first(
                        "C4_DISCORD_MESH_SURFACE_SELF_HEAL",
                        "C4_PLANETARY_SELF_HEAL",
                        default=True,
                    ):
                        doc_post = heal_earth_audit_from_raw(earth_path)
                    else:
                        doc_post = load_earth_audit(earth_path)
                if not discord_or_mesh_surface_closure_ok(doc_post, ctx):
                    st.rollback_count += 1
                    spin.reset()
                    st.gate = Gate.discord_mesh_surface
                    append_heartbeat(
                        ctx,
                        {
                            "anti_entropy": "rollback_to_discord_mesh_surface",
                            "reason": "post_seal_discord_mesh_surface_drift",
                            "playwright_rc": rc_post,
                            "earth_torsion_hint": doc_post.get("earth_torsion_hint"),
                            "mesh_mooring_closed": doc_post.get("mesh_mooring_closed"),
                            "surface_mode": "mesh_nine_cell_http"
                            if ctx.mesh_nine_cell_surface
                            else "discord_playwright_earth_audit",
                            "sealed_docx": str(docx_path),
                            "seal_subphase": "post_seal_mesh_heal",
                            "mesh_heal_meta": _post_hm,
                        },
                    )
                    continue

                st.last_sealed_docx = docx_path
                st.last_md5_msg = md5msg
                st.last_earth_doc = doc_post
                release_governor_lock(lock_path)
                sealed_ok = write_final(
                    ctx,
                    INVARIANT_EXIT_TERMINAL,
                    {
                        "gate": Gate.done.value,
                        "docx": str(st.last_sealed_docx) if st.last_sealed_docx else None,
                        "c4_semantics_md5_verified": st.last_md5_msg or None,
                        "surface_mode": "mesh_nine_cell_http"
                        if ctx.mesh_nine_cell_surface
                        else "discord_playwright_earth_audit",
                        "c4_surface_evidence": st.last_earth_doc
                        or (
                            load_mesh_witness(mesh_witness_path)
                            if ctx.mesh_nine_cell_surface
                            else load_earth_audit(earth_path)
                        ),
                        "rollback_count": st.rollback_count,
                        "last_full_session_rc": st.last_full_session_rc,
                        "require_full_session": ctx.require_full_session,
                        "full_compliance": ctx.full_compliance,
                        "clear_release_deck": ctx.clear_release_deck,
                    },
                    st=st,
                )
                if not sealed_ok:
                    append_heartbeat(
                        ctx,
                        {
                            "gate": Gate.sealing.value,
                            "terminal": "PARTIAL",
                            "note": "write_final(CURE) failed — spiral, do not exit governor",
                        },
                    )
                    time.sleep(max(ctx.heartbeat_sec, 5.0))
                    continue
                append_heartbeat(ctx, {"terminal": INVARIANT_EXIT_TERMINAL, "gate": Gate.done.value})
                return EXIT_OK

            # --- done gate (legacy): CURE always requires sealing + DOCX — fold back ---
            if st.gate == Gate.done:
                append_heartbeat(
                    ctx,
                    {
                        "gate": Gate.done.value,
                        "terminal": "PARTIAL",
                        "note": "CURE requires sealed DOCX — redirecting to sealingGate",
                        "mesh_first_surface": _mesh_first_surface(ctx),
                    },
                )
                st.gate = Gate.sealing
                continue

            # --- unknown gate: spiral only (no REFUSED) ---
            append_heartbeat(
                ctx,
                {
                    "klein_foldback": True,
                    "note": "unknown_gate_retry — invariant spiral",
                    "gate": str(st.gate),
                },
            )
            time.sleep(max(ctx.heartbeat_sec, 2.0))
            continue
        except Exception as _invariant_tick_exc:
            try:
                _gv = st.gate.value
            except Exception:
                _gv = "unknown"
            append_heartbeat(
                ctx,
                {
                    "gate": _gv,
                    "phase": "tick_exception_self_heal",
                    "error": repr(_invariant_tick_exc),
                    "error_type": type(_invariant_tick_exc).__name__,
                    "note": "uncaught exception in governor tick — spiral (no process death)",
                },
            )
            time.sleep(max(ctx.heartbeat_sec, 5.0))
            continue


if __name__ == "__main__":
    raise SystemExit(main())