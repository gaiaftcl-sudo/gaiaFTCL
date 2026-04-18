#!/usr/bin/env python3
import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def latest_match(root: Path, pattern: str) -> Path:
    matches = sorted(root.glob(pattern), key=lambda p: p.stat().st_mtime, reverse=True)
    if not matches:
        raise FileNotFoundError(f"missing artifact for pattern: {pattern}")
    return matches[0]


def main() -> int:
    ap = argparse.ArgumentParser(description="Build regulator-grade validation bundle")
    ap.add_argument("--repo-root", required=True, type=Path)
    ap.add_argument("--output", type=Path, default=None)
    args = ap.parse_args()

    repo_root = args.repo_root.resolve()
    ev_discord = repo_root / "evidence" / "discord"
    ev_release = repo_root / "evidence" / "release"
    ev_release.mkdir(parents=True, exist_ok=True)

    required_patterns = {
        "release_witness": (ev_release, "RELEASE_WITNESS_*.json"),
        "dual_user_witness": (ev_discord, "dual_user/*/DUAL_USER_WITNESS.json"),
        "release_report_json": (ev_discord, "RELEASE_REPORT_*.json"),
        "release_report_docx": (ev_discord, "GAIAFTCL_PROD_RELEASE_*.docx"),
        "mesh_health_snapshot": (ev_release, "MESH_HEALTH_SNAPSHOT_*.tsv"),
    }

    artifacts: Dict[str, Path] = {}
    for name, (base, pattern) in required_patterns.items():
        resolved = latest_match(base, pattern)
        artifacts[name] = resolved.resolve()

    dual_user = json.loads(artifacts["dual_user_witness"].read_text(encoding="utf-8"))
    witness = json.loads(artifacts["release_witness"].read_text(encoding="utf-8"))

    criteria = dual_user.get("criteria", {})
    regulator_go = (
        bool(witness.get("all_nine_green"))
        and bool(criteria.get("non_interference"))
        and bool(criteria.get("state_convergence_release_id"))
        and bool(criteria.get("source_diversity"))
        and bool(criteria.get("convergence_lt_2s"))
    )

    packaged: List[Dict[str, str]] = []
    for name, path in artifacts.items():
        packaged.append(
            {
                "name": name,
                "path": str(path.relative_to(repo_root)),
                "sha256": sha256_file(path),
                "bytes": str(path.stat().st_size),
            }
        )

    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out = args.output or (ev_release / f"REGULATOR_VALIDATION_BUNDLE_{ts}.json")
    bundle = {
        "bundle_version": "2026-04-06",
        "generated_at_utc": ts,
        "definition": "GO means third-party regulator can independently validate full deployment + tests.",
        "regulator_go": regulator_go,
        "deployment": {
            "all_nine_green": bool(witness.get("all_nine_green")),
            "row_count": witness.get("row_count"),
        },
        "dual_user": {
            "non_interference": bool(criteria.get("non_interference")),
            "state_convergence_release_id": bool(criteria.get("state_convergence_release_id")),
            "source_diversity": bool(criteria.get("source_diversity")),
            "convergence_lt_2s": bool(criteria.get("convergence_lt_2s")),
            "release_id_user_a": dual_user.get("release_id_user_a") or dual_user.get("user_a", {}).get("release_id"),
            "release_id_user_b": dual_user.get("release_id_user_b") or dual_user.get("user_b", {}).get("release_id"),
            "convergence_ms": dual_user.get("convergence_ms"),
        },
        "artifacts": packaged,
    }
    out.write_text(json.dumps(bundle, indent=2), encoding="utf-8")
    print(str(out))
    return 0 if regulator_go else 1


if __name__ == "__main__":
    raise SystemExit(main())
