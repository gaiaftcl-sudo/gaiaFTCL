#!/usr/bin/env python3
"""Autonomous local loop for GaiaFusion embedded WASM UI closure.

Contract:
- Detect blank/white-screen states deterministically.
- Run an MCP "conversation" turn about current local UI state (optional when relaxed).
- Apply healing ladder with receipts.
- Exit CALORIE on closure, REFUSED on bounded failure.

Host Docker vs FusionSidecar VM:
- Default: ``127.0.0.1:8803`` must answer (Mac full cell or bridge to guest Docker).
- ``FUSION_UI_SELF_HEAL_RELAX_MAC_GATEWAY=1`` or ``FUSION_UI_SELF_HEAL_IN_APP_SIDECAR=1``: do not fail the
  diagnostic on missing host ``:8803``; do not require a successful MCP HTTP round-trip for CALORIE streak
  (Docker/MCP live in the Linux guest; host may have no daemon). Receipts mark ``relaxed_skip`` / ``gateway_reachable``.
  Unless ``FUSION_UI_SELF_HEAL_MODE`` is set, relaxed runs default to ``light`` (``soft_reprobe`` only) so the ladder
  does not invoke ``run_fusion_mac_app_gate.py`` (long-running). Set ``FUSION_UI_SELF_HEAL_MODE=full`` when you intend
  composite rebuild + app gate.
- ``restart_sidecar`` is skipped with exit-0 witness when ``docker info`` is unavailable on the host.

Env:
- ``FUSION_UI_SELF_HEAL_RELAX_MAC_GATEWAY``, ``FUSION_UI_SELF_HEAL_IN_APP_SIDECAR`` (either =1)
- ``FUSION_UI_SELF_HEAL_SKIP_MCP=1`` — skip MCP POST entirely (telemetry-only)
- Existing: ``FUSION_UI_PORT``, ``FUSION_UI_SELF_HEAL_MAX_CYCLES``, ``FUSION_UI_SELF_HEAL_MODE``, etc.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def get_env_int(name: str, default: int) -> int:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    try:
        val = int(raw)
        return val
    except ValueError:
        return default


def env_bool(name: str, default: bool = False) -> bool:
    raw = os.environ.get(name, "").strip().lower()
    if not raw:
        return default
    return raw in ("1", "true", "yes", "on")


@dataclass
class LoopCfg:
    root: Path
    ui_port: int
    max_cycles: int
    sleep_sec: int
    wallet: str
    heal_mode: str
    stable_required: int
    relax_mac_gateway: bool
    skip_mcp: bool


def load_ui_audit_spec(root: Path) -> dict[str, Any]:
    path = root / "spec" / "native_fusion" / "fusion_ui_component_audit.json"
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(raw, dict):
            raw["_path"] = str(path)
            return raw
    except Exception:
        pass
    return {
        "schema": "gaiaftcl_fusion_ui_component_audit_v1",
        "_path": str(path),
        "must_present_markers": [],
        "blocked_markers_when_active": [],
        "purpose": {},
    }


def fetch_json(url: str, timeout: float = 8.0) -> tuple[bool, int, Any, str]:
    req = urllib.request.Request(url, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            code = int(resp.status)
            raw = resp.read().decode("utf-8", errors="replace")
            try:
                data = json.loads(raw)
            except json.JSONDecodeError:
                return False, code, None, raw[:1200]
            return True, code, data, raw[:1200]
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode("utf-8", errors="replace")
        except Exception:
            body = str(e)
        return False, int(e.code), None, body[:1200]
    except Exception as e:  # noqa: BLE001
        return False, 0, None, str(e)


def fetch_text(url: str, timeout: float = 8.0) -> tuple[bool, int, str]:
    req = urllib.request.Request(url, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            code = int(resp.status)
            raw = resp.read().decode("utf-8", errors="replace")
            return True, code, raw
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode("utf-8", errors="replace")
        except Exception:
            body = str(e)
        return False, int(e.code), body
    except Exception as e:  # noqa: BLE001
        return False, 0, str(e)


def run_cmd(command: list[str], cwd: Path, timeout: int = 900) -> dict[str, Any]:
    try:
        proc = subprocess.run(
            command,
            cwd=str(cwd),
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout,
        )
        out = proc.stdout or ""
        return {
            "command": " ".join(command),
            "rc": proc.returncode,
            "stdout_tail": "\n".join(out.splitlines()[-120:]),
            "ok": proc.returncode == 0,
        }
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or "") if isinstance(e.stdout, str) else ""
        return {
            "command": " ".join(command),
            "rc": 124,
            "stdout_tail": "\n".join(out.splitlines()[-120:]),
            "ok": False,
            "reason": "timeout",
        }
    except Exception as e:  # noqa: BLE001
        return {
            "command": " ".join(command),
            "rc": 1,
            "stdout_tail": str(e),
            "ok": False,
            "reason": "exception",
        }


def audit_fusion_components(html: str, spec: dict[str, Any]) -> dict[str, Any]:
    must = [str(x) for x in spec.get("must_present_markers", []) if isinstance(x, str)]
    blocked = [str(x) for x in spec.get("blocked_markers_when_active", []) if isinstance(x, str)]
    present = [m for m in must if m in html]
    missing = [m for m in must if m not in html]
    blocked_hits = [b for b in blocked if b in html]
    splash_detected = len(blocked_hits) > 0 and "fusion-active-composite" not in present
    return {
        "schema": "gaiaftcl_fusion_ui_component_audit_result_v1",
        "spec_schema": spec.get("schema"),
        "spec_path": spec.get("_path"),
        "present_markers": present,
        "missing_markers": missing,
        "blocked_hits": blocked_hits,
        "splash_detected": splash_detected,
        "active_surface_ok": len(missing) == 0 and len(blocked_hits) == 0,
    }


def diagnostic_contract(
    ui_port: int,
    ui_spec: dict[str, Any],
    *,
    relax_mac_gateway: bool = False,
) -> dict[str, Any]:
    base = f"http://127.0.0.1:{ui_port}"
    checks: list[dict[str, Any]] = []

    ok_h, code_h, health, raw_h = fetch_json(f"{base}/api/fusion/health")
    usd = health.get("usd_px") if isinstance(health, dict) else None
    usd_ok = (
        isinstance(usd, dict)
        and isinstance(usd.get("pxr_version_int"), int)
        and int(usd.get("pxr_version_int", 0)) > 0
        and usd.get("in_memory_stage") is True
        and usd.get("plant_control_viewport_prim") is True
    )
    health_ok = (
        ok_h
        and code_h == 200
        and isinstance(health, dict)
        and health.get("status") == "ok"
        and bool(health.get("wasm_runtime_closed")) is True
        and bool(health.get("klein_bottle_closed")) is True
        and usd_ok
    )
    checks.append(
        {
            "id": "fusion_health_contract",
            "pass": health_ok,
            "http_code": code_h,
            "reason": "" if health_ok else "fusion_health_contract_failed",
            "hint": "run_fusion_mac_app_gate.py --port <ui_port> to restore runtime witness",
            "sample": health if isinstance(health, dict) else raw_h,
        }
    )

    ok_p, code_p, self_probe, raw_p = fetch_json(f"{base}/api/fusion/self-probe")
    dom_count = 0
    if isinstance(self_probe, dict):
        dom = self_probe.get("dom_analysis")
        if isinstance(dom, dict):
            try:
                dom_count = int(dom.get("document_element_count", 0))
            except Exception:
                dom_count = 0
    self_probe_ok = (
        ok_p
        and code_p == 200
        and isinstance(self_probe, dict)
        and self_probe.get("terminal") == "CURE"
        and dom_count > 50
    )
    checks.append(
        {
            "id": "self_probe_dom_contract",
            "pass": self_probe_ok,
            "http_code": code_p,
            "reason": "" if self_probe_ok else "self_probe_dom_contract_failed",
            "hint": "restart GaiaFusion and ensure WKWebView bridge is loaded",
            "sample": self_probe if isinstance(self_probe, dict) else raw_p,
        }
    )

    ok_s, code_s, substrate_html = fetch_text(f"{base}/substrate?telemetryPort=8803")
    substrate_ok = (
        ok_s
        and code_s == 200
        and len(substrate_html) > 300
    )
    checks.append(
        {
            "id": "substrate_html_contract",
            "pass": substrate_ok,
            "http_code": code_s,
            "reason": "" if substrate_ok else "substrate_html_contract_failed",
            "hint": "rebuild composite assets and verify fusion-web mirror includes substrate route",
            "sample": substrate_html[:600],
        }
    )

    ok_sr, code_sr, substrate_raw_html = fetch_text(f"{base}/substrate-raw")
    substrate_raw_ok = (
        ok_sr
        and code_sr == 200
        and isinstance(substrate_raw_html, str)
        and 'data-testid="substrate-raw-main"' in substrate_raw_html
        and "fusion-s4-main" not in substrate_raw_html[:5000]
    )
    checks.append(
        {
            "id": "substrate_raw_routing_contract",
            "pass": substrate_raw_ok,
            "http_code": code_sr,
            "reason": "" if substrate_raw_ok else "substrate_raw_routing_contract_failed",
            "hint": "must serve substrate-raw.html (not fusion-s4 index) to avoid iframe recursion; see LocalServer / fusion-web",
            "sample": (substrate_raw_html or "")[:500],
        }
    )

    ok_f, code_f, fusion_html = fetch_text(f"{base}/fusion-s4")
    ui_audit = audit_fusion_components(fusion_html if isinstance(fusion_html, str) else "", ui_spec)
    ok_proj, code_proj, projection_json, raw_proj = fetch_json(f"{base}/api/fusion/s4-projection")
    projection_ok = (
        ok_proj
        and code_proj == 200
        and isinstance(projection_json, dict)
        and str(projection_json.get("schema", "")).startswith("gaiaftcl_fusion_s4_projection")
    )
    ok_bridge, code_bridge, bridge_json, raw_bridge = fetch_json(f"{base}/api/fusion/bridge-status")
    webview_loaded = isinstance(bridge_json, dict) and bridge_json.get("webview_loaded") is True
    cm = projection_json.get("control_matrix") if isinstance(projection_json, dict) else None
    trace_active = isinstance(cm, dict) and cm.get("trace_active") is True
    operator_surface_ok = (not webview_loaded) or trace_active
    checks.append(
        {
            "id": "operator_surface_armed_contract",
            "pass": operator_surface_ok,
            "http_code": code_bridge,
            "reason": "" if operator_surface_ok else "operator_surface_armed_contract_failed",
            "hint": "when WKWebView is loaded, s4-projection must arm control_matrix.trace_active (webview gate, not only SwiftUI trace chrome)",
            "sample": {
                "webview_loaded": webview_loaded,
                "trace_active": trace_active,
                "bridge": bridge_json if isinstance(bridge_json, dict) else raw_bridge,
            },
        }
    )
    fusion_ok = (
        ok_f
        and code_f == 200
        and len(fusion_html) > 1200
        and projection_ok
    )
    checks.append(
        {
            "id": "fusion_html_contract",
            "pass": fusion_ok,
            "http_code": code_f,
            "reason": "" if fusion_ok else "fusion_html_contract_failed",
            "hint": "ensure fusion-s4 UI and /api/fusion/s4-projection are both healthy; runtime splash/active state is enforced by Playwright gate",
            "sample": {
                "fusion_html_head": fusion_html[:300],
                "projection_http_code": code_proj,
                "projection_sample": projection_json if isinstance(projection_json, dict) else raw_proj,
                "component_audit": ui_audit,
            },
        }
    )

    ok_m, code_m, mac_probe, raw_m = fetch_json(
        "http://127.0.0.1:8803/health", timeout=6.0
    )
    mac_actually_ok = ok_m and code_m == 200
    mac_probe_ok = mac_actually_ok or relax_mac_gateway
    checks.append(
        {
            "id": "mac_gateway_health_contract",
            "pass": mac_probe_ok,
            "http_code": code_m,
            "reason": ""
            if mac_probe_ok
            else "mac_gateway_health_contract_failed",
            "hint": "restart fusion sidecar stack (docker-compose.fusion-sidecar.yml) or set "
            "FUSION_UI_SELF_HEAL_RELAX_MAC_GATEWAY=1 when Docker/MCP runs in FusionSidecar guest only",
            "gateway_reachable": mac_actually_ok,
            "relaxed_skip": bool(relax_mac_gateway and not mac_actually_ok),
            "sample": mac_probe if isinstance(mac_probe, dict) else raw_m,
        }
    )

    passed = all(bool(c["pass"]) for c in checks)
    fail_ids = [c["id"] for c in checks if not c["pass"]]
    return {
        "schema": "gaiaftcl_fusion_blank_screen_contract_v1",
        "pass": passed,
        "fail_ids": fail_ids,
        "ui_component_audit": ui_audit,
        "checks": checks,
    }


def mcp_conversation_turn(cfg: LoopCfg, contract: dict[str, Any], ui_port: int) -> dict[str, Any]:
    url = "http://127.0.0.1:8803/mcp/execute"
    payload = {
        "name": "closure_game_report_v1",
        "params": {
            "ui_contract": contract.get("schema"),
            "ui_failures": contract.get("fail_ids", []),
            "ui_port": ui_port,
            "ui_component_audit": contract.get("ui_component_audit"),
            "operator_prompt": "What do you believe you are showing in the local fusion UI right now? If splash/mooring, propose exact repair action.",
            "requested_action": "diagnose_and_propose_fix_patch",
        },
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        method="POST",
        data=data,
        headers={
            "Content-Type": "application/json",
            "X-Environment-ID": "local",
            "X-Wallet-Address": cfg.wallet,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=15.0) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            parsed = json.loads(body)
            return {
                "ok": True,
                "http_code": int(resp.status),
                "request": payload,
                "response": parsed,
            }
    except urllib.error.HTTPError as e:
        err = ""
        try:
            err = e.read().decode("utf-8", errors="replace")
        except Exception:
            err = str(e)
        return {
            "ok": False,
            "http_code": int(e.code),
            "request": payload,
            "error": err[:1600],
        }
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "http_code": 0, "request": payload, "error": str(e)}


def run_healing_step(cfg: LoopCfg, step: str, ui_port: int) -> dict[str, Any]:
    if step == "soft_reprobe":
        return run_cmd(["bash", "scripts/gaiafusion_internal_cli.sh", str(ui_port)], cfg.root, timeout=90)
    if step == "restart_sidecar":
        if env_bool("FUSION_UI_SELF_HEAL_SKIP_DOCKER_RESTART"):
            return {
                "command": "restart_sidecar",
                "ok": True,
                "rc": 0,
                "stdout_tail": "SKIP: FUSION_UI_SELF_HEAL_SKIP_DOCKER_RESTART=1",
            }
        try:
            pre = subprocess.run(
                ["docker", "info"],
                cwd=str(cfg.root),
                capture_output=True,
                text=True,
                timeout=12,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            return {
                "command": "docker info (preflight)",
                "ok": True,
                "rc": 0,
                "stdout_tail": f"SKIP restart_sidecar: docker unavailable ({exc!r}); "
                "sidecar may run inside FusionSidecar VM — start guest compose + bridge :8803 from the app.",
            }
        if pre.returncode != 0:
            tail = (pre.stderr or pre.stdout or "")[-800:]
            return {
                "command": "docker info (preflight)",
                "ok": True,
                "rc": 0,
                "stdout_tail": "SKIP restart_sidecar: host docker daemon not reachable. " + tail,
            }
        return run_cmd(
            ["docker", "compose", "-f", "docker-compose.fusion-sidecar.yml", "up", "-d", "--build"],
            cfg.root,
            timeout=1200,
        )
    if step == "rebuild_composite":
        return run_cmd(["bash", "scripts/build_gaiafusion_composite_assets.sh"], cfg.root, timeout=2400)
    if step == "rebuild_wasm":
        return run_cmd(["bash", "scripts/build_gaiafusion_wasm_pack.sh"], cfg.root, timeout=1200)
    if step == "restart_app_gate":
        return run_cmd(
            [
                "python3",
                "scripts/run_fusion_mac_app_gate.py",
                "--root",
                str(cfg.root),
                "--skip-composite-assets",
            ],
            cfg.root,
            timeout=2400,
        )
    return {"command": step, "ok": False, "rc": 1, "stdout_tail": "unknown_step"}


def healing_ladder(cfg: LoopCfg) -> list[str]:
    mode = cfg.heal_mode.lower()
    if mode == "light":
        return ["soft_reprobe"]
    if mode == "medium":
        return ["soft_reprobe", "restart_sidecar", "rebuild_wasm", "restart_app_gate"]
    return ["soft_reprobe", "restart_sidecar", "rebuild_wasm", "rebuild_composite", "restart_app_gate"]


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    ev = root / "evidence" / "fusion_control"
    ev.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    jsonl_path = ev / f"fusion_ui_self_heal_loop_{ts}.jsonl"
    receipt_path = ev / f"fusion_ui_self_heal_loop_receipt_{ts}.json"

    relax_gw = env_bool("FUSION_UI_SELF_HEAL_RELAX_MAC_GATEWAY") or env_bool(
        "FUSION_UI_SELF_HEAL_IN_APP_SIDECAR"
    )
    skip_mcp_env = env_bool("FUSION_UI_SELF_HEAL_SKIP_MCP")
    mode_env = os.environ.get("FUSION_UI_SELF_HEAL_MODE", "").strip()
    if mode_env:
        heal_mode_resolved = mode_env
    elif relax_gw:
        # Avoid restart_app_gate / long rebuilds unless operator sets MODE explicitly (can exceed 30+ min).
        heal_mode_resolved = "light"
    else:
        heal_mode_resolved = "full"
    cfg = LoopCfg(
        root=root,
        ui_port=get_env_int("FUSION_UI_PORT", 8910),
        max_cycles=max(1, get_env_int("FUSION_UI_SELF_HEAL_MAX_CYCLES", 4)),
        sleep_sec=max(1, get_env_int("FUSION_UI_SELF_HEAL_SLEEP_SEC", 3)),
        wallet=os.environ.get("MCP_FEED_WALLET", "").strip() or "0xgaiaftcl_internal_feed_readonly",
        heal_mode=heal_mode_resolved,
        stable_required=max(1, get_env_int("FUSION_UI_STABLE_REQUIRED", 2)),
        relax_mac_gateway=relax_gw,
        skip_mcp=skip_mcp_env,
    )

    history: list[dict[str, Any]] = []
    seen_sig: dict[str, int] = {}
    terminal = "REFUSED"
    reason = "max_cycles_exhausted"
    current_port = cfg.ui_port
    ui_spec = load_ui_audit_spec(root)
    stable_streak = 0

    for cycle in range(1, cfg.max_cycles + 1):
        row: dict[str, Any] = {
            "ts_utc": utc_now(),
            "cycle": cycle,
            "ui_port": current_port,
            "heal_mode": cfg.heal_mode,
        }
        # MCP turn (optional when relaxed / skipped): ask substrate what UI it believes is being shown.
        if cfg.skip_mcp:
            convo = {
                "ok": True,
                "http_code": 200,
                "skipped": True,
                "note": "FUSION_UI_SELF_HEAL_SKIP_MCP=1",
                "request": {},
                "response": {},
            }
        else:
            convo = mcp_conversation_turn(
                cfg,
                {
                    "schema": "gaiaftcl_fusion_blank_screen_contract_v1",
                    "fail_ids": ["pre_diagnostic_mcp_first"],
                    "ui_component_audit": {},
                },
                current_port,
            )
        row["mcp_conversation"] = convo
        contract = diagnostic_contract(current_port, ui_spec, relax_mac_gateway=cfg.relax_mac_gateway)
        row["contract"] = contract
        # Persist MCP response for audit/repair trace each cycle.
        mcp_fix_path = ev / f"fusion_ui_self_heal_mcp_turn_cycle{cycle}_{ts}.json"
        mcp_fix_path.write_text(json.dumps(convo, indent=2), encoding="utf-8")
        row["mcp_turn_receipt"] = str(mcp_fix_path.relative_to(root))

        convo_attempted = int(convo.get("http_code", 0)) > 0
        mcp_ok_for_closure = (
            convo_attempted
            or cfg.relax_mac_gateway
            or cfg.skip_mcp
            or convo.get("skipped") is True
        )
        if contract.get("pass") and mcp_ok_for_closure:
            stable_streak += 1
            row["stable_streak"] = stable_streak
            if stable_streak >= cfg.stable_required:
                row["terminal"] = "CALORIE"
                history.append(row)
                terminal = "CALORIE"
                reason = "stable_mode_closed"
                with jsonl_path.open("a", encoding="utf-8") as f:
                    f.write(json.dumps(row) + "\n")
                break
        else:
            stable_streak = 0

        fail_sig = ",".join(contract.get("fail_ids", [])) + f"|mcp:{convo.get('http_code', 0)}"
        seen_sig[fail_sig] = seen_sig.get(fail_sig, 0) + 1
        row["failure_signature"] = fail_sig
        ui_audit = contract.get("ui_component_audit")
        if isinstance(ui_audit, dict):
            if ui_audit.get("splash_detected") is True:
                row["ui_state_assertion"] = "bad_surface_splash_mooring_detected"
            elif ui_audit.get("active_surface_ok") is True:
                row["ui_state_assertion"] = "active_surface_detected"

        heals: list[dict[str, Any]] = []
        for step in healing_ladder(cfg):
            res = run_healing_step(cfg, step, current_port)
            heals.append({"step": step, **res})
            if step == "restart_app_gate" and res.get("ok"):
                try:
                    gate_receipt = json.loads(
                        (cfg.root / "evidence" / "fusion_control" / "fusion_mac_app_gate_receipt.json").read_text(
                            encoding="utf-8"
                        )
                    )
                    wit = gate_receipt.get("witness") if isinstance(gate_receipt, dict) else None
                    if isinstance(wit, dict):
                        p = wit.get("fusion_ui_port")
                        if isinstance(p, int) and p > 0:
                            current_port = p
                            row["ui_port_updated_to"] = p
                except Exception:
                    pass
            if res.get("ok") is False and step == "soft_reprobe":
                # keep going through ladder
                continue
        row["healing"] = heals

        history.append(row)
        with jsonl_path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(row) + "\n")

        if seen_sig[fail_sig] >= 3:
            if isinstance(ui_audit, dict) and ui_audit.get("splash_detected") is True:
                reason = f"splash_mooring_stuck:{fail_sig}"
            else:
                reason = f"repeated_failure_signature:{fail_sig}"
            break

        time.sleep(cfg.sleep_sec)

    receipt = {
        "schema": "gaiaftcl_fusion_ui_self_heal_loop_receipt_v1",
        "ts_utc": utc_now(),
        "terminal": terminal,
        "reason": reason,
        "cycles_attempted": len(history),
        "max_cycles": cfg.max_cycles,
        "ui_port": cfg.ui_port,
        "heal_mode": cfg.heal_mode,
        "relax_mac_gateway": cfg.relax_mac_gateway,
        "skip_mcp": cfg.skip_mcp,
        "conversation_wallet": cfg.wallet,
        "jsonl": str(jsonl_path.relative_to(root)),
        "last_cycle": history[-1] if history else None,
        "failure_signatures": seen_sig,
        "ui_component_audit_spec_path": ui_spec.get("_path"),
    }
    if reason == "max_cycles_exhausted" and history:
        last_contract = history[-1].get("contract")
        if isinstance(last_contract, dict):
            last_audit = last_contract.get("ui_component_audit")
            if isinstance(last_audit, dict) and last_audit.get("splash_detected") is True:
                reason = "splash_mooring_stuck:max_cycles_exhausted"
                receipt["reason"] = reason
    receipt_path.write_text(json.dumps(receipt, indent=2), encoding="utf-8")
    print(str(receipt_path))
    if terminal != "CALORIE":
        print(f"REFUSED: fusion_ui_self_heal_loop reason={reason}")
        return 1
    print("CALORIE: fusion_ui_self_heal_loop closed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
