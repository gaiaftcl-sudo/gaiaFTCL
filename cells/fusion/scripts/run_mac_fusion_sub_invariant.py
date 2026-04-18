#!/usr/bin/env python3
"""LEGACY Mac Fusion sub-governor (sidecar/DMG path).

Default invariant path is now scripts/run_native_rust_fusion_invariant.py.
"""

from __future__ import annotations

import argparse
import glob
import hashlib
import json
import os
import shutil
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


INVARIANT_ID = "gaiaftcl_mac_fusion_sub_invariant_v1"
GATES = [
    "fusionControlAppBuildTestGate",
    "fusionPlasmaAppBuildGate",
    "dmgArtifactGate",
    "dmgMountGate",
    "outerRebuildRedeployGate",
    "macInstallWitnessGate",
    "swiftRuntimeGate",
    "sidecarControlSurfaceGate",
    "macMooringFilesGate",
    "fusionMacVisualGate",
    "outerOpsAdminGate",
    "teamReadinessProofGate",
    "surfaceParityInputGate",
    "subSealingGate",
]

# Successful process exit receipt — must match run_full_release_invariant.INVARIANT_EXIT_TERMINAL.
INVARIANT_EXIT_TERMINAL = "CURE"


def _ok_terminal(t: Any) -> bool:
    """Accept CURE (exit) or legacy CALORIE in external parity artifacts."""
    u = str(t or "").upper()
    return u in ("CURE", "CALORIE")


@dataclass
class Ctx:
    repo_root: Path
    contract_path: Path
    schema_path: Path
    evidence_dir: Path
    run_id: str
    hb_path: Path
    final_path: Path
    latest_path: Path
    debug_dir: Path
    debug_hb_path: Path
    debug_final_path: Path
    debug_latest_path: Path


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def append_hb(ctx: Ctx, row: dict[str, Any]) -> None:
    row.setdefault("ts_utc", utc_now())
    ctx.evidence_dir.mkdir(parents=True, exist_ok=True)
    with ctx.hb_path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(row, ensure_ascii=False) + "\n")
    ctx.debug_dir.mkdir(parents=True, exist_ok=True)
    with ctx.debug_hb_path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(row, ensure_ascii=False) + "\n")


def write_final(ctx: Ctx, terminal: str, payload: dict[str, Any]) -> None:
    out = {
        "schema": "gaiaftcl_mac_fusion_sub_invariant_receipt_v1",
        "invariant_id": INVARIANT_ID,
        "terminal": terminal,
        "ts_utc": utc_now(),
        "run_id": ctx.run_id,
        "heartbeat_jsonl": str(ctx.hb_path),
    }
    out.update(payload)
    ctx.evidence_dir.mkdir(parents=True, exist_ok=True)
    ctx.final_path.write_text(json.dumps(out, indent=2), encoding="utf-8")
    shutil.copy2(ctx.final_path, ctx.latest_path)
    ctx.debug_dir.mkdir(parents=True, exist_ok=True)
    ctx.debug_final_path.write_text(json.dumps(out, indent=2), encoding="utf-8")
    shutil.copy2(ctx.debug_final_path, ctx.debug_latest_path)


def write_gate_witness(ctx: Ctx, gate: str, ok: bool, witness: dict[str, Any], blocker: str | None) -> None:
    ctx.debug_dir.mkdir(parents=True, exist_ok=True)
    p = ctx.debug_dir / f"gate_witness_{gate}.json"
    doc = {
        "gate": gate,
        "ok": ok,
        "terminal": INVARIANT_EXIT_TERMINAL if ok else ("BLOCKED" if blocker else "REFUSED"),
        "blocker": blocker,
        "witness": witness,
        "ts_utc": utc_now(),
    }
    p.write_text(json.dumps(doc, indent=2), encoding="utf-8")


def classify_blocked(text: str) -> str | None:
    low = text.lower()
    if "oauth" in low or "mfa" in low:
        return "oauth_mfa_required"
    if "manual" in low and ("identity" in low or "login" in low):
        return "manual_identity_step"
    if "passcode" in low or "touch id" in low or "biometric" in low:
        return "device_passcode_required"
    return None


def run_cmd(cmd: list[str], cwd: Path, timeout: int = 240) -> tuple[int, str]:
    try:
        cp = subprocess.run(
            cmd,
            cwd=str(cwd),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout,
            check=False,
        )
        return cp.returncode, cp.stdout[-6000:]
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or "") + "\nTIMEOUT"
        return 124, out[-6000:]
    except Exception as e:  # noqa: BLE001
        return 125, f"{type(e).__name__}: {e}"


def run_discord_onboarding_with_retry(ctx: Ctx, attempts: int = 2) -> tuple[int, str, list[dict[str, Any]]]:
    # DISCORD_DISABLED_FOR_SWIFT_INVARIANT
    return 0, "discord onboarding skipped by invariant policy", [{"attempt": 1, "rc": 0, "tail": "disabled"}]


def validate_contract(ctx: Ctx) -> dict[str, Any]:
    if not ctx.contract_path.is_file():
        raise ValueError(f"missing contract: {ctx.contract_path}")
    contract = json.loads(ctx.contract_path.read_text(encoding="utf-8"))
    if contract.get("invariant_id") != INVARIANT_ID:
        raise ValueError("contract invariant_id mismatch")
    if contract.get("gate_order") != GATES:
        raise ValueError("contract gate order mismatch")
    if not ctx.schema_path.is_file():
        raise ValueError(f"missing schema: {ctx.schema_path}")
    return contract


def gate_fusion_control_app_build_test(ctx: Ctx) -> tuple[bool, dict[str, Any], str | None]:
    """Create + test full FusionControl.app (Rust/Metal) — scripts/fusion_control_dmg_gate.sh → batch receipt."""
    if sys.platform != "darwin":
        return False, {"reason": "darwin_required", "platform": sys.platform}, "darwin_required"
    rc, out = run_cmd(["bash", "scripts/fusion_control_dmg_gate.sh"], cwd=ctx.repo_root, timeout=7200)
    receipt_path = ctx.repo_root / "evidence" / "fusion_control" / "dmg_gate_2000_cycle_receipt.json"
    app_root = ctx.repo_root / "services" / "fusion_control_mac" / "dist" / "FusionControl.app"
    bin_path = app_root / "Contents" / "MacOS" / "fusion_control"
    witness: dict[str, Any] = {
        "script_rc": rc,
        "script_tail": "\n".join(out.splitlines()[-24:]),
        "receipt_path": str(receipt_path) if receipt_path.is_file() else None,
        "app_bundle_path": str(app_root),
        "main_binary_path": str(bin_path) if bin_path.is_file() else None,
        "bundle_present_executable": app_root.is_dir() and bin_path.is_file() and os.access(bin_path, os.X_OK),
    }
    if rc != 0 or not receipt_path.is_file():
        return False, {"reason": "invariant_violation", **witness}, None
    try:
        doc = json.loads(receipt_path.read_text(encoding="utf-8"))
    except Exception as e:  # noqa: BLE001
        return False, {"reason": "invariant_violation", **witness, "parse_error": str(e)}, None
    receipt_ok = (
        doc.get("ok") is True
        and doc.get("schema") == "fusion_control_batch_receipt_v1"
        and doc.get("cycles_completed") == doc.get("cycles_requested")
        and int(doc.get("cycles_failed", 0)) == 0
    )
    witness["receipt_ok"] = receipt_ok
    witness["cycles_completed"] = doc.get("cycles_completed")
    witness["cycles_requested"] = doc.get("cycles_requested")
    witness["validation_engine"] = doc.get("validation_engine")
    witness["metallib"] = doc.get("metallib")
    if not receipt_ok or not witness["bundle_present_executable"]:
        return False, {"reason": "invariant_violation", **witness}, None
    return True, witness, None


def gate_fusion_plasma_app_build(ctx: Ctx) -> tuple[bool, dict[str, Any], str | None]:
    """First gate: production FusionSidecarHost.app (Release) — xcodebuild, no DMG shortcuts."""
    if sys.platform != "darwin":
        return False, {"reason": "darwin_required", "platform": sys.platform}, "darwin_required"
    rc, out = run_cmd(["bash", "scripts/build_fusion_plasma_app_release.sh"], cwd=ctx.repo_root, timeout=7200)
    witness_path = ctx.repo_root / "evidence" / "mac_fusion" / "FUSION_PLASMA_APP_BUILD_WITNESS.json"
    app_staged = ctx.repo_root / "build" / "plasma_release" / "FusionSidecarHost.app"
    bin_staged = app_staged / "Contents" / "MacOS" / "FusionSidecarHost"
    doc: dict[str, Any] = {}
    if witness_path.is_file():
        try:
            doc = json.loads(witness_path.read_text(encoding="utf-8"))
        except Exception as e:  # noqa: BLE001
            doc = {"parse_error": str(e)}
    schema_ok = doc.get("schema") == "gaiaftcl_fusion_plasma_app_build_witness_v1"
    bundle_ok = app_staged.is_dir() and bin_staged.is_file() and os.access(bin_staged, os.X_OK)
    sha_ok = bool(doc.get("binary_sha256")) and len(str(doc.get("binary_sha256"))) == 64
    witness = {
        "build_script_rc": rc,
        "build_script_tail": "\n".join(out.splitlines()[-24:]),
        "witness_path": str(witness_path) if witness_path.is_file() else None,
        "schema_ok": schema_ok,
        "bundle_present_executable": bundle_ok,
        "binary_sha256_present": sha_ok,
        "cf_bundle_short_version_string": doc.get("cf_bundle_short_version_string"),
        "cf_bundle_identifier": doc.get("cf_bundle_identifier"),
    }
    if rc != 0 or not schema_ok or not bundle_ok or not sha_ok:
        return False, {"reason": "invariant_violation", **witness}, None
    return True, witness, None


def gate_dmg_artifact(ctx: Ctx) -> tuple[bool, dict[str, Any], str | None]:
    # Contract requires DMG creation in invariant path; ensure script builds if missing.
    rc_ensure, out_ensure = run_cmd(
        ["bash", "scripts/ensure_gaiafusion_dmg.sh"],
        cwd=ctx.repo_root,
        timeout=3600,
    )
    if rc_ensure != 0:
        return (
            False,
            {
                "reason": "missing_artifact",
                "ensure_script_rc": rc_ensure,
                "ensure_output_tail": out_ensure,
            },
            None,
        )
    patterns = [
        str(ctx.repo_root / "build" / "GaiaFusion*.dmg"),
        str(ctx.repo_root / "dist" / "GaiaFusion*.dmg"),
        str(ctx.repo_root / "*.dmg"),
    ]
    hits: list[Path] = []
    for pat in patterns:
        hits.extend(Path(p) for p in glob.glob(pat))
    if not hits:
        return False, {"reason": "missing_artifact", "patterns": patterns}, None
    dmg = sorted(hits, key=lambda p: p.stat().st_mtime, reverse=True)[0]
    st = dmg.stat()
    return True, {
        "dmg_path": str(dmg.resolve()),
        "dmg_size_bytes": st.st_size,
        "dmg_sha256": sha256_file(dmg),
        "ensure_script_rc": rc_ensure,
    }, None


def gate_dmg_mount(ctx: Ctx, dmg_path: str | None) -> tuple[bool, dict[str, Any], str | None]:
    t0 = time.perf_counter()
    mountpoint = Path("/Volumes/GaiaFusion")
    env_prefix: list[str] = []
    if dmg_path:
        env_prefix = ["env", f"GAIAFUSION_DMG={dmg_path}"]
    # Always run mount witness even if mountpoint exists: invariant must assert fresh mount path.
    rc, out = run_cmd(env_prefix + ["bash", "scripts/mount_gaiafusion_dmg.sh"], cwd=ctx.repo_root, timeout=240)
    if rc != 0:
        return False, {"reason": "invariant_violation", "mount_script_rc": rc, "output_tail": out}, None
    rc_df, out_df = run_cmd(["df", "-h", str(mountpoint)], cwd=ctx.repo_root, timeout=20)
    if rc_df != 0:
        return False, {"reason": "invariant_violation", "df_rc": rc_df, "output_tail": out_df}, None
    sidecar_mounted = (mountpoint / "FusionSidecarHost.app").is_dir()
    fusion_ctrl_mounted = (mountpoint / "FusionControl.app").is_dir()
    if not sidecar_mounted or not fusion_ctrl_mounted:
        return False, {
            "reason": "invariant_violation",
            "mountpoint": str(mountpoint),
            "fusion_sidecar_host_app_present": sidecar_mounted,
            "fusion_control_app_present": fusion_ctrl_mounted,
            "df_line": out_df.strip().splitlines()[-1] if out_df.strip() else "",
        }, None
    return True, {
        "mountpoint": str(mountpoint),
        "df_line": out_df.strip().splitlines()[-1] if out_df.strip() else "",
        "fusion_sidecar_host_app_present": sidecar_mounted,
        "fusion_control_app_present": fusion_ctrl_mounted,
        "elapsed_ms": (time.perf_counter() - t0) * 1000.0,
        "mount_script_output_tail": "\n".join(out.splitlines()[-12:]),
    }, None


def gate_install_witness(ctx: Ctx) -> tuple[bool, dict[str, Any], str | None]:
    candidates = [
        ctx.repo_root / "services" / "fusion_control_mac" / "dist" / "FusionControl.app" / "Contents" / "MacOS" / "fusion_control",
        Path("/Volumes/GaiaFusion/FusionControl.app/Contents/MacOS/fusion_control"),
        ctx.repo_root / "build" / "plasma_release" / "FusionSidecarHost.app" / "Contents" / "MacOS" / "FusionSidecarHost",
        Path("/Volumes/GaiaFusion/FusionSidecarHost.app/Contents/MacOS/FusionSidecarHost"),
        Path("/Applications/FusionSidecarHost.app/Contents/MacOS/FusionSidecarHost"),
        Path("/Volumes/GaiaFusion/GaiaFTCL.app/Contents/MacOS/GaiaFTCL"),
        Path("/Applications/GaiaFTCL.app/Contents/MacOS/GaiaFTCL"),
        Path("/Volumes/GaiaFusion/GaiaFusion.app/Contents/MacOS/GaiaFusion"),
        Path("/Applications/GaiaFusion.app/Contents/MacOS/GaiaFusion"),
        Path("/Applications/FusionControl.app/Contents/MacOS/FusionControl"),
    ]
    for c in candidates:
        if c.exists():
            rc, out = run_cmd(["bash", "-lc", f"'{c}' --version"], cwd=Path.cwd(), timeout=20)
            return True, {
                "resolved_binary_path": str(c),
                "is_executable": os.access(c, os.X_OK),
                "version_probe": out.strip().splitlines()[-1] if rc == 0 and out.strip() else "unavailable",
            }, None
    return False, {"reason": "missing_artifact", "candidates": [str(c) for c in candidates]}, None


def gate_rebuild_redeploy(ctx: Ctx) -> tuple[bool, dict[str, Any], str | None]:
    # Outer cure requirement: recreate DMG + publish to mesh.
    rc_build, out_build = run_cmd(["bash", "scripts/build_gaiaftcl_facade_dmg.sh"], cwd=ctx.repo_root, timeout=3600)
    if rc_build != 0:
        return False, {"reason": "invariant_violation", "build_rc": rc_build, "build_tail": "\n".join(out_build.splitlines()[-20:])}, None
    rc_deploy, out_deploy = run_cmd(["bash", "scripts/deploy_dmg_to_mesh.sh"], cwd=ctx.repo_root, timeout=3600)
    low = out_deploy.lower()
    blocker = None
    if "ssh key not found" in low or "permission denied" in low or "operation timed out" in low or "no route to host" in low:
        blocker = "mesh_dmg_deploy_blocked"
    witness = {
        "build_rc": rc_build,
        "build_tail": "\n".join(out_build.splitlines()[-12:]),
        "deploy_rc": rc_deploy,
        "deploy_tail": "\n".join(out_deploy.splitlines()[-20:]),
    }
    if rc_deploy != 0:
        return False, {"reason": "invariant_violation", **witness}, blocker
    return True, witness, None


def gate_swift_runtime(ctx: Ctx) -> tuple[bool, dict[str, Any], str | None]:
    # Ensure local Swift app + local npm UI target are running before tests.
    rc_ui, out_ui = run_cmd(
        ["bash", "-lc", "curl -sfS -m 8 -o /dev/null -w '%{http_code}' http://127.0.0.1:8910/fusion-s4"],
        cwd=ctx.repo_root,
        timeout=15,
    )
    ui_ok = rc_ui == 0 and out_ui.strip() == "200"
    healed_steps: list[dict[str, Any]] = []
    if not ui_ok:
        rc_launch, out_launch = run_cmd(
            ["env", "FUSION_STACK_DETACHED=1", "bash", "scripts/fusion_stack_launch.sh", "local"],
            cwd=ctx.repo_root,
            timeout=300,
        )
        healed_steps.append({"step": "fusion_stack_launch_detached", "rc": rc_launch, "tail": "\n".join(out_launch.splitlines()[-12:])})
        rc_ui, out_ui = run_cmd(
            ["bash", "-lc", "curl -sfS -m 12 -o /dev/null -w '%{http_code}' http://127.0.0.1:8910/fusion-s4"],
            cwd=ctx.repo_root,
            timeout=20,
        )
        ui_ok = rc_ui == 0 and out_ui.strip() == "200"

    app_binary_candidates = [
        ctx.repo_root / "build" / "plasma_release" / "FusionSidecarHost.app" / "Contents" / "MacOS" / "FusionSidecarHost",
        Path("/Applications/FusionSidecarHost.app/Contents/MacOS/FusionSidecarHost"),
        Path("/Volumes/GaiaFusion/FusionSidecarHost.app/Contents/MacOS/FusionSidecarHost"),
        Path("/Applications/GaiaFTCL.app/Contents/MacOS/GaiaFTCL"),
        Path("/Volumes/GaiaFusion/GaiaFTCL.app/Contents/MacOS/GaiaFTCL"),
        Path("/Applications/FusionControl.app/Contents/MacOS/FusionControl"),
        Path("/Volumes/GaiaFusion/FusionControl.app/Contents/MacOS/FusionControl"),
    ]
    resolved_app_binary = next((p for p in app_binary_candidates if p.exists()), None)
    app_version_probe = ""
    app_binary_executable = False
    if resolved_app_binary is not None:
        app_binary_executable = os.access(resolved_app_binary, os.X_OK)
        rc_ver, out_ver = run_cmd(
            ["bash", "-lc", f"'{resolved_app_binary}' --version || true"],
            cwd=ctx.repo_root,
            timeout=20,
        )
        if rc_ver in (0, 1):
            app_version_probe = "\n".join(out_ver.splitlines()[-3:]).strip()
    rc_pg, out_pg = run_cmd(
        ["bash", "-lc", "pgrep -fal \"FusionSidecarHost|GaiaFTCL|FusionControl\" || true"],
        cwd=ctx.repo_root,
        timeout=10,
    )
    swift_running = bool(out_pg.strip())
    if not swift_running:
        app_candidates = [
            str(ctx.repo_root / "build" / "plasma_release" / "FusionSidecarHost.app"),
            "/Applications/FusionSidecarHost.app",
            "/Volumes/GaiaFusion/FusionSidecarHost.app",
            "/Applications/GaiaFTCL.app",
            "/Volumes/GaiaFusion/GaiaFTCL.app",
        ]
        for app in app_candidates:
            rc_open, out_open = run_cmd(["open", "-a", app], cwd=ctx.repo_root, timeout=20)
            healed_steps.append({"step": f"open_app:{app}", "rc": rc_open, "tail": "\n".join(out_open.splitlines()[-6:])})
            if rc_open == 0:
                break
        _rc_pg2, out_pg2 = run_cmd(
            ["bash", "-lc", "pgrep -fal \"FusionSidecarHost|GaiaFTCL|FusionControl\" || true"],
            cwd=ctx.repo_root,
            timeout=10,
        )
        swift_running = bool(out_pg2.strip())
        out_pg = out_pg2 or out_pg
    witness = {
        "ui_http_ok": ui_ok,
        "ui_http_code": out_ui.strip(),
        "app_binary_path": str(resolved_app_binary) if resolved_app_binary else None,
        "app_binary_executable": app_binary_executable,
        "app_version_probe": app_version_probe or "unavailable",
        "swift_runtime_running": swift_running,
        "swift_runtime_processes": [x for x in out_pg.splitlines() if x.strip()][:20],
        "self_heal_steps": healed_steps,
    }
    if not ui_ok or not swift_running or not resolved_app_binary or not app_binary_executable:
        return False, {"reason": "invariant_violation", **witness}, None
    return True, witness, None


def gate_sidecar_control_surface(ctx: Ctx) -> tuple[bool, dict[str, Any], str | None]:
    p = ctx.repo_root / "macos" / "FusionSidecarHost" / "FusionSidecarHost" / "ContentView.swift"
    app_p = ctx.repo_root / "macos" / "FusionSidecarHost" / "FusionSidecarHost" / "FusionSidecarHostApp.swift"
    if not p.is_file():
        return False, {"reason": "missing_artifact", "content_view_path": str(p)}, None
    if not app_p.is_file():
        return False, {"reason": "missing_artifact", "app_path": str(app_p)}, None
    src = p.read_text(encoding="utf-8")
    app_src = app_p.read_text(encoding="utf-8")
    has_webkit = "import WebKit" in src and "WKWebView" in src
    has_local_surface = "http://127.0.0.1:8910/fusion-s4" in src
    discord_intentionally_disabled = ("DISCORD_DISABLED_FOR_SWIFT_INVARIANT" in src) or ("DISCORD_DISABLED_FOR_SWIFT_INVARIANT" in app_src)
    has_playwright_onboarding = (
        "Run Playwright Walkthrough" in src and "run_fusion_new_user_playwright.sh" in src
    )
    has_glass = (
        "glassEffectCompat" in src and
        ".ultraThinMaterial" in src and
        "FusionManifoldTheme" in src
    )
    has_dynamic_blue_theme = "Daylight Blue Glass" in src and "Evening Blue Glass" in src
    has_fusion_menu_actions = (
        "CommandMenu(\"Fusion\")" in app_src and
        ".fusionStartVM" in app_src and
        ".fusionStopAll" in app_src and
        ".fusionRunPlaywrightOnboarding" in app_src
    )
    witness = {
        "content_view_path": str(p),
        "app_path": str(app_p),
        "has_webkit_surface": has_webkit,
        "has_local_surface_url": has_local_surface,
        "discord_intentionally_disabled": discord_intentionally_disabled,
        "has_playwright_onboarding_hook": has_playwright_onboarding,
        "has_glass_effect": has_glass,
        "has_dynamic_blue_theme": has_dynamic_blue_theme,
        "has_fusion_menu_actions": has_fusion_menu_actions,
    }
    if (
        not has_webkit
        or not has_local_surface
        or not discord_intentionally_disabled
        or not has_playwright_onboarding
        or not has_glass
        or not has_dynamic_blue_theme
        or not has_fusion_menu_actions
    ):
        return False, {"reason": "invariant_violation", **witness}, None
    return True, witness, None


def gate_mooring_files(ctx: Ctx, max_age_sec: int) -> tuple[bool, dict[str, Any], str | None]:
    home = Path.home() / ".gaiaftcl"
    files = {
        "cell_identity": home / "cell_identity.json",
        "mount_receipt": home / "mount_receipt.json",
        "fusion_mesh_mooring_state": home / "fusion_mesh_mooring_state.json",
    }
    now = time.time()
    out: dict[str, Any] = {"files": {}, "all_present": True, "max_age_sec": max_age_sec}
    oldest_ok = True
    for name, p in files.items():
        ent: dict[str, Any] = {"path": str(p), "present": p.is_file()}
        if p.is_file():
            mtime = p.stat().st_mtime
            ent["mtime_utc"] = datetime.fromtimestamp(mtime, tz=timezone.utc).isoformat()
            ent["age_sec"] = now - mtime
            try:
                ent["json_valid"] = isinstance(json.loads(p.read_text(encoding="utf-8")), dict)
            except Exception:  # noqa: BLE001
                ent["json_valid"] = False
            if ent["age_sec"] > max_age_sec:
                oldest_ok = False
        else:
            out["all_present"] = False
            oldest_ok = False
        out["files"][name] = ent
    # Self-heal attempt: refresh mount receipt + mesh heartbeat from current identity wallet.
    if not out["all_present"] or not oldest_ok:
        ident_path = files["cell_identity"]
        wallet = ""
        if ident_path.is_file():
            try:
                ident = json.loads(ident_path.read_text(encoding="utf-8"))
                wallet = str(ident.get("wallet", "")).strip()
            except Exception:  # noqa: BLE001
                wallet = ""
        if wallet and wallet.startswith("0x") and len(wallet) == 42:
            rc_onboard, out_onboard = run_cmd(
                ["bash", "deploy/mac_cell_mount/bin/cell_onboard.sh", "--wallet", wallet],
                cwd=ctx.repo_root,
                timeout=180,
            )
            rc_mount, out_mount = run_cmd(
                ["bash", "deploy/mac_cell_mount/bin/gaia_mount", "--wallet", wallet],
                cwd=ctx.repo_root,
                timeout=180,
            )
            nats_candidates: list[str] = []
            for candidate in (
                os.environ.get("NATS_URL", "").strip(),
                "nats://127.0.0.1:14222",
                "nats://127.0.0.1:4222",
                "nats://host.docker.internal:4222",
                f"nats://{os.environ.get('GAIAFTCL_HEAD_IP', '77.42.85.60')}:4222",
            ):
                if candidate and candidate not in nats_candidates:
                    nats_candidates.append(candidate)
            hb_attempts: list[dict[str, Any]] = []
            rc_hb = 1
            out_hb = "heartbeat_not_attempted"
            for nats_url in nats_candidates:
                rc_hb, out_hb = run_cmd(
                    [
                        "env",
                        f"NATS_URL={nats_url}",
                        "bash",
                        "deploy/mac_cell_mount/bin/fusion_mesh_mooring_heartbeat.sh",
                    ],
                    cwd=ctx.repo_root,
                    timeout=180,
                )
                hb_attempts.append(
                    {
                        "nats_url": nats_url,
                        "rc": rc_hb,
                        "tail": "\n".join(out_hb.splitlines()[-8:]),
                    }
                )
                if rc_hb == 0:
                    break
            # Recompute witness after refresh attempt.
            now = time.time()
            out = {"files": {}, "all_present": True, "max_age_sec": max_age_sec}
            oldest_ok = True
            for name, p in files.items():
                ent = {"path": str(p), "present": p.is_file()}
                if p.is_file():
                    mtime = p.stat().st_mtime
                    ent["mtime_utc"] = datetime.fromtimestamp(mtime, tz=timezone.utc).isoformat()
                    ent["age_sec"] = now - mtime
                    try:
                        ent["json_valid"] = isinstance(json.loads(p.read_text(encoding="utf-8")), dict)
                    except Exception:  # noqa: BLE001
                        ent["json_valid"] = False
                    if ent["age_sec"] > max_age_sec:
                        oldest_ok = False
                else:
                    out["all_present"] = False
                    oldest_ok = False
                out["files"][name] = ent
            out["self_heal_attempted"] = True
            out["self_heal_wallet"] = wallet
            out["self_heal_steps"] = {
                "cell_onboard": {"rc": rc_onboard, "tail": "\n".join(out_onboard.splitlines()[-8:])},
                "gaia_mount": {"rc": rc_mount, "tail": "\n".join(out_mount.splitlines()[-8:])},
                "mesh_heartbeat": {
                    "rc": rc_hb,
                    "tail": "\n".join(out_hb.splitlines()[-8:]),
                    "attempts": hb_attempts,
                },
            }
        else:
            out["self_heal_attempted"] = False
            out["self_heal_wallet"] = wallet or None
    if not out["all_present"]:
        return False, {"reason": "missing_artifact", **out}, None
    if not oldest_ok:
        # If only mesh heartbeat freshness remains stale after retries, classify as infrastructure BLOCKED.
        files_doc = out.get("files", {})
        cell_age = (((files_doc.get("cell_identity") or {}).get("age_sec")) or 10**9)  # type: ignore[assignment]
        mount_age = (((files_doc.get("mount_receipt") or {}).get("age_sec")) or 10**9)  # type: ignore[assignment]
        mesh_age = (((files_doc.get("fusion_mesh_mooring_state") or {}).get("age_sec")) or 10**9)  # type: ignore[assignment]
        if cell_age <= max_age_sec and mount_age <= max_age_sec and mesh_age > max_age_sec:
            return False, {"reason": "invariant_violation", **out}, "mesh_nats_unreachable"
        return False, {"reason": "invariant_violation", **out}, None
    return True, out, None


def gate_discord_surface(ctx: Ctx, min_state_bytes: int) -> tuple[bool, dict[str, Any], str | None]:
    # DISCORD_DISABLED_FOR_SWIFT_INVARIANT
    witness = {
        "discord_surface_gate_disabled": True,
        "policy_marker": "DISCORD_DISABLED_FOR_SWIFT_INVARIANT",
    }
    return True, witness, None


def gate_visual(ctx: Ctx, min_png_bytes: int, min_dom_bytes: int) -> tuple[bool, dict[str, Any], str | None]:
    rc, out = run_cmd(
        ["env", "FUSION_OPERATOR_PLAYWRIGHT=1", "bash", "scripts/verify_fusion_operator_surface.sh"],
        cwd=ctx.repo_root,
        timeout=1200,
    )
    png_candidates = glob.glob(str(ctx.repo_root / "evidence" / "**" / "*.png"), recursive=True)
    preferred_png = ctx.repo_root / "evidence" / "fusion_control" / "fusion_dashboard_witness.png"
    latest_png = preferred_png if preferred_png.is_file() else (
        Path(sorted(png_candidates, key=lambda p: Path(p).stat().st_mtime)[-1]) if png_candidates else None
    )
    size = latest_png.stat().st_size if latest_png and latest_png.is_file() else 0
    dom_html = ctx.repo_root / "evidence" / "fusion_control" / "fusion_dashboard_dom_snapshot.html"
    dom_json = ctx.repo_root / "evidence" / "fusion_control" / "fusion_dashboard_dom_snapshot.json"
    dom_bytes = dom_html.stat().st_size if dom_html.is_file() else 0
    projection_api_path = ctx.repo_root / "evidence" / "fusion_control" / "fusion_s4_projection_witness.json"
    rc_proj, out_proj = run_cmd(
        [
            "bash",
            "-lc",
            "curl -sfS -m 20 http://127.0.0.1:8910/api/fusion/s4-projection > "
            + f"'{projection_api_path}'",
        ],
        cwd=ctx.repo_root,
        timeout=30,
    )
    rc_ui, out_ui = run_cmd(
        [
            "bash",
            "-lc",
            "curl -sfS -m 20 -o /dev/null -w '%{http_code}' http://127.0.0.1:8910/fusion-s4",
        ],
        cwd=ctx.repo_root,
        timeout=30,
    )
    ui_http_ok = rc_ui == 0 and out_ui.strip() == "200"
    rc_fleet_ui, out_fleet_ui = run_cmd(
        [
            "bash",
            "-lc",
            "curl -sfS -m 20 -o /dev/null -w '%{http_code}' http://127.0.0.1:8910/fusion-fleet",
        ],
        cwd=ctx.repo_root,
        timeout=30,
    )
    fleet_ui_http_ok = rc_fleet_ui == 0 and out_fleet_ui.strip() == "200"
    rc_mesh_api, out_mesh_api = run_cmd(
        [
            "bash",
            "-lc",
            "curl -sfS -m 20 http://127.0.0.1:8910/api/fusion/fleet-digest",
        ],
        cwd=ctx.repo_root,
        timeout=30,
    )
    rc_games_api, out_games_api = run_cmd(
        [
            "bash",
            "-lc",
            "curl -sfS -m 20 http://127.0.0.1:8910/api/fusion/global-challenge-digest",
        ],
        cwd=ctx.repo_root,
        timeout=30,
    )
    projection_ok = False
    projection_configurable = False
    projection_schema = None
    dom_route_ok = False
    dom_anchor_ok = False
    mesh_api_ok = False
    games_api_ok = False
    operator_req_path = ctx.repo_root / "spec" / "mac_fusion_operator_requirements.json"
    operator_req_ok = False
    operator_games_ok = False
    operator_games_missing: list[str] = []
    operator_required_fields_missing: list[str] = []
    operator_player_class = None
    operator_personas: list[str] = []
    req_doc: dict[str, Any] = {}
    if operator_req_path.is_file():
        try:
            req_doc = json.loads(operator_req_path.read_text(encoding="utf-8"))
            operator_player_class = req_doc.get("player_class")
            if isinstance(req_doc.get("personas"), list):
                operator_personas = [str(x) for x in req_doc["personas"]]
            operator_req_ok = req_doc.get("schema") == "gaiaftcl_mac_fusion_operator_requirements_v1"
        except Exception:  # noqa: BLE001
            operator_req_ok = False
    if rc_proj == 0 and projection_api_path.is_file():
        try:
            proj = json.loads(projection_api_path.read_text(encoding="utf-8"))
            projection_schema = proj.get("schema")
            required_schema = str(req_doc.get("required_ui_schema", "gaiaftcl_fusion_s4_projection_ui_v1"))
            projection_ok = projection_schema == required_schema
            projection_configurable = bool(
                isinstance(proj.get("projection_s4"), dict)
                and isinstance(proj.get("flow_catalog_s4"), dict)
                and isinstance(proj.get("production_systems_ui"), list)
            )
            control_matrix = proj.get("control_matrix") if isinstance(proj, dict) else None
            control_matrix_ok = bool(
                isinstance(control_matrix, dict)
                and isinstance(control_matrix.get("receipt"), dict)
                and control_matrix.get("run_error") in (None, "")
            )
            long_run = proj.get("long_run") if isinstance(proj, dict) else None
            long_run_ok = bool(
                isinstance(long_run, dict)
                and isinstance(long_run.get("signals_jsonl"), str)
                and "jsonl_tail_line_count" in long_run
                and "running" in long_run
                and "last_record" in long_run
            )
            if dom_json.is_file():
                dom_doc = json.loads(dom_json.read_text(encoding="utf-8"))
                dom_url = str(dom_doc.get("url", ""))
                dom_route_ok = "/fusion-s4" in dom_url
                dom_anchor_ok = bool(
                    int(dom_doc.get("fusion_main_count", 0)) > 0
                    and int(dom_doc.get("fusion_status_ribbon_count", 0)) > 0
                    and int(dom_doc.get("fusion_mesh_discord_panel_count", 0)) > 0
                    and int(dom_doc.get("fusion_production_panel_count", 0)) > 0
                    and int(dom_doc.get("fusion_mesh_fleet_embed_count", 0)) > 0
                )
            if rc_mesh_api == 0:
                mesh_doc = json.loads(out_mesh_api)
                mesh_api_ok = bool(
                    isinstance(mesh_doc, dict)
                    and mesh_doc.get("schema_valid") is True
                    and isinstance(mesh_doc.get("snapshot"), dict)
                    and bool((mesh_doc.get("snapshot") or {}).get("schema"))
                )
            if rc_games_api == 0:
                games_doc = json.loads(out_games_api)
                games_api_ok = isinstance(games_doc, dict) and bool(games_doc.get("schema"))
            required_fields = req_doc.get("required_ui_contract_fields", [])
            if isinstance(required_fields, list):
                operator_required_fields_missing = [str(f) for f in required_fields if f not in proj]
            required_games = req_doc.get("required_games", [])
            if isinstance(required_games, list):
                text = json.dumps(proj, ensure_ascii=False).lower()
                for g in required_games:
                    gg = str(g).lower()
                    token_ok = gg in text
                    if gg == "moor":
                        token_ok = token_ok or isinstance(proj.get("mesh_operator_spine"), dict)
                    if gg == "long_run_start_stop":
                        token_ok = token_ok or isinstance(proj.get("long_run"), dict)
                    if gg == "control_matrix":
                        token_ok = token_ok or isinstance(proj.get("control_matrix"), dict)
                    if gg == "mesh_status":
                        token_ok = token_ok or isinstance(proj.get("mesh_operator_spine"), dict)
                    if gg == "global_sovereign_challenge":
                        token_ok = token_ok or isinstance(proj.get("global_sovereign_challenge"), dict)
                    if not token_ok:
                        operator_games_missing.append(str(g))
            operator_games_ok = len(operator_games_missing) == 0 and len(operator_required_fields_missing) == 0
        except Exception:  # noqa: BLE001
            projection_ok = False
            control_matrix_ok = False
            long_run_ok = False
            dom_route_ok = False
            dom_anchor_ok = False
            mesh_api_ok = False
            games_api_ok = False
    else:
        control_matrix_ok = False
        long_run_ok = False
        dom_route_ok = False
        dom_anchor_ok = False
        mesh_api_ok = False
        games_api_ok = False
    pass_line = ""
    for line in reversed(out.splitlines()):
        if "pass" in line.lower() or "ok" in line.lower():
            pass_line = line
            break
    blocked = classify_blocked(out)
    witness = {
        "png_path": str(latest_png) if latest_png else None,
        "png_size_bytes": size,
        "dom_snapshot_html_path": str(dom_html) if dom_html.is_file() else None,
        "dom_snapshot_json_path": str(dom_json) if dom_json.is_file() else None,
        "dom_snapshot_bytes": dom_bytes,
        "s4_projection_witness_path": str(projection_api_path) if projection_api_path.is_file() else None,
        "s4_projection_schema": projection_schema,
        "s4_projection_configurable": projection_configurable,
        "s4_projection_control_matrix_ok": control_matrix_ok,
        "s4_projection_long_run_ok": long_run_ok,
        "fusion_s4_route_http_ok": ui_http_ok,
        "fusion_s4_route_http_code": out_ui.strip(),
        "fusion_fleet_route_http_ok": fleet_ui_http_ok,
        "fusion_fleet_route_http_code": out_fleet_ui.strip(),
        "mesh_digest_api_ok": mesh_api_ok,
        "global_challenge_digest_api_ok": games_api_ok,
        "dom_route_ok": dom_route_ok,
        "dom_anchor_ok": dom_anchor_ok,
        "operator_requirements_path": str(operator_req_path) if operator_req_path.is_file() else None,
        "operator_requirements_ok": operator_req_ok,
        "operator_player_class": operator_player_class,
        "operator_personas": operator_personas,
        "operator_required_fields_missing": operator_required_fields_missing,
        "operator_games_missing": operator_games_missing,
        "operator_games_ok": operator_games_ok,
        "required_anchor_matched": bool(pass_line),
        "test_pass_line": pass_line,
    }
    if blocked:
        return False, witness, blocked
    if (
        rc != 0
        or size < min_png_bytes
        or dom_bytes < min_dom_bytes
        or not ui_http_ok
        or not fleet_ui_http_ok
        or not projection_ok
        or not projection_configurable
        or not control_matrix_ok
        or not long_run_ok
        or not dom_route_ok
        or not dom_anchor_ok
        or not mesh_api_ok
        or not games_api_ok
        or not operator_req_ok
        or not operator_games_ok
        or not witness["required_anchor_matched"]
    ):
        return False, {
            "reason": "invariant_violation",
            "script_exit_code": rc,
            "projection_fetch_rc": rc_proj,
            "projection_fetch_tail": out_proj[-800:],
            "output_tail": out[-3000:],
            **witness,
        }, None
    return True, witness, None


def gate_parity(ctx: Ctx) -> tuple[bool, dict[str, Any], str | None]:
    """Independent parity artifact only — no synthesis or on-disk enrichment (true invariant)."""
    p = ctx.repo_root / "evidence" / "parity" / "SURFACE_PARITY_WITNESS.json"
    if not p.is_file():
        return (
            False,
            {
                "reason": "missing_artifact",
                "parity_path": str(p),
                "invariant_rule": "SURFACE_PARITY_WITNESS.json must exist from the parity pipeline; invariant does not fabricate it",
            },
            None,
        )
    try:
        doc = json.loads(p.read_text(encoding="utf-8"))
    except Exception as e:  # noqa: BLE001
        return False, {"reason": "invariant_violation", "parity_path": str(p), "parse_error": str(e)}, None
    # Reject artifacts produced by earlier synthetic self-heal paths (not independent).
    bogus_modes = frozenset({"local_s4c4_invariant_self_heal", "local_lane_hash_enrichment"})
    pm = str(doc.get("parity_mode") or "")
    if pm in bogus_modes:
        return (
            False,
            {
                "reason": "non_independent_parity_artifact",
                "parity_path": str(p),
                "parity_mode": pm,
                "invariant_rule": "replace with pipeline-generated SURFACE_PARITY_WITNESS.json",
            },
            None,
        )
    schema = doc.get("schema")
    # Branch A — repo parity pipeline (Discord mesh games capture): scripts/generate_surface_parity_witness.py
    if schema == "surface_parity_witness_v1":
        try:
            divergence_count = int(doc.get("divergence_count", 1))
        except Exception:  # noqa: BLE001
            divergence_count = 1
        term = doc.get("terminal")
        witness = {
            "parity_path": str(p),
            "schema": schema,
            "parity_kind": "discord_mesh_games_pipeline",
            "divergence_count": divergence_count,
            "terminal": term,
            "games_total": doc.get("games_total"),
            "games_live": doc.get("games_live"),
            "missing_live_games": doc.get("missing_live_games"),
            "source": doc.get("source"),
            "parity_mode": pm or None,
            "independent_parity_artifact": True,
        }
        if divergence_count != 0 or not _ok_terminal(term):
            return False, {"reason": "invariant_violation", **witness}, None
        return True, witness, None

    # Branch B — fusion S4 projection + DOM/visual hash parity (independent file, not synthesized here)
    if schema == "gaiaftcl_surface_parity_witness_v1":
        divergence = doc.get("divergence_count", doc.get("divergences", 0))
        try:
            divergence_count = int(divergence)
        except Exception:  # noqa: BLE001
            divergence_count = 1
        proj_schema = (doc.get("checks") or {}).get("projection_schema")
        hashes = doc.get("hashes") if isinstance(doc.get("hashes"), dict) else {}
        has_hashes = all(bool(hashes.get(k)) for k in ("projection_sha256", "dom_sha256", "visual_sha256"))
        witness = {
            "parity_path": str(p),
            "schema": schema,
            "parity_kind": "fusion_s4_projection_hashes",
            "divergence_count": divergence_count,
            "terminal": doc.get("terminal"),
            "projection_schema": proj_schema,
            "parity_mode": pm or None,
            "has_hashes": has_hashes,
            "independent_parity_artifact": True,
        }
        if (
            divergence_count != 0
            or not _ok_terminal(doc.get("terminal"))
            or proj_schema != "gaiaftcl_fusion_s4_projection_ui_v1"
            or not has_hashes
        ):
            return False, {"reason": "invariant_violation", **witness}, None
        return True, witness, None

    return (
        False,
        {
            "reason": "invariant_violation",
            "parity_path": str(p),
            "schema": schema,
            "invariant_rule": "expected schema surface_parity_witness_v1 or gaiaftcl_surface_parity_witness_v1",
        },
        None,
    )


def gate_ops_admin(ctx: Ctx) -> tuple[bool, dict[str, Any], str | None]:
    rc_docker, out_docker = run_cmd(["bash", "-lc", "docker ps --format '{{.Names}}'"], cwd=ctx.repo_root, timeout=30)
    docker_names = [x.strip() for x in out_docker.splitlines() if x.strip()]
    docker_ok = rc_docker == 0 and len(docker_names) > 0

    sovereign_mesh_path = ctx.repo_root / "evidence" / "fusion_control" / "sovereign_mesh_witness.json"
    rc_sm, out_sm = run_cmd(
        ["bash", "-lc", f"curl -sfS -m 60 http://127.0.0.1:8910/api/sovereign-mesh > '{sovereign_mesh_path}'"],
        cwd=ctx.repo_root,
        timeout=90,
    )
    sovereign_mesh_ok = False
    sovereign_mesh_cells = 0
    if rc_sm == 0 and sovereign_mesh_path.is_file():
        try:
            sm = json.loads(sovereign_mesh_path.read_text(encoding="utf-8"))
            panels = sm.get("panels") if isinstance(sm, dict) else None
            sovereign_mesh_ok = bool(
                isinstance(panels, dict)
                and "mesh_cells" in panels
                and "fusion_fleet_snapshot" in panels
            )
            if sovereign_mesh_ok:
                cells = ((panels.get("mesh_cells") or {}).get("cells")) if isinstance(panels.get("mesh_cells"), dict) else []
                sovereign_mesh_cells = len(cells) if isinstance(cells, list) else 0
        except Exception:  # noqa: BLE001
            sovereign_mesh_ok = False

    rc_usd, out_usd = run_cmd(
        ["bash", "-lc", "curl -sfS -m 20 http://127.0.0.1:8910/api/fusion/fleet-usd"],
        cwd=ctx.repo_root,
        timeout=30,
    )
    openusd_ok = rc_usd == 0 and ("#usda 1.0" in out_usd or "# usda 1.0" in out_usd)

    dns_targets = ["gaiaftcl.com", "www.gaiaftcl.com"]
    dns_results: list[dict[str, Any]] = []
    dns_ok = True
    for host in dns_targets:
        rc_dns, out_dns = run_cmd(
            [
                "python3",
                "-c",
                "import socket,sys; h=sys.argv[1]; "
                "print(socket.gethostbyname(h))",
                host,
            ],
            cwd=ctx.repo_root,
            timeout=10,
        )
        one_ok = rc_dns == 0 and bool(out_dns.strip())
        dns_results.append({"host": host, "ok": one_ok, "answer": out_dns.strip() if one_ok else None})
        dns_ok = dns_ok and one_ok

    witness = {
        "docker_cli_ok": docker_ok,
        "docker_container_count": len(docker_names),
        "docker_container_names_sample": docker_names[:20],
        "sovereign_mesh_api_ok": sovereign_mesh_ok,
        "sovereign_mesh_witness_path": str(sovereign_mesh_path) if sovereign_mesh_path.is_file() else None,
        "sovereign_mesh_cells_count": sovereign_mesh_cells,
        "openusd_fleet_overlay_ok": openusd_ok,
        "dns_resolution_ok": dns_ok,
        "dns_resolution_results": dns_results,
    }
    if not docker_ok or not sovereign_mesh_ok or not openusd_ok or not dns_ok:
        return False, {"reason": "invariant_violation", **witness}, None
    return True, witness, None


def gate_team_readiness_proof(ctx: Ctx) -> tuple[bool, dict[str, Any], str | None]:
    """Sealed human/independent ledger only — invariant does not author PASS rows."""
    p = ctx.repo_root / "evidence" / "fusion_control" / "FUSION_11_TEAM_READINESS_PROOF.md"
    if not p.is_file():
        return (
            False,
            {
                "reason": "missing_artifact",
                "proof_path": str(p),
                "invariant_rule": "FUSION_11_TEAM_READINESS_PROOF.md must be sealed outside this runner; auto-generation disabled",
            },
            None,
        )
    txt = p.read_text(encoding="utf-8")
    low = txt.lower()
    has_schema = "gaiaftcl_fusion_team_readiness_proof_v1" in low
    has_total = "teams_total: 11" in low
    committed = ("committed_to_invest_time: true" in low) or ("willing to invest their time" in low)
    # Each team line must contain SEALED_PASS (not generic PASS from synthetic generator).
    sealed_lines = [ln for ln in txt.splitlines() if "TEAM_PASS_" in ln and "SEALED_PASS" in ln]
    pending_in_ledger = any("PENDING" in ln and "TEAM_PASS_" in ln for ln in txt.splitlines())
    witness = {
        "proof_path": str(p),
        "schema_ok": has_schema,
        "teams_total_ok": has_total,
        "commitment_ok": committed,
        "teams_sealed_count": len(sealed_lines),
        "teams_sealed_required": 11,
        "pending_in_team_ledger": pending_in_ledger,
        "independent_artifact_only": True,
    }
    if not has_schema or not has_total or not committed or len(sealed_lines) < 11 or pending_in_ledger:
        return False, {"reason": "invariant_violation", **witness}, None
    return True, witness, None


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Mac Fusion sub-governor invariant runner.")
    ap.add_argument("--repo-root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--validate-contract-only", action="store_true")
    ap.add_argument("--outer-max-cycles", type=int, default=1)
    ap.add_argument("--max-cycles", type=int, default=None, help="Alias for --outer-max-cycles")
    return ap.parse_args()


def outer_self_heal(ctx: Ctx, failed_gate: str) -> dict[str, Any]:
    steps: list[dict[str, Any]] = []
    # Deterministic repair actions by failure class.
    if failed_gate == "fusionControlAppBuildTestGate":
        rc, out = run_cmd(["bash", "scripts/fusion_control_dmg_gate.sh"], cwd=ctx.repo_root, timeout=7200)
        steps.append({"step": "fusion_control_dmg_gate", "rc": rc, "tail": "\n".join(out.splitlines()[-20:])})
    elif failed_gate == "fusionPlasmaAppBuildGate":
        rc, out = run_cmd(["bash", "scripts/build_fusion_plasma_app_release.sh"], cwd=ctx.repo_root, timeout=7200)
        steps.append({"step": "build_fusion_plasma_app_release", "rc": rc, "tail": "\n".join(out.splitlines()[-16:])})
    elif failed_gate == "surfaceParityInputGate":
        # Real pipeline script — not inline synthesis (requires PLAYWRIGHT_MESH_GAME_CAPTURE.json, etc.).
        rc, out = run_cmd(["python3", "scripts/generate_surface_parity_witness.py"], cwd=ctx.repo_root, timeout=300)
        steps.append({"step": "generate_surface_parity_witness", "rc": rc, "tail": "\n".join(out.splitlines()[-14:])})
    elif failed_gate in {"fusionMacVisualGate"}:
        rc, out = run_cmd(
            ["env", "FUSION_STACK_DETACHED=1", "FUSION_STACK_REUSE_UI=1", "bash", "scripts/fusion_stack_launch.sh", "local"],
            cwd=ctx.repo_root,
            timeout=300,
        )
        steps.append({"step": "fusion_stack_launch_detached_reuse_ui", "rc": rc, "tail": "\n".join(out.splitlines()[-10:])})
        rc, out = run_cmd(
            ["env", "FUSION_OPERATOR_PLAYWRIGHT=1", "bash", "scripts/verify_fusion_operator_surface.sh"],
            cwd=ctx.repo_root,
            timeout=1200,
        )
        steps.append({"step": "verify_fusion_operator_surface", "rc": rc, "tail": "\n".join(out.splitlines()[-10:])})
    elif failed_gate == "macMooringFilesGate":
        rc, out = run_cmd(["bash", "deploy/mac_cell_mount/bin/fusion_mesh_mooring_heartbeat.sh"], cwd=ctx.repo_root, timeout=240)
        steps.append({"step": "fusion_mesh_mooring_heartbeat", "rc": rc, "tail": "\n".join(out.splitlines()[-10:])})
    elif failed_gate == "outerOpsAdminGate":
        rc, out = run_cmd(["bash", "scripts/mesh_health_snapshot.sh"], cwd=ctx.repo_root, timeout=180)
        steps.append({"step": "mesh_health_snapshot", "rc": rc, "tail": "\n".join(out.splitlines()[-10:])})
        rc, out = run_cmd(
            ["env", "FUSION_STACK_DETACHED=1", "FUSION_STACK_REUSE_UI=1", "bash", "scripts/fusion_stack_launch.sh", "local"],
            cwd=ctx.repo_root,
            timeout=300,
        )
        steps.append({"step": "fusion_stack_launch_detached_reuse_ui", "rc": rc, "tail": "\n".join(out.splitlines()[-10:])})
    elif failed_gate in {"swiftRuntimeGate", "outerRebuildRedeployGate"}:
        rc, out = run_cmd(["bash", "scripts/fusion_control_dmg_gate.sh"], cwd=ctx.repo_root, timeout=7200)
        steps.append({"step": "fusion_control_dmg_gate", "rc": rc, "tail": "\n".join(out.splitlines()[-14:])})
        rc, out = run_cmd(["bash", "scripts/build_fusion_plasma_app_release.sh"], cwd=ctx.repo_root, timeout=7200)
        steps.append({"step": "build_fusion_plasma_app_release", "rc": rc, "tail": "\n".join(out.splitlines()[-12:])})
        rc, out = run_cmd(["env", "FUSION_STACK_DETACHED=1", "bash", "scripts/fusion_stack_launch.sh", "local"], cwd=ctx.repo_root, timeout=300)
        steps.append({"step": "fusion_stack_launch_detached", "rc": rc, "tail": "\n".join(out.splitlines()[-10:])})
        rc, out = run_cmd(["bash", "scripts/ensure_gaiafusion_dmg.sh"], cwd=ctx.repo_root, timeout=1800)
        steps.append({"step": "ensure_gaiafusion_dmg", "rc": rc, "tail": "\n".join(out.splitlines()[-10:])})
    else:
        rc, out = run_cmd(["bash", "scripts/ensure_gaiafusion_dmg.sh"], cwd=ctx.repo_root, timeout=1800)
        steps.append({"step": "ensure_gaiafusion_dmg", "rc": rc, "tail": "\n".join(out.splitlines()[-10:])})
    return {"failed_gate": failed_gate, "steps": steps}


def main() -> int:
    # Native path is authoritative. Legacy runner is blocked by default to prevent Discord/sidecar flow.
    matches = os.environ.get("GAIAFTCL_ALLOW_LEGACY_MAC_INVARIANT", "").strip()
    if not matches:
        print("REFUSED: legacy mac invariant disabled; run scripts/run_native_rust_fusion_invariant.py")
        return 2
    if matches.lower() not in {"1", "true", "yes"}:
        print("REFUSED: legacy mac invariant disabled; run scripts/run_native_rust_fusion_invariant.py")
        return 2

    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    evidence_dir = repo_root / "evidence" / "release"
    debug_dir = repo_root / "evidence" / "mac_fusion"
    ctx = Ctx(
        repo_root=repo_root,
        contract_path=repo_root / "spec" / "mac_fusion_sub_invariant_contract.json",
        schema_path=repo_root / "scripts" / "mac_fusion_sub_invariant_schema.json",
        evidence_dir=evidence_dir,
        run_id=run_id,
        hb_path=evidence_dir / f"MAC_FUSION_SUB_INVARIANT_{run_id}.jsonl",
        final_path=evidence_dir / f"MAC_FUSION_SUB_INVARIANT_{run_id}.json",
        latest_path=evidence_dir / "MAC_FUSION_SUB_INVARIANT_latest.json",
        debug_dir=debug_dir,
        debug_hb_path=debug_dir / f"MAC_FUSION_SUB_HEARTBEAT_{run_id}.jsonl",
        debug_final_path=debug_dir / f"MAC_FUSION_SUB_RESULT_{run_id}.json",
        debug_latest_path=debug_dir / "LATEST_MAC_FUSION_RESULT.json",
    )
    finished = False

    def death_handler(sig: int, _frame: Any) -> None:
        nonlocal finished
        if not finished:
            append_hb(ctx, {"gate": "done", "terminal": "Death", "signal": sig})
            write_final(ctx, "Death", {"reason": "process_exit_before_terminal_receipt", "signal": sig})
        raise SystemExit(2)

    signal.signal(signal.SIGINT, death_handler)
    signal.signal(signal.SIGTERM, death_handler)

    try:
        contract = validate_contract(ctx)
    except Exception as e:  # noqa: BLE001
        append_hb(ctx, {"gate": "dmgArtifactGate", "terminal": "REFUSED", "last_error": str(e)})
        write_final(ctx, "REFUSED", {"reason": "contract_invalid", "error": str(e)})
        finished = True
        return 1

    if args.validate_contract_only:
        append_hb(ctx, {"gate": "dmgArtifactGate", "contract_valid": True, "contract_path": str(ctx.contract_path)})
        write_final(
            ctx,
            INVARIANT_EXIT_TERMINAL,
            {
                "mode": "validate_contract_only",
                "contract_path": str(ctx.contract_path),
                "schema_path": str(ctx.schema_path),
            },
        )
        finished = True
        return 0

    thresholds = contract.get("thresholds", {})
    max_age_sec = int(thresholds.get("mooring_file_max_age_sec", 86400))
    min_png_bytes = int(thresholds.get("png_min_bytes", 10000))
    min_dom_bytes = int(thresholds.get("dom_snapshot_min_bytes", 2000))
    max_cycles = max(1, int(args.max_cycles if args.max_cycles is not None else args.outer_max_cycles))
    cycle_results: list[dict[str, Any]] = []
    gate_results: list[dict[str, Any]] = []
    for outer_cycle in range(1, max_cycles + 1):
        gate_results = []
        dmg_path_for_mount: str | None = None
        failed_gate: str | None = None
        failed_witness: dict[str, Any] | None = None
        failed_blocker: str | None = None
        for i, gate in enumerate(GATES[:-1], start=1):
            t0 = time.perf_counter()
            if gate == "fusionControlAppBuildTestGate":
                ok, witness, blocker = gate_fusion_control_app_build_test(ctx)
            elif gate == "fusionPlasmaAppBuildGate":
                ok, witness, blocker = gate_fusion_plasma_app_build(ctx)
            elif gate == "dmgArtifactGate":
                ok, witness, blocker = gate_dmg_artifact(ctx)
                if ok:
                    dmg_path_for_mount = witness.get("dmg_path")
            elif gate == "dmgMountGate":
                ok, witness, blocker = gate_dmg_mount(ctx, dmg_path_for_mount)
            elif gate == "outerRebuildRedeployGate":
                ok, witness, blocker = gate_rebuild_redeploy(ctx)
            elif gate == "macInstallWitnessGate":
                ok, witness, blocker = gate_install_witness(ctx)
            elif gate == "swiftRuntimeGate":
                ok, witness, blocker = gate_swift_runtime(ctx)
            elif gate == "sidecarControlSurfaceGate":
                ok, witness, blocker = gate_sidecar_control_surface(ctx)
            elif gate == "macMooringFilesGate":
                ok, witness, blocker = gate_mooring_files(ctx, max_age_sec)
            elif gate == "fusionMacVisualGate":
                ok, witness, blocker = gate_visual(ctx, min_png_bytes, min_dom_bytes)
            elif gate == "outerOpsAdminGate":
                ok, witness, blocker = gate_ops_admin(ctx)
            elif gate == "teamReadinessProofGate":
                ok, witness, blocker = gate_team_readiness_proof(ctx)
            else:
                ok, witness, blocker = gate_parity(ctx)
            row = {
                "outer_cycle": outer_cycle,
                "cycle": i,
                "gate": gate,
                "elapsed_ms": (time.perf_counter() - t0) * 1000.0,
                "last_witness": witness,
            }
            gate_results.append({"gate": gate, "ok": ok, "witness": witness, "blocker": blocker})
            write_gate_witness(ctx, gate, ok, witness, blocker)
            if ok:
                append_hb(ctx, row)
                continue
            failed_gate = gate
            failed_witness = witness
            failed_blocker = blocker
            if blocker:
                row["terminal"] = "BLOCKED"
                row["blocker_reason"] = blocker
                append_hb(ctx, row)
                write_final(ctx, "BLOCKED", {"failed_gate": gate, "blocker_reason": blocker, "gate_results": gate_results})
                finished = True
                return 2
            # Gate-level cure: self-heal immediately, then re-check the same gate once.
            row["terminal"] = "PARTIAL"
            row["last_error"] = witness.get("reason", "invariant_violation")
            append_hb(ctx, row)
            heal = outer_self_heal(ctx, gate)
            append_hb(
                ctx,
                {
                    "gate": "outerSelfHealGate",
                    "outer_cycle": outer_cycle,
                    "phase": "immediate_gate_repair",
                    "last_witness": heal,
                    "terminal": "PARTIAL",
                },
            )
            cycle_results.append(
                {
                    "outer_cycle": outer_cycle,
                    "failed_gate": gate,
                    "failed_reason": witness.get("reason", "invariant_violation"),
                    "self_heal": heal,
                }
            )
            # re-run same gate deterministically
            t1 = time.perf_counter()
            if gate == "fusionControlAppBuildTestGate":
                ok2, witness2, blocker2 = gate_fusion_control_app_build_test(ctx)
            elif gate == "fusionPlasmaAppBuildGate":
                ok2, witness2, blocker2 = gate_fusion_plasma_app_build(ctx)
            elif gate == "dmgArtifactGate":
                ok2, witness2, blocker2 = gate_dmg_artifact(ctx)
                if ok2:
                    dmg_path_for_mount = witness2.get("dmg_path")
            elif gate == "dmgMountGate":
                ok2, witness2, blocker2 = gate_dmg_mount(ctx, dmg_path_for_mount)
            elif gate == "outerRebuildRedeployGate":
                ok2, witness2, blocker2 = gate_rebuild_redeploy(ctx)
            elif gate == "macInstallWitnessGate":
                ok2, witness2, blocker2 = gate_install_witness(ctx)
            elif gate == "swiftRuntimeGate":
                ok2, witness2, blocker2 = gate_swift_runtime(ctx)
            elif gate == "sidecarControlSurfaceGate":
                ok2, witness2, blocker2 = gate_sidecar_control_surface(ctx)
            elif gate == "macMooringFilesGate":
                ok2, witness2, blocker2 = gate_mooring_files(ctx, max_age_sec)
            elif gate == "fusionMacVisualGate":
                ok2, witness2, blocker2 = gate_visual(ctx, min_png_bytes, min_dom_bytes)
            elif gate == "outerOpsAdminGate":
                ok2, witness2, blocker2 = gate_ops_admin(ctx)
            elif gate == "teamReadinessProofGate":
                ok2, witness2, blocker2 = gate_team_readiness_proof(ctx)
            else:
                ok2, witness2, blocker2 = gate_parity(ctx)
            retry_row = {
                "outer_cycle": outer_cycle,
                "cycle": i,
                "gate": gate,
                "phase": "post_heal_recheck",
                "elapsed_ms": (time.perf_counter() - t1) * 1000.0,
                "last_witness": witness2,
            }
            gate_results[-1] = {"gate": gate, "ok": ok2, "witness": witness2, "blocker": blocker2}
            write_gate_witness(ctx, gate, ok2, witness2, blocker2)
            if ok2:
                retry_row["terminal"] = INVARIANT_EXIT_TERMINAL
                append_hb(ctx, retry_row)
                failed_gate = None
                failed_witness = None
                failed_blocker = None
                continue
            if blocker2:
                retry_row["terminal"] = "BLOCKED"
                retry_row["blocker_reason"] = blocker2
                append_hb(ctx, retry_row)
                write_final(ctx, "BLOCKED", {"failed_gate": gate, "blocker_reason": blocker2, "gate_results": gate_results})
                finished = True
                return 2
            retry_row["terminal"] = "REFUSED"
            retry_row["last_error"] = witness2.get("reason", "invariant_violation")
            append_hb(ctx, retry_row)
            break

        if failed_gate is None:
            break
        # failed even after immediate repair-recheck: broken for this run
        break
    else:
        write_final(
            ctx,
            "REFUSED",
            {
                "reason": "outer_self_heal_budget_exhausted",
                "outer_max_cycles": max_cycles,
                "cycle_results": cycle_results,
                "gate_results": gate_results,
            },
        )
        finished = True
        return 1

    if failed_gate is not None:
        write_final(
            ctx,
            "REFUSED",
            {
                "reason": "gate_failed_after_self_heal_recheck",
                "failed_gate": failed_gate,
                "failed_witness": failed_witness or {},
                "gate_results": gate_results,
                "outer_heal_cycles": cycle_results,
            },
        )
        finished = True
        return 1

    append_hb(
        ctx,
        {
            "gate": "subSealingGate",
            "last_witness": {
                "final_receipt_path": str(ctx.final_path),
                "heartbeat_jsonl_path": str(ctx.hb_path),
                "terminal_line": f"STATE: {INVARIANT_EXIT_TERMINAL}",
            },
        },
    )
    write_final(
        ctx,
        INVARIANT_EXIT_TERMINAL,
        {"gate_results": gate_results, "completed_gates": GATES, "outer_heal_cycles": cycle_results, "outer_max_cycles": max_cycles},
    )
    append_hb(ctx, {"gate": "done", "terminal": INVARIANT_EXIT_TERMINAL})
    finished = True
    print(f"STATE: {INVARIANT_EXIT_TERMINAL}")
    print(f"Receipt: {ctx.final_path}")
    print(f"Debug heartbeat: {ctx.debug_hb_path}")
    print(f"Debug latest: {ctx.debug_latest_path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SystemExit:
        raise
    except Exception as e:  # noqa: BLE001
        # Last-resort explicit Death receipt attempt.
        try:
            repo = Path(__file__).resolve().parents[1]
            ev = repo / "evidence" / "release"
            ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
            fallback = ev / f"MAC_FUSION_SUB_INVARIANT_{ts}_death.json"
            ev.mkdir(parents=True, exist_ok=True)
            fallback.write_text(
                json.dumps(
                    {
                        "schema": "gaiaftcl_mac_fusion_sub_invariant_receipt_v1",
                        "terminal": "Death",
                        "error": f"{type(e).__name__}: {e}",
                        "ts_utc": utc_now(),
                    },
                    indent=2,
                ),
                encoding="utf-8",
            )
        except Exception:
            pass
        raise
