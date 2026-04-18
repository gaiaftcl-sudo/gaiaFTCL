#!/usr/bin/env python3
"""Capture a GaiaFusion screenshot with preflight key checks and graceful app lifecycle."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path("/Users/richardgillespie/Documents/FoT8D/GAIAOS")
APP_BIN = ROOT / "macos/GaiaFusion/.build/arm64-apple-macosx/release/GaiaFusion"
PROCESS_MATCH = "GaiaFusion"
SHOT_DIR = ROOT / "evidence/native_fusion/screenshots"
SHOT_DIR.mkdir(parents=True, exist_ok=True)


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        **kwargs,
    )


def require_accessibility() -> None:
    # If this fails, System Events access is blocked for automation.
    proc = run([
        "osascript",
        "-e",
        'tell application "System Events" to get name of every application process',
    ])
    if proc.returncode != 0:
        raise RuntimeError(
            "Accessibility blocked. Add this host process to System Settings › Privacy & Security › Accessibility."
        )


def require_screen_recording() -> None:
    tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
    path = Path(tmp.name)
    tmp.close()
    try:
        proc = run(["/usr/sbin/screencapture", "-x", str(path)])
        if proc.returncode != 0 or not path.exists() or path.stat().st_size == 0:
            raise RuntimeError(
                "Screen Recording permission missing. Enable it in System Settings › Privacy & Security › Screen Recording."
            )
    finally:
        if path.exists():
            try:
                path.unlink()
            except OSError:
                pass


def _running_pids() -> list[int]:
    proc = run(["pgrep", "-f", "GaiaFusion"])
    if proc.returncode != 0:
        return []
    pids: list[int] = []
    for part in proc.stdout.split():
        try:
            pids.append(int(part))
        except ValueError:
            pass
    return pids


def _attempt_graceful_quit() -> None:
    if not _running_pids():
        return
    run(["osascript", "-e", 'tell application "System Events" to tell process "GaiaFusion" to set frontmost to true'])
    time.sleep(0.25)


def clear_existing() -> None:
    # Keep screenshot behavior simple and non-destructive:
    # do not kill the app; reuse the running process if present.
    if _running_pids():
        _attempt_graceful_quit()
        return


def ensure_app_running() -> subprocess.Popen[str] | None:
    if _running_pids():
        return None
    p = subprocess.Popen(
        [str(APP_BIN)],
        cwd=str(APP_BIN.parent),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(2)
    return p


def bring_front() -> None:
    run(["osascript", "-e", 'tell application "System Events" to set frontmost of process "GaiaFusion" to true'])


def assert_window() -> str:
    proc = run([
        "osascript",
        "-e",
        'tell application "System Events" to tell process "GaiaFusion" to get name of window 1',
    ])
    if proc.returncode != 0:
        raise RuntimeError("GaiaFusion window not exposed to Accessibility; cannot confirm visible UI.")
    title = proc.stdout.strip()
    if not title:
        raise RuntimeError("GaiaFusion has no readable window title.")
    return title


def capture_screenshot() -> Path:
    shot = SHOT_DIR / f"fusion_app_{time.strftime('%Y%m%dT%H%M%SZ')}.png"
    proc = run(["/usr/sbin/screencapture", "-x", str(shot)])
    if proc.returncode != 0 or not shot.exists() or shot.stat().st_size == 0:
        raise RuntimeError("screencapture failed even after permission checks.")
    return shot


def main() -> int:
    print("[preflight] testing accessibility + screen capture key")
    try:
        require_accessibility()
        require_screen_recording()
    except RuntimeError as e:
        print(f"BLOCKED: {e}")
        return 2

    clear_existing()
    p = ensure_app_running()
    try:
        try:
            window_title = assert_window()
        except RuntimeError:
            bring_front()
            window_title = assert_window()
        print(f"[app] window=\"{window_title}\"")
        bring_front()
        time.sleep(0.6)
        shot = capture_screenshot()
        print(f"SCREENSHOT: {shot}")
        print(f"SIZE: {shot.stat().st_size}")
        return 0
    except RuntimeError as e:
        print(f"ERROR: {e}")
        return 1
    finally:
        if p is not None and p.poll() is None:
            # keep this operator session alive after capture
            pass


if __name__ == "__main__":
    sys.exit(main())
