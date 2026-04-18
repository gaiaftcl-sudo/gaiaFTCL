#!/usr/bin/env python3
"""
Daily sports betting hunt — manifest-driven, check-in first, then N arbitrary games.

No hardcoded matchups: each calendar day uses manifests/YYYY-MM-DD.json (or --manifest).
Feed odds APIs / scrapers / human JSON into raw_file payloads; the engine stays domain-agnostic.

Typical cron (UTC card reset):
  0 5 * * * cd GAIAOS && VIE_GATEWAY_URL=... GAIAFTCL_INTERNAL_KEY=... \\
    python3 scripts/vie_v2/daily_sports_hunt.py --date $(date -u +%%F)

Init today's empty card from template:
  python3 scripts/vie_v2/daily_sports_hunt.py --init-manifest

Run:
  python3 scripts/vie_v2/daily_sports_hunt.py [--date YYYY-MM-DD] [--dry-run]
"""

from __future__ import annotations

import argparse
import copy
import json
import os
import sys
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

_GAIAOS = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
_MANIFEST_DIR = os.path.join(os.path.dirname(__file__), "manifests")
sys.path.insert(0, os.path.join(_GAIAOS, "services"))

from vie_v2.transformer import InvariantTransformer  # noqa: E402


def _utc_date() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def _manifest_dir() -> str:
    d = os.environ.get("VIE_HUNT_MANIFEST_DIR", "").strip()
    return os.path.abspath(d) if d else os.path.abspath(_MANIFEST_DIR)


def _template_path() -> str:
    return os.path.join(_manifest_dir(), "TEMPLATE.json")


def _default_manifest_path(hunt_date: str) -> str:
    return os.path.join(_manifest_dir(), f"{hunt_date}.json")


def _safe_join_manifest(manifest_dir: str, rel: str) -> str:
    base = os.path.abspath(manifest_dir)
    cand = os.path.abspath(os.path.join(base, rel))
    common = os.path.commonpath([base, cand])
    if common != base:
        raise ValueError(f"raw_file escapes manifest directory: {rel!r}")
    return cand


def _load_json(path: str) -> Dict[str, Any]:
    with open(path, encoding="utf-8") as f:
        out = json.load(f)
    if not isinstance(out, dict):
        raise ValueError(f"expected object in {path}")
    return out


def _prepare_checkin(
    manifest: Dict[str, Any], hunt_date: str
) -> Tuple[str, Dict[str, Any], str, Optional[str]]:
    chk = manifest.get("checkin")
    if not isinstance(chk, dict):
        chk = {}
    schema = str(chk.get("domain_schema_name") or "sports_daily_hunt_checkin").strip()
    raw = copy.deepcopy(chk.get("raw_data")) if isinstance(chk.get("raw_data"), dict) else {}
    session = raw.setdefault("session", {})
    session["hunt_date"] = hunt_date
    sid = str(session.get("session_id") or f"hunt-{hunt_date}")
    if "REPLACE" in sid:
        sid = f"hunt-{hunt_date}"
    session["session_id"] = sid
    entity = str(chk.get("entity_id_override") or "").strip() or sid
    mirror = chk.get("mirror_collection")
    mirror_s = str(mirror).strip() if mirror else None
    return schema, raw, entity, mirror_s


def _resolve_game_raw(manifest_path: str, item: Dict[str, Any]) -> Dict[str, Any]:
    mdir = os.path.dirname(os.path.abspath(manifest_path))
    if "raw_data" in item and isinstance(item["raw_data"], dict):
        return copy.deepcopy(item["raw_data"])
    rel = item.get("raw_file")
    if isinstance(rel, str) and rel.strip():
        path = _safe_join_manifest(mdir, rel.strip())
        return _load_json(path)
    raise ValueError(
        "each games[] entry needs raw_data (object) or raw_file (path relative to manifest)"
    )


def _infer_entity_id(item: Dict[str, Any], raw: Dict[str, Any]) -> str:
    if item.get("entity_id"):
        return str(item["entity_id"]).strip()
    paths = (
        ("player", "id"),
        ("athlete", "id"),
        ("instrument", "instrument_id"),
        ("protein", "protein_id"),
        ("sample", "sample_id"),
    )
    for path in paths:
        d: Any = raw
        ok = True
        for p in path:
            if not isinstance(d, dict):
                ok = False
                break
            d = d.get(p)
        if ok and d is not None and str(d).strip():
            return str(d).strip()
    raise ValueError(
        "games[] entry needs entity_id or a recognizable id field inside raw_data/raw_file"
    )


def _post_gateway(body: Dict[str, Any]) -> Tuple[int, str]:
    gw = os.getenv("VIE_GATEWAY_URL", "").strip()
    key = os.getenv("GAIAFTCL_INTERNAL_KEY", "").strip()
    if not gw or not key:
        return -1, "no gateway (set VIE_GATEWAY_URL + GAIAFTCL_INTERNAL_KEY)"
    try:
        import httpx
    except ImportError:
        return -1, "httpx not installed"
    r = httpx.post(
        f"{gw.rstrip('/')}/vie/ingest",
        json=body,
        headers={"X-Gaiaftcl-Internal-Key": key},
        timeout=120.0,
    )
    return r.status_code, r.text


def _run_ingest(
    *,
    tr: InvariantTransformer,
    schema_name: str,
    raw: Dict[str, Any],
    entity_id: str,
    mirror_collection: Optional[str],
    dry_run: bool,
    label: str,
) -> Dict[str, Any]:
    schema_path = os.path.join(
        _GAIAOS, "services", "vie_v2", "domain_schemas", f"{schema_name}.json"
    )
    domain_schema: Optional[Dict[str, Any]] = None
    if os.path.isfile(schema_path):
        with open(schema_path, encoding="utf-8") as f:
            domain_schema = json.load(f)

    if dry_run and domain_schema is None:
        raise ValueError(
            f"dry-run needs a bundled schema file (or register + use gateway only): {schema_path}"
        )

    vq = None
    if domain_schema is not None:
        vq = tr.map_to_vqbit(raw, domain_schema, entity_id_override=entity_id)

    receipt: Dict[str, Any] = {
        "label": label,
        "entity_id": entity_id,
    }
    if vq is not None:
        receipt["terminal_signal"] = vq.get("terminal_signal")
        receipt["symmetry_break_probability"] = vq.get("symmetry_break_probability")
        receipt["receipt_hash"] = vq.get("receipt_hash")
        receipt["vqbit"] = vq

    if dry_run:
        receipt["gateway_status"] = "dry_run"
        return receipt

    body: Dict[str, Any] = {
        "raw_data": raw,
        "domain_schema_name": schema_name,
        "entity_id": entity_id,
    }
    if mirror_collection:
        body["mirror_collection"] = mirror_collection
    code, text = _post_gateway(body)
    receipt["gateway_http"] = code
    receipt["gateway_body_preview"] = text[:2000]
    if code == 200:
        try:
            gj = json.loads(text)
            if isinstance(gj, dict) and gj.get("vqbit"):
                receipt["gateway_vqbit"] = gj["vqbit"]
        except json.JSONDecodeError:
            pass
    return receipt


def _write_init_manifest(hunt_date: str) -> str:
    tpl = _template_path()
    if not os.path.isfile(tpl):
        raise FileNotFoundError(f"missing template: {tpl}")
    base = _load_json(tpl)
    base["hunt_date"] = hunt_date
    chk = base.setdefault("checkin", {})
    rd = chk.setdefault("raw_data", {})
    sess = rd.setdefault("session", {})
    sess["session_id"] = f"hunt-{hunt_date}"
    sess["hunt_date"] = hunt_date
    out_path = _default_manifest_path(hunt_date)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(base, f, indent=2)
        f.write("\n")
    return out_path


def main() -> int:
    ap = argparse.ArgumentParser(description="VIE daily hunt — check-in + manifest games")
    ap.add_argument("--date", dest="hunt_date", default=None, help="YYYY-MM-DD (default UTC today)")
    ap.add_argument("--manifest", default=None, help="Explicit manifest JSON path")
    ap.add_argument("--dry-run", action="store_true", help="Local transform only; no POST /vie/ingest")
    ap.add_argument("--skip-checkin", action="store_true", help="Ingest games[] only")
    ap.add_argument("--init-manifest", action="store_true", help="Write manifests/DATE.json from TEMPLATE.json")
    args = ap.parse_args()

    hunt_date = (args.hunt_date or _utc_date()).strip()
    if len(hunt_date) != 10 or hunt_date[4] != "-" or hunt_date[7] != "-":
        print("error: --date must be YYYY-MM-DD", file=sys.stderr)
        return 2

    if args.init_manifest:
        path = _write_init_manifest(hunt_date)
        print(json.dumps({"wrote": path, "hunt_date": hunt_date}, indent=2))
        print("Edit games[] and payload JSON files; then run without --init-manifest.")
        return 0

    manifest_path = args.manifest or _default_manifest_path(hunt_date)
    if not os.path.isfile(manifest_path):
        print(
            json.dumps(
                {
                    "error": "manifest_not_found",
                    "path": manifest_path,
                    "hint": f"Run: python3 {sys.argv[0]} --init-manifest --date {hunt_date}",
                },
                indent=2,
            ),
            file=sys.stderr,
        )
        return 1

    manifest = _load_json(manifest_path)
    manifest_date = str(manifest.get("hunt_date") or "").strip()
    if manifest_date and manifest_date != hunt_date:
        print(
            f"warning: manifest hunt_date={manifest_date!r} != --date={hunt_date!r}",
            file=sys.stderr,
        )

    tr = InvariantTransformer()
    receipts: List[Dict[str, Any]] = []

    if not args.skip_checkin:
        schema_c, raw_c, entity_c, mir_c = _prepare_checkin(manifest, hunt_date)
        receipts.append(
            _run_ingest(
                tr=tr,
                schema_name=schema_c,
                raw=raw_c,
                entity_id=entity_c,
                mirror_collection=mir_c,
                dry_run=args.dry_run,
                label="checkin",
            )
        )

    games = manifest.get("games")
    if not isinstance(games, list):
        games = []
    for i, g in enumerate(games):
        if not isinstance(g, dict):
            continue
        label = str(g.get("label") or f"game_{i}").strip()
        schema_name = str(g.get("domain_schema_name") or "").strip()
        if not schema_name:
            print(f"error: games[{i}] missing domain_schema_name", file=sys.stderr)
            return 1
        raw = _resolve_game_raw(manifest_path, g)
        eid = _infer_entity_id(g, raw)
        mir = g.get("mirror_collection")
        mir_s = str(mir).strip() if mir else None
        receipts.append(
            _run_ingest(
                tr=tr,
                schema_name=schema_name,
                raw=raw,
                entity_id=eid,
                mirror_collection=mir_s,
                dry_run=args.dry_run,
                label=label,
            )
        )

    print(json.dumps({"hunt_date": hunt_date, "receipts": receipts}, indent=2, default=str))

    if not args.skip_checkin and receipts:
        c0 = receipts[0]
        print(
            "\nWITNESS: check-in terminal=%s Psb=%s receipt_hash=%s"
            % (
                c0.get("terminal_signal"),
                c0.get("symmetry_break_probability"),
                c0.get("receipt_hash"),
            ),
            flush=True,
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
