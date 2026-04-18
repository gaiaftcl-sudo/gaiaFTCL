#!/usr/bin/env python3
from __future__ import annotations

import argparse
import glob
import json
import pathlib
from PIL import Image, ImageStat


def screenshot_candidates(repo_root: pathlib.Path) -> list[pathlib.Path]:
    paths = []
    paths.extend(sorted(glob.glob(str(repo_root / "evidence" / "discord" / "screenshots" / "*" / "*.png"))))
    paths.extend(sorted(glob.glob(str(repo_root / "evidence" / "discord" / "dual_user" / "*" / "*.png"))))
    paths.extend(sorted(glob.glob(str(repo_root / "evidence" / "fusion" / "LATEST_SCREENSHOTS" / "*.png"))))
    return [pathlib.Path(p) for p in paths]


def analyze(path: pathlib.Path) -> dict:
    if not path.exists():
        return {"path": str(path), "ok": False, "reason": "missing"}
    if path.stat().st_size == 0:
        return {"path": str(path), "ok": False, "reason": "empty_file"}
    try:
        with Image.open(path) as img:
            width, height = img.size
            gray = img.convert("L")
            var = ImageStat.Stat(gray).var[0]
    except Exception as exc:
        return {"path": str(path), "ok": False, "reason": f"read_error:{exc}"}

    reasons = []
    if width < 900 or height < 500:
        reasons.append("low_resolution")
    if var < 8.0:
        reasons.append("low_variance_possible_blank")
    inv_path = path.with_suffix(".invariant.json")
    inv_pass = None
    is_discord_shot = "/evidence/discord/screenshots/" in str(path)
    if is_discord_shot and not inv_path.exists():
        reasons.append("invariant_missing")
    elif inv_path.exists():
        try:
            inv = json.loads(inv_path.read_text(encoding="utf-8"))
            inv_pass = bool(inv.get("pass"))
            if not inv_pass:
                reasons.append("invariant_failed")
        except Exception:
            reasons.append("invariant_unreadable")
    return {
        "path": str(path),
        "ok": not reasons,
        "width": width,
        "height": height,
        "variance": round(var, 2),
        "invariant_path": str(inv_path) if inv_path.exists() else None,
        "invariant_pass": inv_pass,
        "reasons": reasons,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo-root", type=pathlib.Path, required=True)
    ap.add_argument("--out-json", type=pathlib.Path, required=True)
    args = ap.parse_args()

    checks = [analyze(p) for p in screenshot_candidates(args.repo_root)]
    ok = [c for c in checks if c.get("ok")]
    bad = [c for c in checks if not c.get("ok")]
    out = {
        "total": len(checks),
        "passed": len(ok),
        "failed": len(bad),
        "valid_screenshots": [c["path"] for c in ok],
        "checks": checks,
    }
    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(out, indent=2), encoding="utf-8")
    print(f"Wrote screenshot validation: {args.out_json}")
    if not ok:
        print("REFUSED: no valid screenshots available")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
