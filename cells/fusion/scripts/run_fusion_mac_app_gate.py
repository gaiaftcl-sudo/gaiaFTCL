#!/usr/bin/env python3
"""Single gate invariant: composite assets (Metal + fusion-web mirror) → build GaiaFusion → runtime probes + Playwright.

Default gate build is **SwiftPM-only** (``Package.swift``); ``xcodebuild`` is opt-in via ``GAIAFUSION_GATE_USE_XCODE=1``.
After ``swift build``, the gate patches the debug Mach-O with the same ``@executable_path/../Frameworks`` rpath as
``package_gaiafusion_app.sh``, and ``find_binary`` no longer prefers a stale Xcode DerivedData ``.app`` (dyld failure /
projection timeout). Optional: ``GAIAFUSION_GATE_APP_BUNDLE=/path/to/GaiaFusion.app`` to run the packaged artifact.
Optional: ``GAIAFUSION_GATE_SKIP_SWIFT_BUILD=1`` with ``GAIAFUSION_GATE_APP_BUNDLE`` set to skip redundant ``swift build``
when probing a pre-built ``dist/GaiaFusion.app`` only. On host Mac, ``enforce_host_c4_lock`` clears those bundle vars unless
``GAIAFUSION_ALLOW_STALE_GATE_BUNDLE=1``. If the SwiftPM debug child is **SIGKILL** (-9) before TCP bind (receipt:
``child_exited_before_listen:rc=-9``), re-run against a codesigned packaged ``.app`` (e.g. ``/tmp/gaiafusion-delivery/GaiaFusion.app``
from ``build_gaiafusion_release.sh``) with the three vars above.

Self-probe / Phase 4 kinematic gate (after openusd): for **each** of the nine canonical ``PlantKindsCatalog`` kinds, the gate
**POST**s ``/api/fusion/gate/load-viewport-plant``, waits for ``swap_lifecycle==VERIFIED``, **POST**s
``/api/fusion/gate/engage-viewport``, then polls ``/api/fusion/openusd-playback`` until ``normalized_t`` is observed in
three bands ([0,0.33), [0.33,0.66), [0.66,1]) with ``frames_presented>0``. Artifact:
``evidence/fusion_control/gaiafusion_kinematic_gate_receipt.json``. Refuses if
``GAIAFUSION_GATE_OPENUSD_HEADLESS_OK=1``. Skip entire self-probe block with ``GAIAFUSION_GATE_SKIP_SELF_PROBE=1`` (CI only).

On import: `enforce_host_c4_lock()` clears toxic GAIAFUSION_SKIP_* on Apple Silicon host Mac (non-CI), matching
`scripts/lib/gaiafusion_host_c4_lock.sh`. Opt out: GAIAFUSION_ALLOW_SKIP_ON_HOST=1.

Child process: `start_app` sets ``MTL_DISABLE_COMPILED_CODE_CACHE`` and ``CI_DISABLE_FSCache`` (via ``setdefault``)
unless already present, to reduce Metal/CoreImage on-disk shader cache contention in CI/headless runs.

After ``Popen``, the gate waits until ``127.0.0.1:FUSION_UI_PORT`` accepts TCP (default **90s**, override
``GAIAFUSION_GATE_LISTEN_TIMEOUT_SEC``) before HTTP probes — REFUSED ``loopback_tcp_never_bound`` if the app never binds.
"""

from __future__ import annotations

import argparse
import http.client
import json
import os
import platform
import re
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, BinaryIO


def enforce_host_c4_lock() -> None:
    """Strip toxic GAIAFUSION_SKIP_* / probe-SIGKILL env on Apple Silicon host Mac (matches scripts/lib/gaiafusion_host_c4_lock.sh)."""
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        return
    ci_markers = ("CI", "GITHUB_ACTIONS", "GITLAB_CI")
    if any(os.environ.get(k) for k in ci_markers):
        return
    if os.environ.get("GAIAFUSION_ALLOW_SKIP_ON_HOST") == "1":
        return
    print(
        "[C4] Host Mac arm64 (non-CI): clearing GAIAFUSION_SKIP_* / USD probe SIGKILL workarounds "
        "(set GAIAFUSION_ALLOW_SKIP_ON_HOST=1 to retain).",
        file=sys.stderr,
    )
    for key in (
        "GAIAFUSION_SKIP_WORKING_APP_VERIFY",
        "GAIAFUSION_SKIP_XCTEST",
        "GAIAFUSION_SKIP_MAC_CELL_MCP",
        "GAIAFUSION_SKIP_MESH_MCP",
        "GAIAFUSION_SKIP_USD_PROBE_CLI",
        "GAIAFUSION_USD_PROBE_SIGKILL_OK",
    ):
        os.environ.pop(key, None)
    # Packaged-bundle shortcuts drift from GaiaFusion/Resources (plant timelines, fusion-web). Default: proof against
    # current tree via swift build. Opt back in: GAIAFUSION_ALLOW_STALE_GATE_BUNDLE=1
    if os.environ.get("GAIAFUSION_ALLOW_STALE_GATE_BUNDLE") != "1":
        for _k in ("GAIAFUSION_GATE_SKIP_SWIFT_BUILD", "GAIAFUSION_GATE_APP_BUNDLE"):
            if _k in os.environ:
                os.environ.pop(_k, None)
        print(
            "[C4] Cleared GAIAFUSION_GATE_SKIP_SWIFT_BUILD / GAIAFUSION_GATE_APP_BUNDLE "
            "(set GAIAFUSION_ALLOW_STALE_GATE_BUNDLE=1 to use a packaged .app).",
            file=sys.stderr,
        )


enforce_host_c4_lock()


INVARIANT_ID = "gaiaftcl_fusion_mac_app_gate_v6"
COMPOSITE_SCRIPT = "scripts/build_gaiafusion_composite_assets.sh"
SCHEME = "GaiaFusion"
PROJECT = "GaiaFusion"
BUILD_DIR = "macos/GaiaFusion"
BINARY_NAME = "GaiaFusion"
PORT_DEFAULT = 8910
PROBE_PATH = "/api/fusion/s4-projection"
PLAYWRIGHT_SPEC = "tests/fusion/fusion_mac_wasm_gate.spec.ts"


def gate_use_xcodebuild() -> bool:
    """Default: SwiftPM-only gate (Package.swift). Set GAIAFUSION_GATE_USE_XCODE=1 to run xcodebuild first."""
    if os.environ.get("GAIAFUSION_GATE_USE_XCODE") == "1":
        return True
    # Legacy: GAIAFUSION_GATE_SKIP_XCODE=0 meant "do not skip xcode"
    if os.environ.get("GAIAFUSION_GATE_SKIP_XCODE") == "0":
        return True
    return False


def find_free_tcp_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def gate_listen_timeout_sec() -> float:
    raw = os.environ.get("GAIAFUSION_GATE_LISTEN_TIMEOUT_SEC", "").strip()
    if raw:
        try:
            return max(5.0, float(raw))
        except ValueError:
            pass
    return 90.0


def wait_for_loopback_tcp_accept(
    port: int,
    timeout_sec: float,
    proc: subprocess.Popen[bytes] | None,
) -> tuple[bool, float, str]:
    """Poll until something accepts TCP on 127.0.0.1:port (Swifter bound) or timeout / child exit."""
    t0 = time.monotonic()
    deadline = t0 + timeout_sec
    while time.monotonic() < deadline:
        if proc is not None and proc.poll() is not None:
            rc = proc.returncode
            return False, time.monotonic() - t0, f"child_exited_before_listen:rc={rc}"
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                pass
            return True, time.monotonic() - t0, "tcp_accept_ok"
        except OSError:
            time.sleep(0.2)
    return False, time.monotonic() - t0, "timeout_no_tcp_accept"


@dataclass
class GateContext:
    repo_root: Path
    project_root: Path
    evidence_dir: Path
    run_id: str
    health_port: int
    probe_path: str


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def urlopen_direct(url: str, timeout: float | None = None):
    """``urllib`` honors ``HTTP(S)_PROXY``; localhost probes must bypass proxies or the gate hangs/flakes."""
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    if timeout is not None:
        return opener.open(url, timeout=timeout)
    return opener.open(url)


def run_cmd(cmd: list[str], cwd: Path, timeout: int = 600) -> tuple[int, str]:
    proc = subprocess.run(
        cmd,
        cwd=str(cwd),
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout,
    )
    return proc.returncode, proc.stdout[-12000:]


def should_skip_swift_build_for_packaged_bundle(ctx: GateContext) -> bool:
    """When ``GAIAFUSION_GATE_SKIP_SWIFT_BUILD=1`` and ``GAIAFUSION_GATE_APP_BUNDLE`` resolves to an executable, skip
    ``swift build`` and probe that artifact only (avoids long redundant debug compiles when dist/ is already sealed).
    """
    v = os.environ.get("GAIAFUSION_GATE_SKIP_SWIFT_BUILD", "").strip().lower()
    if v not in ("1", "true", "yes"):
        return False
    bundle_raw = os.environ.get("GAIAFUSION_GATE_APP_BUNDLE", "").strip()
    if not bundle_raw:
        return False
    bundle = Path(bundle_raw).expanduser()
    if not bundle.is_absolute():
        bundle = (ctx.repo_root / bundle).resolve()
    else:
        bundle = bundle.resolve()
    exe = bundle / "Contents" / "MacOS" / BINARY_NAME
    return exe.is_file() and os.access(exe, os.X_OK)


def find_binary(ctx: GateContext) -> Path | None:
    """Resolve GaiaFusion executable for the gate.

    - ``GAIAFUSION_GATE_APP_BUNDLE`` — if set to a ``.app`` path, use ``Contents/MacOS/GaiaFusion`` (packaged artifact).
    - Default (no ``GAIAFUSION_GATE_USE_XCODE=1``): **SwiftPM** ``.build/.../debug/GaiaFusion`` only — never a stale
      Xcode DerivedData ``.app`` (that path lacks ``package_gaiafusion_app.sh`` rpath/embed and dies at dyld).
    - With ``GAIAFUSION_GATE_USE_XCODE=1``: historical order (DerivedData from ``-showBuildSettings``, then SwiftPM).
    """
    bundle_raw = os.environ.get("GAIAFUSION_GATE_APP_BUNDLE", "").strip()
    if bundle_raw:
        bundle = Path(bundle_raw).expanduser()
        if not bundle.is_absolute():
            bundle = (ctx.repo_root / bundle).resolve()
        else:
            bundle = bundle.resolve()
        exe = bundle / "Contents" / "MacOS" / BINARY_NAME
        if exe.is_file() and os.access(exe, os.X_OK):
            return exe

    candidates: list[Path] = []

    if gate_use_xcodebuild():
        rc, out = run_cmd(
            [
                "xcodebuild",
                "-scheme",
                SCHEME,
                "-destination",
                "platform=macOS",
                "-showBuildSettings",
            ],
            cwd=ctx.project_root,
            timeout=120,
        )
        if rc == 0:
            build_dir_match = re.search(r"^\s*BUILT_PRODUCTS_DIR\s*=\s*(.+)$", out, re.M)
            product_match = re.search(r"^\s*FULL_PRODUCT_NAME\s*=\s*(.+)$", out, re.M)
            if build_dir_match and product_match:
                build_dir = Path(build_dir_match.group(1).strip())
                full_product = product_match.group(1).strip()
                if full_product.endswith(".app"):
                    candidates.append(build_dir / full_product / "Contents" / "MacOS" / BINARY_NAME)
                else:
                    candidates.append(build_dir / full_product)

    candidates.extend(
        [
            ctx.project_root / ".build" / "arm64-apple-macosx" / "debug" / BINARY_NAME,
            ctx.project_root / ".build" / "x86_64-apple-macosx" / "debug" / BINARY_NAME,
            ctx.project_root / ".build" / "debug" / BINARY_NAME,
        ]
    )

    for path in candidates:
        if path.is_file() and os.access(path, os.X_OK):
            return path

    for alt in ctx.project_root.glob(".build/*/debug/*"):
        if alt.name == BINARY_NAME and alt.is_file() and os.access(str(alt), os.X_OK):
            return alt

    return None


def patch_swiftpm_gate_binary(project_root: Path) -> tuple[bool, dict[str, Any]]:
    """After ``swift build``, align Mach-O LC_RPATH with ``package_gaiafusion_app.sh`` so dyld can resolve USD_Core.

    Adds ``@executable_path/../Frameworks`` (idempotent failures from duplicate rpath are ignored).
    """
    rc, out = run_cmd(
        ["swift", "build", "--configuration", "debug", "--show-bin-path"],
        cwd=project_root,
        timeout=120,
    )
    witness: dict[str, Any] = {"show_bin_path_rc": rc}
    if rc != 0:
        return False, {**witness, "reason": "show_bin_path_failed", "tail": out[-2000:] if out else ""}
    bp = Path(out.strip().splitlines()[-1].strip())
    exe = bp / BINARY_NAME
    witness["binary"] = str(exe)
    if not exe.is_file():
        return False, {**witness, "reason": "gaiafusion_binary_missing"}
    rpath = "@executable_path/../Frameworks"
    irc, irout = run_cmd(
        ["install_name_tool", "-add_rpath", rpath, str(exe)],
        cwd=project_root,
        timeout=60,
    )
    tail = (irout or "")[-800:]
    dup_markers = ("duplicate path", "already has LC_RPATH", "would duplicate")
    if irc != 0 and not any(m in tail for m in dup_markers):
        witness["install_name_tool"] = {"rpath": rpath, "rc": irc, "tail": tail}
        return False, {**witness, "reason": "install_name_tool_failed"}
    witness["install_name_tool"] = {
        "rpath": rpath,
        "rc": 0,
        "note": "injected" if irc == 0 else "duplicate_rpath_ok",
        "raw_rc": irc,
        "tail": tail,
    }
    return True, witness


def dyld_framework_search_paths(binary: Path) -> list[str]:
    """Directories for DYLD_FRAMEWORK_PATH so dyld finds USD_Core (SwiftPM flat dir or packaged Contents/Frameworks)."""
    dirs: list[str] = []
    parent = binary.parent.resolve()
    # Packaged .app: .../Contents/MacOS/GaiaFusion
    if parent.name == "MacOS" and (parent.parent / "Frameworks" / "USD_Core.framework").is_dir():
        dirs.append(str((parent.parent / "Frameworks").resolve()))
    # SwiftPM: USD_Core.framework next to the executable
    if (parent / "USD_Core.framework").is_dir():
        dirs.append(str(parent))
    return dirs


def running_pids() -> list[int]:
    # Use -x (exact process name), not -f. `pgrep -f GaiaFusion` matches any argv string containing
    # that substring — zsh/Cursor wrappers, paths under macos/GaiaFusion/, xctest, etc. — and the gate
    # would SIGTERM unrelated processes (looks "stuck", flakes projection).
    try:
        proc = subprocess.run(
            ["pgrep", "-x", BINARY_NAME],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
    except FileNotFoundError:
        return []
    if proc.returncode != 0:
        return []
    pids: list[int] = []
    for token in proc.stdout.split():
        try:
            pids.append(int(token))
        except ValueError:
            continue
    return pids


def stop_running_gaiafusion() -> list[int]:
    """Terminate **all** GaiaFusion Mach-O processes (single Mac cell). TERM, then KILL stragglers (UI may ignore TERM)."""
    initial = running_pids()
    for pid in initial:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if initial:
        time.sleep(2.0)
    for pid in running_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    if initial:
        time.sleep(1.0)
    return initial


@dataclass
class GateChildLogs:
    """Paths to child stdout/stderr files (parent holds write FDs until closed after terminate)."""

    stdout_path: Path
    stderr_path: Path
    _stdout_f: BinaryIO
    _stderr_f: BinaryIO

    def close_parent_handles(self) -> None:
        for f in (self._stdout_f, self._stderr_f):
            try:
                f.flush()
                f.close()
            except OSError:
                pass


def start_app(
    ctx: GateContext,
    binary: Path,
    extra_env: dict[str, str] | None = None,
) -> tuple[subprocess.Popen[bytes] | None, GateChildLogs | None]:
    """Launch GaiaFusion with stdout/stderr redirected to evidence files (avoids PIPE deadlock if Swift prints).

    Port alignment: the gate sets ``FUSION_UI_PORT`` to the chosen TCP port; ``LocalServer`` reads that env (not stdout).
    """
    out_f = None
    err_f = None
    try:
        ctx.evidence_dir.mkdir(parents=True, exist_ok=True)
        out_path = ctx.evidence_dir / f"gaiafusion_gate_{ctx.run_id}_stdout.log"
        err_path = ctx.evidence_dir / f"gaiafusion_gate_{ctx.run_id}_stderr.log"
        out_f = open(out_path, "wb")
        err_f = open(err_path, "wb")
        logs = GateChildLogs(stdout_path=out_path, stderr_path=err_path, _stdout_f=out_f, _stderr_f=err_f)
        env = os.environ.copy()
        # Metal / CoreImage: in headless or heavily threaded CI, JIT shader compile + MTLCompilerFSCache disk I/O can
        # deadlock (CI::KernelCompileQueue / __ulock_wait2). Keep compiled pipelines in RAM; skip CI FSCache writes.
        env.setdefault("MTL_DISABLE_COMPILED_CODE_CACHE", "1")
        env.setdefault("CI_DISABLE_FSCache", "1")
        # Swifter runs HTTP handlers off MainActor; s4-projection uses a no–cross-actor snapshot when set (gate only).
        env.setdefault("GAIAFUSION_GATE_MINIMAL_S4", "1")
        env.setdefault("GAIAFUSION_AUTO_MOOR", "1")
        # SingleMacCellLock is per FUSION_UI_PORT — mark gate subprocess for receipts / debugging.
        env.setdefault("GAIAFUSION_GATE_CHILD", "1")
        fw_dirs = dyld_framework_search_paths(binary)
        if fw_dirs:
            prev = env.get("DYLD_FRAMEWORK_PATH", "").strip()
            merged = ":".join([*fw_dirs, prev] if prev else fw_dirs)
            env["DYLD_FRAMEWORK_PATH"] = merged
        if extra_env:
            env.update(extra_env)
        proc = subprocess.Popen(
            [str(binary)],
            cwd=str(binary.parent),
            stdout=out_f,
            stderr=err_f,
            stdin=subprocess.DEVNULL,
            text=False,
            start_new_session=True,
            env=env,
        )
        return proc, logs
    except OSError:
        for f in (out_f, err_f):
            if f is not None:
                try:
                    f.close()
                except OSError:
                    pass
        return None, None


def read_child_log_tails(logs: GateChildLogs | None, max_chars: int = 24_000) -> dict[str, Any]:
    """After the child has exited or been signalled, read UTF-8 tails for receipt witnesses."""
    if logs is None:
        return {"note": "no_child_logs"}
    logs.close_parent_handles()
    out = ""
    err = ""
    try:
        if logs.stdout_path.is_file():
            raw = logs.stdout_path.read_bytes()
            out = raw.decode("utf-8", errors="replace")[-max_chars:]
    except OSError as exc:
        out = f"<stdout read error: {exc!r}>"
    try:
        if logs.stderr_path.is_file():
            raw = logs.stderr_path.read_bytes()
            err = raw.decode("utf-8", errors="replace")[-max_chars:]
    except OSError as exc:
        err = f"<stderr read error: {exc!r}>"
    return {
        "stdout_log": str(logs.stdout_path),
        "stderr_log": str(logs.stderr_path),
        "stdout_tail": out,
        "stderr_tail": err,
    }


def terminate_gate_child(proc: subprocess.Popen[bytes] | None, wait_sec: float = 4.0) -> int | None:
    """Stop gate-spawned GaiaFusion; return exit code if available.

    GUI apps may ignore SIGTERM; SIGKILL wait can still block briefly — never raise TimeoutExpired to callers.
    """
    if proc is None:
        return None
    try:
        if proc.poll() is None:
            proc.terminate()
            try:
                return proc.wait(timeout=wait_sec)
            except subprocess.TimeoutExpired:
                proc.kill()
                try:
                    return proc.wait(timeout=12.0)
                except subprocess.TimeoutExpired:
                    try:
                        os.kill(proc.pid, signal.SIGKILL)
                    except OSError:
                        pass
                    try:
                        return proc.wait(timeout=20.0)
                    except subprocess.TimeoutExpired:
                        return None
        return proc.returncode
    except OSError:
        return proc.poll()


def probe_projection(ctx: GateContext, timeout_sec: float = 1.5) -> tuple[bool, str]:
    """Return (ok, diagnostic). Prefer ``curl --noproxy '*'`` — urllib/proxy stacks often flake on localhost in IDE shells."""
    url = f"http://127.0.0.1:{ctx.health_port}{ctx.probe_path}"
    to = max(1, int(timeout_sec))
    try:
        proc = subprocess.run(
            [
                "curl",
                "-fsS",
                "--noproxy",
                "*",
                "--connect-timeout",
                str(to),
                "-o",
                "/dev/null",
                "-w",
                "%{http_code}",
                url,
            ],
            capture_output=True,
            text=True,
            timeout=timeout_sec + 3.0,
            check=False,
        )
        code = (proc.stdout or "").strip()
        if proc.returncode == 0 and code == "200":
            return True, ""
        tail = ((proc.stderr or "") + (proc.stdout or ""))[-400:]
        return False, f"curl rc={proc.returncode} http_code={code!r} tail={tail!r}"
    except FileNotFoundError:
        pass
    except subprocess.TimeoutExpired as exc:
        return False, f"curl_timeout: {exc!r}"
    except OSError as exc:
        return False, f"curl_oserror: {exc!r}"

    try:
        with urlopen_direct(url, timeout=timeout_sec) as response:
            ok = response.status == 200
            return ok, "" if ok else f"urllib status={getattr(response, 'status', None)}"
    except (urllib.error.URLError, TimeoutError, socket.timeout) as exc:
        return False, repr(exc)


def probe_fusion_health_json(port: int, timeout_sec: float = 2.0) -> tuple[bool, dict[str, Any]]:
    """Invariant: /api/fusion/health documents mesh port, self_heal, Klein-bottle closure, and native `usd_px` (monolithic USD)."""
    url = f"http://127.0.0.1:{port}/api/fusion/health"
    try:
        with urlopen_direct(url, timeout=timeout_sec) as response:
            raw = response.read().decode("utf-8", errors="replace")
            body = json.loads(raw)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, ValueError) as exc:
        return False, {"error": str(exc)}
    if not isinstance(body, dict):
        return False, {"error": "not_a_json_object"}
    status = body.get("status")
    local_ui = body.get("local_ui_port")
    self_heal = body.get("self_heal")
    kb = body.get("klein_bottle")
    kb_closed_top = body.get("klein_bottle_closed")
    usd = body.get("usd_px")
    usd_ok = (
        isinstance(usd, dict)
        and isinstance(usd.get("pxr_version_int"), int)
        and int(usd.get("pxr_version_int", 0)) > 0
        and isinstance(usd.get("in_memory_stage"), bool)
        and usd.get("plant_control_viewport_prim") is True
    )
    ok = (
        status == "ok"
        and isinstance(local_ui, int)
        and local_ui == port
        and isinstance(self_heal, dict)
        and isinstance(self_heal.get("recovery_active"), bool)
        and isinstance(self_heal.get("reprobe_upstream_allowed"), bool)
        and isinstance(kb, dict)
        and kb.get("closed") is True
        and kb_closed_top is True
        and isinstance(kb.get("default_metallib_present"), bool)
        and usd_ok
    )
    return ok, body


def probe_fusion_self_probe_json(port: int, timeout_sec: float = 12.0) -> tuple[bool, dict[str, Any]]:
    """In-app `/api/fusion/self-probe` — WKWebView DOM + wasm + openusd_playback (off-main-thread HTTP client)."""
    url = f"http://127.0.0.1:{port}/api/fusion/self-probe"
    last_err: str | None = None
    for attempt in range(1, 4):
        try:
            with urlopen_direct(url, timeout=timeout_sec) as response:
                raw = response.read().decode("utf-8", errors="replace")
                body = json.loads(raw)
            if not isinstance(body, dict):
                return False, {"error": "not_a_json_object"}
            return True, body
        except (
            urllib.error.URLError,
            TimeoutError,
            json.JSONDecodeError,
            ValueError,
            http.client.RemoteDisconnected,
            ConnectionResetError,
            BrokenPipeError,
        ) as exc:
            last_err = str(exc)
            if attempt < 3:
                time.sleep(0.35 * attempt)
    return False, {"error": last_err or "self_probe_failed"}


def validate_splash_contract(body: dict[str, Any]) -> tuple[bool, str]:
    """Phase 2: splash must dismiss via server+WebView handshake, not timeout bypass."""
    if os.environ.get("GAIAFUSION_GATE_SKIP_SPLASH_CONTRACT", "").strip() == "1":
        return True, "skipped"
    dismissed = body.get("splash_dismissed")
    reason = body.get("splash_dismiss_reason", "unknown")
    if dismissed is not True:
        return False, f"splash_screen_active:dismissed={dismissed!r} reason={reason!r}"
    if reason != "handshake":
        return False, f"ui_boot_lag_not_handshake:splash_dismiss_reason={reason!r}"
    return True, ""


def probe_self_probe_until_splash_handshake(
    port: int, max_wait_sec: float = 48.0
) -> tuple[bool, dict[str, Any]]:
    """Poll ``/api/fusion/self-probe`` until splash contract passes or wall-clock exhaustion."""
    if os.environ.get("GAIAFUSION_GATE_SKIP_SPLASH_CONTRACT", "").strip() == "1":
        return probe_fusion_self_probe_json(port, timeout_sec=12.0)
    deadline = time.monotonic() + max_wait_sec
    last_body: dict[str, Any] = {}
    while time.monotonic() < deadline:
        sp_ok, sp_body = probe_fusion_self_probe_json(port, timeout_sec=4.0)
        last_body = sp_body if isinstance(sp_body, dict) else {}
        if not sp_ok:
            time.sleep(0.35)
            continue
        sk, _ = validate_splash_contract(sp_body)
        if sk:
            return True, sp_body
        # Splash still up, or dismissed via timeout — keep polling until deadline.
        time.sleep(0.25)
    return False, last_body


def validate_self_probe_epistemic_only(body: dict[str, Any]) -> tuple[bool, str]:
    """Pre-automation: terminal CURE + epistemic M/T/I/A (swap lifecycle may be IDLE or mid-flight)."""
    if body.get("terminal") != "CURE":
        return False, f"terminal_not_cure:{body.get('terminal')!r}"
    ou = body.get("openusd_playback")
    if not isinstance(ou, dict):
        return False, "openusd_playback_missing"
    ep = ou.get("epistemic")
    if not isinstance(ep, dict):
        return False, "epistemic_missing"
    letters = frozenset({"M", "T", "I", "A"})
    for k in ("I_p", "B_T", "n_e"):
        v = ep.get(k)
        if not isinstance(v, str) or len(v) != 1 or v not in letters:
            return False, f"epistemic_{k}_invalid:{v!r}"
    return True, ""


def validate_self_probe_subgame_post_automation(body: dict[str, Any], expected_plant: str) -> tuple[bool, str]:
    """After loopback swap: same epistemic checks + ``swap_lifecycle==VERIFIED`` and committed plant_kind."""
    ok, reason = validate_self_probe_epistemic_only(body)
    if not ok:
        return False, reason
    ou = body.get("openusd_playback")
    assert isinstance(ou, dict)
    sl = ou.get("swap_lifecycle")
    pk = ou.get("plant_kind")
    if sl != "VERIFIED":
        return False, f"swap_lifecycle_not_verified:{sl!r}"
    if pk != expected_plant:
        return False, f"plant_kind_mismatch:expected={expected_plant!r} got={pk!r}"
    return True, ""


# Canonical rotation order (matches Swift ``PlantType`` / ``PlantKindsCatalog``).
_SUBGAME_X_PLANT_ROTATION: tuple[str, ...] = (
    "tokamak",
    "stellarator",
    "frc",
    "spheromak",
    "mirror",
    "inertial",
    "spherical_tokamak",
    "z_pinch",
    "mif",
)


def pick_alternate_plant_kind(current: str | None) -> str:
    cur = (current or "tokamak").strip().lower()
    for k in _SUBGAME_X_PLANT_ROTATION:
        if k != cur:
            return k
    return "stellarator"


def http_post_json_local(url: str, payload: dict[str, Any], timeout_sec: float = 8.0) -> tuple[bool, dict[str, Any]]:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(req, timeout=timeout_sec) as response:
            raw = response.read().decode("utf-8", errors="replace")
            body = json.loads(raw)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, ValueError, OSError) as exc:
        return False, {"error": str(exc)}
    if not isinstance(body, dict):
        return False, {"error": "not_a_json_object"}
    return True, body


def wait_for_swap_verified(
    port: int, target: str, deadline_sec: float = 55.0
) -> tuple[bool, dict[str, Any]]:
    """Poll self-probe until ``openusd_playback.swap_lifecycle == VERIFIED`` and plant_kind matches."""
    deadline = time.monotonic() + deadline_sec
    last: dict[str, Any] = {}
    while time.monotonic() < deadline:
        sp_ok, sp_body = probe_fusion_self_probe_json(port, timeout_sec=4.0)
        last = sp_body if isinstance(sp_body, dict) else {}
        if not sp_ok or not isinstance(sp_body, dict):
            time.sleep(0.12)
            continue
        ou = sp_body.get("openusd_playback")
        if isinstance(ou, dict) and ou.get("swap_lifecycle") == "VERIFIED" and ou.get("plant_kind") == target:
            return True, sp_body
        time.sleep(0.12)
    return False, last


def run_canonical_plant_kinematic_gate(port: int) -> tuple[bool, str, dict[str, Any]]:
    """Phase 4: all nine canonical ``PlantKindsCatalog`` kinds — VERIFIED swap, ENGAGE, ``normalized_t`` in three bands (strict frames).

    REFUSED when ``GAIAFUSION_GATE_OPENUSD_HEADLESS_OK=1`` (no silent headless waiver for operator CURE).
    Writes no file here; caller persists ``gaiafusion_kinematic_gate_receipt.json``.
    """
    if os.environ.get("GAIAFUSION_GATE_OPENUSD_HEADLESS_OK", "").strip() == "1":
        return False, "kinematic_gate_REFUSED:GAIAFUSION_GATE_OPENUSD_HEADLESS_OK_set", {
            "policy": "operator_CURE_requires_frames_presented",
        }
    plants = _SUBGAME_X_PLANT_ROTATION
    engage_url = f"http://127.0.0.1:{port}/api/fusion/gate/engage-viewport"
    load_url = f"http://127.0.0.1:{port}/api/fusion/gate/load-viewport-plant"
    receipt: dict[str, Any] = {
        "schema": "gaiaftcl_kinematic_gate_receipt_v1",
        "plant_kinds_order": list(plants),
        "poll_interval_sec": 0.12,
        "normalized_t_bands": {
            "low": "[0.0, 0.33)",
            "mid": "[0.33, 0.66)",
            "high": "[0.66, 1.0]",
        },
        "per_plant": [],
    }
    for kind in plants:
        plant_row: dict[str, Any] = {"plant_kind": kind}
        post_ok, post_body = http_post_json_local(load_url, {"plant_kind": kind})
        plant_row["load_post_ok"] = post_ok
        plant_row["load_post"] = post_body
        if not post_ok or post_body.get("ok") is not True:
            return False, f"load_viewport_failed:{kind}", {**receipt, "failed_at": plant_row}
        ok_vf, sp_last = wait_for_swap_verified(port, kind, deadline_sec=55.0)
        plant_row["verified_ok"] = ok_vf
        if not ok_vf:
            return False, f"timeout_verified_swap:{kind}", {**receipt, "failed_at": plant_row, "last_self_probe": sp_last}
        eng_ok, eng_body = http_post_json_local(engage_url, {})
        plant_row["engage_ok"] = eng_ok
        plant_row["engage_body"] = eng_body
        if not eng_ok or eng_body.get("ok") is not True:
            return False, f"engage_failed:{kind}", {**receipt, "failed_at": plant_row}
        bands = {"low": False, "mid": False, "high": False}
        samples: list[dict[str, Any]] = []
        band_deadline = time.monotonic() + 60.0
        completed = False
        while time.monotonic() < band_deadline:
            ou_ok, ou_body = probe_openusd_playback_json(port)
            if ou_ok and isinstance(ou_body, dict):
                try:
                    nt = float(ou_body.get("normalized_t", 0.0))
                except (TypeError, ValueError):
                    nt = 0.0
                try:
                    fp = int(ou_body.get("frames_presented", 0))
                except (TypeError, ValueError):
                    fp = 0
                samples.append({"normalized_t": nt, "frames_presented": fp})
                if 0.0 <= nt < 0.33:
                    bands["low"] = True
                elif 0.33 <= nt < 0.66:
                    bands["mid"] = True
                elif nt >= 0.66:
                    bands["high"] = True
                if bands["low"] and bands["mid"] and bands["high"]:
                    plant_row["bands_observed"] = bands
                    plant_row["sample_count"] = len(samples)
                    completed = True
                    break
            time.sleep(0.12)
        if not completed:
            plant_row["bands_observed"] = bands
            plant_row["samples_tail"] = samples[-24:]
            return False, f"kinematic_bands_incomplete:{kind}", {**receipt, "failed_at": plant_row}
        receipt["per_plant"].append(plant_row)
    return True, "", receipt


run_six_plant_kinematic_gate = run_canonical_plant_kinematic_gate


def run_subgame_x_loopback_automation(port: int) -> tuple[bool, str, dict[str, Any]]:
    """POST gate load-viewport-plant, poll self-probe until VERIFIED + plant_kind matches (C4 mechanical SubGame X)."""
    ou_ok, ou_body = probe_openusd_playback_json(port, timeout_sec=4.0)
    if not ou_ok:
        return False, "openusd_playback_unavailable_for_plant_baseline", {"openusd_playback": ou_body}
    current = ou_body.get("plant_kind")
    if not isinstance(current, str):
        current = "tokamak"
    target = pick_alternate_plant_kind(current)
    post_url = f"http://127.0.0.1:{port}/api/fusion/gate/load-viewport-plant"
    post_ok, post_body = http_post_json_local(post_url, {"plant_kind": target})
    witness: dict[str, Any] = {
        "target_plant_kind": target,
        "prior_plant_kind": current,
        "post_ok": post_ok,
        "post_response": post_body,
    }
    if not post_ok or not post_body.get("ok"):
        return False, f"gate_load_viewport_plant_failed:{post_body!r}", witness

    deadline = time.monotonic() + 20.0
    seen_states: list[str] = []
    last_sl: str | None = None
    last_sp: dict[str, Any] = {}
    while time.monotonic() < deadline:
        sp_ok, sp_body = probe_fusion_self_probe_json(port, timeout_sec=3.0)
        last_sp = sp_body if isinstance(sp_body, dict) else {}
        if sp_ok and isinstance(sp_body, dict):
            ou = sp_body.get("openusd_playback")
            if isinstance(ou, dict):
                sl = ou.get("swap_lifecycle")
                if isinstance(sl, str) and sl != last_sl:
                    seen_states.append(sl)
                    last_sl = sl
                pk = ou.get("plant_kind")
                if sl == "VERIFIED" and pk == target:
                    witness["swap_lifecycle_trace"] = seen_states
                    witness["final_self_probe"] = sp_body
                    return True, "", witness
        time.sleep(0.05)

    witness["swap_lifecycle_trace"] = seen_states
    witness["last_swap_lifecycle"] = last_sl
    witness["final_self_probe"] = last_sp
    return False, "timeout_waiting_for_verified_swap", witness


def probe_openusd_playback_json(port: int, timeout_sec: float = 2.0) -> tuple[bool, dict[str, Any]]:
    """Invariant: ``frames_presented > 0`` via ``/api/fusion/openusd-playback`` (strict Metal receipt).

    If ``GAIAFUSION_GATE_OPENUSD_HEADLESS_OK=1``, accept ``stage_loaded`` + ``render_path`` when ``frames_presented``
    stays 0 (e.g. process has no visible display / CVDisplayLink never ticks). Default remains strict for interactive Mac.
    """
    url = f"http://127.0.0.1:{port}/api/fusion/openusd-playback"
    try:
        with urlopen_direct(url, timeout=timeout_sec) as response:
            raw = response.read().decode("utf-8", errors="replace")
            body = json.loads(raw)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, ValueError) as exc:
        return False, {"error": str(exc)}
    if not isinstance(body, dict):
        return False, {"error": "not_a_json_object"}
    fp_raw = body.get("frames_presented", 0)
    try:
        fp_i = int(fp_raw)
    except (TypeError, ValueError):
        fp_i = 0
    schema = body.get("schema")
    fp_ok = fp_i > 0
    headless_ok = (
        os.environ.get("GAIAFUSION_GATE_OPENUSD_HEADLESS_OK", "").strip() == "1"
        and body.get("stage_loaded") is True
        and body.get("render_path") == "metal_usd_proxy_wireframe"
    )
    ok = schema == "gaiaftcl_openusd_playback_v1" and (fp_ok or headless_ok)
    return ok, body


def playwright_wasm_gate(repo_root: Path, port: int) -> tuple[bool, dict[str, Any]]:
    """Robot agent: Playwright drives fusion-s4 topology iframe; asserts substrate JSON is ok (not gateway_unreachable)."""
    ui_dir = repo_root / "services" / "gaiaos_ui_web"
    spec_path = ui_dir / PLAYWRIGHT_SPEC
    if not spec_path.is_file():
        return False, {"reason": "playwright_spec_missing", "path": str(spec_path)}
    env = os.environ.copy()
    env["GAIA_ROOT"] = str(repo_root)
    env["FUSION_MAC_GATE_BASE_URL"] = f"http://127.0.0.1:{port}"
    cmd = [
        "npx",
        "playwright",
        "test",
        PLAYWRIGHT_SPEC,
        "--config=playwright.fusion.config.ts",
    ]
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(ui_dir),
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=600,
            check=False,
        )
    except FileNotFoundError:
        return False, {"reason": "npx_not_found"}
    except subprocess.TimeoutExpired as exc:
        tail = (exc.stdout or "")[-8000:]
        return False, {"reason": "playwright_timeout", "tail": tail}
    ok = proc.returncode == 0
    tail = (proc.stdout or "")[-12000:]
    return ok, {
        "command": " ".join(cmd),
        "rc": proc.returncode,
        "ok": ok,
        "stdout_tail": tail,
    }


def composite_resources_paths(
    ctx: GateContext,
) -> tuple[Path, Path, Path, Path, Path]:
    """default.metallib, fusion-web/index.html, substrate.html, fusion-web/_next/static (dir), gaiafusion_substrate.wasm."""
    res = ctx.project_root / "GaiaFusion" / "Resources"
    return (
        res / "default.metallib",
        res / "fusion-web" / "index.html",
        res / "fusion-web" / "substrate.html",
        res / "fusion-web" / "_next" / "static",
        res / "gaiafusion_substrate.wasm",
    )


def verify_composite_artifacts(ctx: GateContext) -> tuple[bool, dict[str, Any]]:
    metallib, fusion_index, substrate_html, static_dir, substrate_wasm = composite_resources_paths(ctx)
    res = ctx.project_root / "GaiaFusion" / "Resources"
    sidecar_compose = res / "fusion-sidecar-cell" / "docker-compose.fusion-sidecar.yml"
    plant_adapters = res / "spec" / "native_fusion" / "plant_adapters.json"
    substrate_bindgen_js = res / "gaiafusion_substrate_bindgen.js"
    ok = (
        metallib.is_file()
        and fusion_index.is_file()
        and substrate_html.is_file()
        and static_dir.is_dir()
        and substrate_wasm.is_file()
        and substrate_bindgen_js.is_file()
        and substrate_bindgen_js.stat().st_size > 512
        and sidecar_compose.is_file()
        and plant_adapters.is_file()
    )
    detail: dict[str, Any] = {
        "default_metallib": str(metallib),
        "default_metallib_bytes": metallib.stat().st_size if metallib.is_file() else 0,
        "fusion_web_index_html": str(fusion_index),
        "fusion_web_index_bytes": fusion_index.stat().st_size if fusion_index.is_file() else 0,
        "fusion_web_substrate_html": str(substrate_html),
        "fusion_web_substrate_bytes": substrate_html.stat().st_size if substrate_html.is_file() else 0,
        "fusion_web_next_static_dir": str(static_dir),
        "gaiafusion_substrate_wasm": str(substrate_wasm),
        "gaiafusion_substrate_wasm_bytes": substrate_wasm.stat().st_size if substrate_wasm.is_file() else 0,
        "gaiafusion_substrate_bindgen_js": str(substrate_bindgen_js),
        "gaiafusion_substrate_bindgen_js_bytes": substrate_bindgen_js.stat().st_size if substrate_bindgen_js.is_file() else 0,
        "fusion_sidecar_compose_yml": str(sidecar_compose),
        "fusion_sidecar_compose_bytes": sidecar_compose.stat().st_size if sidecar_compose.is_file() else 0,
        "plant_adapters_json": str(plant_adapters),
        "plant_adapters_bytes": plant_adapters.stat().st_size if plant_adapters.is_file() else 0,
        "ok": ok,
    }
    return ok, detail


def poll_wasm_runtime_closed(port: int, attempts: int = 90, interval_sec: float = 0.5) -> tuple[bool, dict[str, Any]]:
    """Wait for WKWebView to post wasmRuntime witness — /api/fusion/health wasm_runtime.closed."""
    last: dict[str, Any] = {}
    url = f"http://127.0.0.1:{port}/api/fusion/health"
    for _ in range(attempts):
        try:
            with urlopen_direct(url, timeout=2.0) as response:
                last = json.loads(response.read().decode("utf-8", errors="replace"))
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, ValueError):
            time.sleep(interval_sec)
            continue
        wr = last.get("wasm_runtime")
        if isinstance(wr, dict) and wr.get("closed") is True:
            return True, last
        time.sleep(interval_sec)
    return False, last


def wasm_runtime_bindgen_witness_ok(fusion_health: dict[str, Any]) -> tuple[bool, str]:
    """CURE gate: wasm_runtime must be the real wasm-bindgen closure path, not raw instantiate / spike."""
    wr = fusion_health.get("wasm_runtime")
    if not isinstance(wr, dict):
        return False, "wasm_runtime_missing_or_not_object"
    if wr.get("closed") is not True:
        return False, "wasm_runtime_not_closed"
    if wr.get("ok") is not True:
        return False, "wasm_runtime_ok_false"
    path = wr.get("instantiate_path")
    if path != "wasm_bindgen_init":
        return False, f"instantiate_path_not_bindgen:{path!r}"
    return True, ""


def build_composite_assets(ctx: GateContext) -> tuple[bool, dict[str, Any]]:
    script = ctx.repo_root / COMPOSITE_SCRIPT
    if not script.is_file():
        return False, {"reason": "composite_script_missing", "path": str(script)}
    rc, out = run_cmd(["bash", str(script)], cwd=ctx.repo_root, timeout=2400)
    witness: dict[str, Any] = {
        "command": f"bash {COMPOSITE_SCRIPT}",
        "rc": rc,
        "tail": "\n".join(out.splitlines()[-48:]),
    }
    if rc != 0:
        return False, witness
    v_ok, v_detail = verify_composite_artifacts(ctx)
    witness["artifacts"] = v_detail
    if not v_ok:
        return False, {**witness, "reason": "composite_artifact_verification_failed"}
    return True, witness


def build_gate(ctx: GateContext) -> tuple[bool, dict[str, Any]]:
    """Build GaiaFusion for the gate.

    Default: **SwiftPM only** (``Package.swift`` is source of truth). Set ``GAIAFUSION_GATE_USE_XCODE=1`` to run
    ``xcodebuild`` first (historical; Xcode scheme must expose USD headers).

    After a successful ``swift build``, applies the same ``install_name_tool`` LC_RPATH as ``package_gaiafusion_app.sh``
    so the gate binary does not die at dyld before ``LocalServer`` binds (fixes projection timeout when ``find_binary``
    would have launched an un-packaged DerivedData ``.app``).
    """
    witness: dict[str, Any] = {}
    if not gate_use_xcodebuild():
        witness["xcodebuild"] = {
            "skipped": True,
            "reason": "default SwiftPM-only gate (set GAIAFUSION_GATE_USE_XCODE=1 for xcodebuild)",
        }
    else:
        rc, out = run_cmd(
            [
                "xcodebuild",
                "-scheme",
                SCHEME,
                "-destination",
                "platform=macOS",
                "build",
            ],
            cwd=ctx.project_root,
            timeout=1200,
        )
        witness["xcodebuild"] = {
            "command": "xcodebuild -scheme GaiaFusion -destination platform=macOS build",
            "rc": rc,
            "tail": "\n".join(out.splitlines()[-24:]),
        }
        if rc != 0:
            return False, witness

    src, sout = run_cmd(
        ["swift", "build", "--configuration", "debug"],
        cwd=ctx.project_root,
        timeout=1200,
    )
    witness["swift_build"] = {
        "command": "swift build --configuration debug",
        "rc": src,
        "tail": "\n".join(sout.splitlines()[-20:]),
    }
    if src != 0:
        return False, witness

    patch_ok, patch_witness = patch_swiftpm_gate_binary(ctx.project_root)
    witness["swiftpm_gate_rpath_patch"] = patch_witness
    if not patch_ok:
        return False, witness
    return True, witness


def run_gate(
    ctx: GateContext,
    skip_playwright: bool,
    fusion_port: int,
    skip_composite_assets: bool,
) -> tuple[bool, dict[str, Any], int]:
    if sys.platform != "darwin":
        return False, {"reason": "darwin_required", "platform": sys.platform}, 2

    ctx.health_port = fusion_port

    if skip_composite_assets:
        composite_witness: dict[str, Any] = {"skipped": True}
        v_ok, v_detail = verify_composite_artifacts(ctx)
        composite_witness["pre_existing_artifacts"] = v_detail
        if not v_ok:
            return False, {"composite_assets": composite_witness, "reason": "composite_assets_missing_skip_false"}, 1
    else:
        comp_ok, composite_witness = build_composite_assets(ctx)
        if not comp_ok:
            return False, {"composite_assets": composite_witness, "reason": "composite_assets_failed"}, 1

    if should_skip_swift_build_for_packaged_bundle(ctx):
        build_witness = {
            "skipped": True,
            "reason": "GAIAFUSION_GATE_SKIP_SWIFT_BUILD with valid GAIAFUSION_GATE_APP_BUNDLE",
        }
        build_ok = True
    else:
        build_ok, build_witness = build_gate(ctx)
        if not build_ok:
            return False, {"composite_assets": composite_witness, "build": build_witness, "reason": "build_failed"}, 1

    binary = find_binary(ctx)
    if not binary:
        return False, {"composite_assets": composite_witness, "build": build_witness, "reason": "binary_not_found"}, 1

    started_pid = None
    proc: subprocess.Popen[bytes] | None = None
    child_logs: GateChildLogs | None = None

    def attach_child_diagnostics(w: dict[str, Any]) -> None:
        if proc is None:
            return
        try:
            w["child_process_exit_code"] = terminate_gate_child(proc)
        except subprocess.TimeoutExpired:
            w["child_process_exit_code"] = None
            w["child_terminate_note"] = "unexpected_wait_timeout"
        w["child_log_witness"] = read_child_log_tails(child_logs)

    if skip_playwright:
        # Per-port SingleMacCellLock: do not SIGKILL the operator's GaiaFusion on 8910; child uses `fusion_port` only.
        replaced: list[int] = []
        if os.environ.get("GAIAFUSION_GATE_KILL_EXISTING", "").strip() == "1":
            replaced = stop_running_gaiafusion()
        proc, child_logs = start_app(ctx, binary, {"FUSION_UI_PORT": str(fusion_port)})
        if proc is None:
            return False, {
                "composite_assets": composite_witness,
                "build": build_witness,
                "reason": "start_failed",
                "binary": str(binary),
                "replaced_pids": replaced,
                "detail": "popen_failed",
            }, 1
        if proc.poll() is not None:
            fail_w: dict[str, Any] = {
                "composite_assets": composite_witness,
                "build": build_witness,
                "reason": "start_failed",
                "binary": str(binary),
                "replaced_pids": replaced,
                "detail": "exited_before_probe_window",
            }
            attach_child_diagnostics(fail_w)
            return False, fail_w, 1
        started_pid = proc.pid
        # Brief bootstrap; Swifter bind is waited explicitly below (``wait_for_loopback_tcp_accept``).
        time.sleep(2.0)
        witness = {
            "composite_assets": composite_witness,
            "build": build_witness,
            "run_mode": "started_by_gate_skip_playwright",
            "replaced_pids": replaced,
            "started_pid": started_pid,
            "binary": str(binary),
            "fusion_ui_port": fusion_port,
            "FUSION_UI_PORT": str(fusion_port),
            "child_stdout_log": str(child_logs.stdout_path) if child_logs else None,
            "child_stderr_log": str(child_logs.stderr_path) if child_logs else None,
        }
    else:
        replaced = []
        if os.environ.get("GAIAFUSION_GATE_KILL_EXISTING", "").strip() == "1":
            replaced = stop_running_gaiafusion()
        proc, child_logs = start_app(ctx, binary, {"FUSION_UI_PORT": str(fusion_port)})
        if proc is None:
            return False, {
                "composite_assets": composite_witness,
                "build": build_witness,
                "reason": "start_failed",
                "binary": str(binary),
                "replaced_pids": replaced,
                "detail": "popen_failed",
            }, 1
        if proc.poll() is not None:
            fail_w = {
                "composite_assets": composite_witness,
                "build": build_witness,
                "reason": "start_failed",
                "binary": str(binary),
                "replaced_pids": replaced,
                "detail": "exited_before_probe_window",
            }
            attach_child_diagnostics(fail_w)
            return False, fail_w, 1
        started_pid = proc.pid
        time.sleep(2.0)
        witness = {
            "composite_assets": composite_witness,
            "build": build_witness,
            "run_mode": "restarted_for_playwright_wasm_gate",
            "replaced_pids": replaced,
            "started_pid": started_pid,
            "binary": str(binary),
            "fusion_ui_port": fusion_port,
            "FUSION_UI_PORT": str(fusion_port),
            "child_stdout_log": str(child_logs.stdout_path) if child_logs else None,
            "child_stderr_log": str(child_logs.stderr_path) if child_logs else None,
        }

    listen_timeout = gate_listen_timeout_sec()
    listen_ok, listen_elapsed, listen_diag = wait_for_loopback_tcp_accept(
        fusion_port, listen_timeout, proc
    )
    witness["loopback_listen_ok"] = listen_ok
    witness["loopback_listen_elapsed_sec"] = round(listen_elapsed, 3)
    witness["loopback_listen_diag"] = listen_diag
    witness["loopback_listen_timeout_sec"] = listen_timeout
    if not listen_ok:
        fail_listen: dict[str, Any] = {
            **witness,
            "reason": "loopback_tcp_never_bound",
            "detail": listen_diag,
        }
        attach_child_diagnostics(fail_listen)
        return False, fail_listen, 1

    probe_ok = False
    last_proj_diag = ""
    for attempt in range(1, 12):
        ok, last_proj_diag = probe_projection(ctx)
        if ok:
            probe_ok = True
            break
        time.sleep(1.0)

    witness["projection_probe_ok"] = probe_ok
    witness["projection_probe_attempts"] = attempt
    witness["projection_probe_last_error"] = "" if probe_ok else last_proj_diag
    witness["projection_url"] = f"http://127.0.0.1:{ctx.health_port}{ctx.probe_path}"

    if not probe_ok:
        fail_w = {**witness, "reason": "projection_not_responding"}
        attach_child_diagnostics(fail_w)
        return False, fail_w, 1

    fh_ok, fh_body = probe_fusion_health_json(ctx.health_port)
    witness["fusion_health_probe_ok"] = fh_ok
    witness["fusion_health"] = fh_body
    if not fh_ok:
        fail_w = {**witness, "reason": "fusion_health_invariant_failed"}
        attach_child_diagnostics(fail_w)
        return False, fail_w, 1

    ou_ok = False
    ou_body: dict[str, Any] = {}
    ou_attempt = 0
    for ou_attempt in range(1, 41):
        ou_ok, ou_body = probe_openusd_playback_json(ctx.health_port)
        if ou_ok:
            break
        time.sleep(0.5)
    witness["openusd_playback_probe_ok"] = ou_ok
    witness["openusd_playback_probe_attempts"] = ou_attempt
    witness["openusd_playback"] = ou_body
    if not ou_ok:
        fail_w = {**witness, "reason": "openusd_playback_not_presenting"}
        attach_child_diagnostics(fail_w)
        return False, fail_w, 1

    try:
        _fp_w = int(ou_body.get("frames_presented") or 0)
    except (TypeError, ValueError):
        _fp_w = 0
    witness["openusd_frames_presented"] = _fp_w
    witness["openusd_gate_relaxed_headless"] = (
        os.environ.get("GAIAFUSION_GATE_OPENUSD_HEADLESS_OK", "").strip() == "1" and _fp_w == 0 and ou_ok
    )

    if os.environ.get("GAIAFUSION_GATE_SKIP_SELF_PROBE", "").strip() == "1":
        witness["fusion_self_probe"] = {"skipped": True, "note": "GAIAFUSION_GATE_SKIP_SELF_PROBE"}
        witness["fusion_self_probe_ok"] = True
        witness["self_probe_subgame_ok"] = True
        witness["self_probe_subgame_reason"] = "skipped"
    else:
        sp_ok, sp_body = probe_self_probe_until_splash_handshake(ctx.health_port)
        witness["fusion_self_probe_ok"] = sp_ok
        witness["fusion_self_probe_baseline"] = sp_body
        if not sp_ok:
            fail_w = {**witness, "reason": "fusion_self_probe_unavailable_or_splash_not_handshake"}
            attach_child_diagnostics(fail_w)
            return False, fail_w, 1
        splash_ok, splash_reason = validate_splash_contract(sp_body)
        witness["splash_contract_ok"] = splash_ok
        witness["splash_contract_reason"] = splash_reason
        if not splash_ok:
            fail_w = {
                **witness,
                "reason": "splash_contract_failed",
                "detail": splash_reason,
            }
            attach_child_diagnostics(fail_w)
            return False, fail_w, 1
        ep_ok, ep_reason = validate_self_probe_epistemic_only(sp_body)
        witness["self_probe_epistemic_ok"] = ep_ok
        witness["self_probe_epistemic_reason"] = ep_reason
        if not ep_ok:
            fail_w = {**witness, "reason": "self_probe_epistemic_failed", "detail": ep_reason}
            attach_child_diagnostics(fail_w)
            return False, fail_w, 1

        kin_ok, kin_reason, kin_witness = run_canonical_plant_kinematic_gate(ctx.health_port)
        witness["canonical_plant_kinematic"] = kin_witness
        witness["canonical_plant_kinematic_ok"] = kin_ok
        witness["canonical_plant_kinematic_reason"] = kin_reason
        # Legacy keys (same values): older receipts / parsers used "six_plant_*" when the rotation was six kinds.
        witness["six_plant_kinematic"] = kin_witness
        witness["six_plant_kinematic_ok"] = kin_ok
        witness["six_plant_kinematic_reason"] = kin_reason
        kpath = write_kinematic_gate_receipt(ctx, "CURE" if kin_ok else "REFUSED", kin_witness, kin_reason)
        witness["kinematic_gate_receipt_path"] = str(kpath)
        if not kin_ok:
            fail_w = {**witness, "reason": "canonical_plant_kinematic_failed", "detail": kin_reason}
            attach_child_diagnostics(fail_w)
            return False, fail_w, 1

        sp_final_ok, final = probe_fusion_self_probe_json(ctx.health_port, timeout_sec=8.0)
        if not sp_final_ok or not isinstance(final, dict):
            fail_w = {**witness, "reason": "fusion_self_probe_missing_after_kinematic"}
            attach_child_diagnostics(fail_w)
            return False, fail_w, 1
        target = _SUBGAME_X_PLANT_ROTATION[-1]
        splash_final_ok, splash_final_reason = validate_splash_contract(final)
        witness["splash_contract_final_ok"] = splash_final_ok
        witness["splash_contract_final_reason"] = splash_final_reason
        if not splash_final_ok:
            fail_w = {
                **witness,
                "reason": "splash_contract_final_failed",
                "detail": splash_final_reason,
            }
            attach_child_diagnostics(fail_w)
            return False, fail_w, 1
        sg_ok, sg_reason = validate_self_probe_subgame_post_automation(final, target)
        witness["fusion_self_probe"] = final
        witness["self_probe_subgame_ok"] = sg_ok
        witness["self_probe_subgame_reason"] = sg_reason
        if not sg_ok:
            fail_w = {**witness, "reason": "self_probe_subgame_invariant_failed", "detail": sg_reason}
            attach_child_diagnostics(fail_w)
            return False, fail_w, 1

    if skip_playwright:
        wasm_rt_ok, wasm_rt_body = True, {"skipped": True, "note": "skip_playwright omits wasm_runtime poll"}
    else:
        wasm_rt_ok, wasm_rt_body = poll_wasm_runtime_closed(ctx.health_port)
    witness["wasm_runtime_closed_ok"] = wasm_rt_ok
    witness["fusion_health_after_wasm_poll"] = wasm_rt_body
    if not wasm_rt_ok:
        fail_w = {**witness, "reason": "wasm_runtime_not_closed"}
        attach_child_diagnostics(fail_w)
        return False, fail_w, 1

    if not skip_playwright:
        bg_ok, bg_reason = wasm_runtime_bindgen_witness_ok(wasm_rt_body)
        witness["wasm_bindgen_path_ok"] = bg_ok
        witness["wasm_bindgen_path_reason"] = bg_reason
        if not bg_ok:
            fail_w = {**witness, "reason": "wasm_runtime_not_bindgen_witness", "detail": bg_reason}
            attach_child_diagnostics(fail_w)
            return False, fail_w, 1

    if skip_playwright:
        witness["playwright_wasm_gate"] = {"skipped": True}
        if child_logs is not None:
            child_logs.close_parent_handles()
        return True, witness, 0

    pw_ok, pw_witness = playwright_wasm_gate(ctx.repo_root, ctx.health_port)
    witness["playwright_wasm_gate"] = pw_witness
    if not pw_ok:
        fail_w = {**witness, "reason": "playwright_wasm_gate_failed"}
        attach_child_diagnostics(fail_w)
        return False, fail_w, 1

    if child_logs is not None:
        child_logs.close_parent_handles()
    return True, witness, 0


def write_kinematic_gate_receipt(
    ctx: GateContext, terminal: str, payload: dict[str, Any], detail: str = ""
) -> Path:
    """Phase 4 artifact: ``evidence/fusion_control/gaiafusion_kinematic_gate_receipt.json``."""
    ctx.evidence_dir.mkdir(parents=True, exist_ok=True)
    path = ctx.evidence_dir / "gaiafusion_kinematic_gate_receipt.json"
    doc: dict[str, Any] = {
        "schema": "gaiaftcl_kinematic_gate_receipt_v1",
        "terminal": terminal,
        "ts_utc": utc_now(),
        "run_id": ctx.run_id,
        "detail": detail,
        "witness": payload,
    }
    path.write_text(json.dumps(doc, indent=2), encoding="utf-8")
    return path


def write_receipt(ctx: GateContext, terminal: str, payload: dict[str, Any]) -> Path:
    ctx.evidence_dir.mkdir(parents=True, exist_ok=True)
    path = ctx.evidence_dir / "fusion_mac_app_gate_receipt.json"
    doc = {
        "schema": "gaiaftcl_fusion_mac_app_gate_receipt_v6",
        "invariant_id": INVARIANT_ID,
        "terminal": terminal,
        "ts_utc": utc_now(),
        "run_id": ctx.run_id,
        "witness": payload,
    }
    path.write_text(json.dumps(doc, indent=2), encoding="utf-8")
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description="Run single mac app build/runtime gate for GaiaFusion.")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1], help="Repository root")
    parser.add_argument(
        "--port",
        type=int,
        default=None,
        help="GaiaFusion LocalServer port (default: ephemeral free port — 8910 is often Next dev:fusion)",
    )
    parser.add_argument("--probe-path", default=PROBE_PATH, help="Health endpoint path")
    parser.add_argument(
        "--skip-playwright",
        action="store_true",
        help="Skip Playwright WASM gate (build + projection only)",
    )
    parser.add_argument(
        "--skip-composite-assets",
        action="store_true",
        help="Do not run build_gaiafusion_composite_assets.sh; require pre-built Resources (default.metallib + fusion-web)",
    )
    args = parser.parse_args()

    repo_root = args.root.resolve()
    project_root = repo_root / BUILD_DIR
    evidence_dir = repo_root / "evidence" / "fusion_control"
    run_id = utc_now().replace(":", "").replace("-", "")
    if args.port is not None:
        fusion_port = args.port
    else:
        # Avoid 8910: Next `dev:fusion` often binds it; hitting the wrong process yields bogus probes (e.g. 404 on /api/fusion/health).
        fusion_port = find_free_tcp_port()

    ctx = GateContext(
        repo_root=repo_root,
        project_root=project_root,
        evidence_dir=evidence_dir,
        run_id=run_id,
        health_port=fusion_port,
        probe_path=args.probe_path,
    )

    ok, payload, rc = run_gate(
        ctx,
        skip_playwright=args.skip_playwright,
        fusion_port=fusion_port,
        skip_composite_assets=args.skip_composite_assets,
    )
    terminal = "CURE" if ok else ("BLOCKED" if rc == 2 else "REFUSED")
    receipt_path = write_receipt(ctx, terminal, payload)
    print(receipt_path)

    if not ok:
        print(f"BLOCKED: {payload.get('reason', 'unknown')}")
        return rc

    if args.skip_playwright:
        print("CURE: GaiaFusion composite + build + runtime gate passed (Playwright skipped)")
    else:
        print("CURE: GaiaFusion composite + build + runtime + Playwright substrate API gate passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
