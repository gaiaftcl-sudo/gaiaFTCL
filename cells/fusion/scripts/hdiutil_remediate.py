#!/usr/bin/env python3
"""
Detach stale GaiaFusion / hdiutil mounts for the same DMG image-path.
Used by mount_gaiafusion_dmg.sh between attach attempts (Chess Move 1 remediation).
"""
from __future__ import annotations

import argparse
import plistlib
import subprocess
import sys


def _hdiutil_info_plist() -> dict:
    cp = subprocess.run(
        ["hdiutil", "info", "-plist"],
        capture_output=True,
        check=False,
    )
    if cp.returncode != 0 or not cp.stdout:
        return {}
    try:
        return plistlib.loads(cp.stdout)
    except Exception:
        return {}


def detach_mountpoint(mountpoint: str) -> None:
    subprocess.run(
        ["hdiutil", "detach", mountpoint, "-force"],
        capture_output=True,
        check=False,
    )
    subprocess.run(
        ["diskutil", "unmount", "force", mountpoint],
        capture_output=True,
        check=False,
    )


def detach_images_for_dmg(dmg_path: str) -> int:
    """Detach any mounted image whose image-path matches dmg_path. Returns detach count."""
    info = _hdiutil_info_plist()
    images = info.get("images") or []
    if not isinstance(images, list):
        return 0
    count = 0
    dmg_abs = dmg_path
    for img in images:
        if not isinstance(img, dict):
            continue
        ip = str(img.get("image-path") or "").strip()
        if not ip or ip != dmg_abs:
            continue
        ents = img.get("system-entities") or []
        if not isinstance(ents, list):
            continue
        for ent in ents:
            if not isinstance(ent, dict):
                continue
            mp = str(ent.get("mount-point") or "").strip()
            dev = str(ent.get("dev-entry") or "").strip()
            if mp:
                detach_mountpoint(mp)
                count += 1
            elif dev and dev.startswith("/dev/disk"):
                subprocess.run(
                    ["hdiutil", "detach", dev],
                    capture_output=True,
                    check=False,
                )
                count += 1
    return count


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dmg", required=True, help="Absolute path to .dmg (must match hdiutil image-path)")
    ap.add_argument("--mountpoint", default="/Volumes/GaiaFusion")
    args = ap.parse_args()

    detach_mountpoint(args.mountpoint)
    n = detach_images_for_dmg(args.dmg)
    print(f"CALORIE: hdiutil_remediate detach attempts (mountpoint + image-path): {n}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
