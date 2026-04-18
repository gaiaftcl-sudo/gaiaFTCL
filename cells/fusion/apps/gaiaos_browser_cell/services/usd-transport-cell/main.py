#!/usr/bin/env python3
"""
GaiaOS USD Transport Cell (per WorldCell)

Responsibilities:
- Owns and serves the canonical USD layer stack on disk (single-writer of usd/state/live.usdc when pxr is available).
- Broadcasts realtime WS deltas (best-effort) with routing + monotonic revision fields.
- Accepts perception ingress as JSON ops and/or USD overlay layers and persists audit artifacts.

No synthetic/mock data:
- Provider ingestion calls real upstream APIs (NOAA/NWS + AviationWeather) when enabled.
- This service does not fabricate provider outputs; it only transports, persists, and projects.
"""

import asyncio
import json
import hashlib
import logging
import math
import os
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

import aiohttp
from aiohttp import web

from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, generate_latest

from topology_primitives import MobiusProposition, validate_klein_closure
from invariants import default_packs
from schema_validation import validate_schema_obj
from bio_invariants import bio_packs


def _log_level() -> int:
    level = os.getenv("LOG_LEVEL", "INFO").upper().strip()
    return getattr(logging, level, logging.INFO)


logging.basicConfig(
    level=_log_level(),
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger("usd-transport-cell")


PORT = int(os.getenv("PORT", "8790"))
CELL_ID = os.getenv("CELL_ID", "local").strip()

USD_DIR = Path(os.getenv("USD_DIR", "/usd")).resolve()
USD_ROOT = USD_DIR / "root.usda"
LIVE_USDC = USD_DIR / "state" / "live.usdc"
LIVE_USDA_DEBUG = USD_DIR / "state" / "live.usda"
PERCEPTION_DIR = USD_DIR / "perception"
REJECTIONS_DIR = USD_DIR / "rejections"
BIO_DIR = USD_DIR / "bio"
BIO_REJECTIONS_DIR = BIO_DIR / "rejections"
AUDIT_DIR = USD_DIR / "audit"
ARTIFACTS_DIR = USD_DIR / "artifacts"

ARANGO_URL = os.getenv("ARANGO_URL", "http://localhost:8529")
ARANGO_DB = os.getenv("ARANGO_DB", "gaiaos_substrate")
ARANGO_USER = os.getenv("ARANGO_USER", "gaiaos")
ARANGO_PASSWORD = os.getenv("ARANGO_PASSWORD", "gaiaos")
POLL_HZ = float(os.getenv("POLL_HZ", "30"))

# Earth providers (capability-gated; no synthetic data)
ENABLE_NOAA_NWS = os.getenv("ENABLE_NOAA_NWS", "0") == "1"
ENABLE_AVIATION_WEATHER = os.getenv("ENABLE_AVIATION_WEATHER", "0") == "1"

METAR_STATIONS = [s.strip().upper() for s in os.getenv("METAR_STATIONS", "").split(",") if s.strip()]
NWS_POINT_LAT = os.getenv("NWS_POINT_LAT", "").strip()
NWS_POINT_LON = os.getenv("NWS_POINT_LON", "").strip()
NWS_USER_AGENT = os.getenv("NWS_USER_AGENT", "GaiaOS/1.0 (usd-transport-cell)")
WEATHER_POLL_SEC = int(os.getenv("WEATHER_POLL_SEC", "300"))

# ATC providers (real network sources; off unless operator selects a region/airport)
ENABLE_ATC_ADSB = os.getenv("ENABLE_ATC_ADSB", "1") == "1"
ENABLE_ATC_METAR = os.getenv("ENABLE_ATC_METAR", "1") == "1"
ENABLE_ATC_AIRSIGMET = os.getenv("ENABLE_ATC_AIRSIGMET", "1") == "1"
ATC_RADIUS_KM_DEFAULT = float(os.getenv("ATC_RADIUS_KM_DEFAULT", "150"))
ATC_POLL_SEC = float(os.getenv("ATC_POLL_SEC", "2.0"))
# Default to airplanes.live because OpenSky frequently 429s without credentials.
# This is still real data (no synthetic), just a more reliable default source.
ATC_ADSB_SOURCE = os.getenv("ATC_ADSB_SOURCE", "airplanes_live").strip().lower()
ATC_ADSB_FALLBACK_ON_429 = os.getenv("ATC_ADSB_FALLBACK_ON_429", "1") == "1"
OPENSKY_USER = os.getenv("OPENSKY_USER", "").strip()
OPENSKY_PASS = os.getenv("OPENSKY_PASS", "").strip()
ATC_CORRIDOR_PRESET_DEFAULT = os.getenv("ATC_CORRIDOR_PRESET", "NE_FULL").strip().upper()

# airplanes.live (rate-limited 1 req/sec; endpoints documented at https://airplanes.live/api-guide/)
AIRPLANES_LIVE_BASE_URL = os.getenv("AIRPLANES_LIVE_BASE_URL", "https://api.airplanes.live/v2").strip().rstrip("/")

# Prometheus metrics (real-time, no synthetic values)
METRIC_WS_CLIENTS = Gauge("gaiaos_transport_ws_clients", "Connected WebSocket clients")
METRIC_PXR_OK = Gauge("gaiaos_transport_pxr_ok", "1 if pxr is available in this container, else 0")
METRIC_CURRENT_REV = Gauge("gaiaos_transport_current_rev", "Current monotonic revision by world", ["world"])
METRIC_PROVIDER_ENABLED = Gauge("gaiaos_transport_provider_enabled", "1 if provider is enabled by configuration, else 0", ["provider"])
METRIC_PROVIDER_LAST_OK_TS_MS = Gauge("gaiaos_transport_provider_last_ok_ts_ms", "Last successful provider fetch timestamp (ms since epoch)", ["provider"])
METRIC_PERCEPTION_REJECTS = Counter(
    "gaiaos_transport_perception_rejects_total",
    "Total rejected perception ingresses (pre-rev, pre-persist accepted stream)",
    ["world", "reason"],
)
METRIC_PERCEPTION_REJECTS_BY_PACK = Counter(
    "gaiaos_transport_perception_rejects_by_pack_total",
    "Total rejected perception ingresses (labeled by pack)",
    ["world", "reason", "pack_id"],
)


PXR_OK = False
PXR_ERR: Optional[str] = None
try:
    from pxr import Gf, Sdf, Usd, UsdGeom  # type: ignore
    from pxr import UsdShade  # type: ignore

    PXR_OK = True
except Exception as e:  # pragma: no cover
    PXR_OK = False
    PXR_ERR = str(e)

WS_MAX_BATCH_KB = int(os.getenv("WS_MAX_BATCH_KB", "50"))
WS_MAX_BATCH_BYTES = max(8 * 1024, WS_MAX_BATCH_KB * 1024)

TICK_MS = int(os.getenv("TICK_MS", "500"))
WS_REJECT_MAX_BYTES = int(os.getenv("WS_REJECT_MAX_BYTES", "2048"))


def _now_ms() -> int:
    return int(time.time() * 1000)


def _iso8601_now(ts_ms: Optional[int] = None) -> str:
    ms = int(ts_ms) if ts_ms is not None else _now_ms()
    return datetime.fromtimestamp(ms / 1000.0, tz=timezone.utc).isoformat().replace("+00:00", "Z")


def _ensure_dirs() -> None:
    (USD_DIR / "state").mkdir(parents=True, exist_ok=True)
    (USD_DIR / "worlds").mkdir(parents=True, exist_ok=True)
    PERCEPTION_DIR.mkdir(parents=True, exist_ok=True)
    REJECTIONS_DIR.mkdir(parents=True, exist_ok=True)
    BIO_DIR.mkdir(parents=True, exist_ok=True)
    BIO_REJECTIONS_DIR.mkdir(parents=True, exist_ok=True)
    AUDIT_DIR.mkdir(parents=True, exist_ok=True)
    ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)


def _world_key(world: str) -> str:
    if world not in ("Cell", "Human", "Astro"):
        return "Astro"
    return world


def _find_repo_root(start: Path) -> Path:
    p = start.resolve()
    for candidate in [p, *p.parents]:
        if (candidate / ".git").exists():
            return candidate
        if (candidate / "doc" / "schemas").is_dir() and (candidate / "apps").is_dir():
            return candidate
    return p.parents[-1]


REPO_ROOT = _find_repo_root(Path(__file__))
SCHEMA_DIR = (REPO_ROOT / "doc" / "schemas").resolve()


def _load_json_schema(schema_dir: Path, rel_path: str) -> Tuple[bool, Optional[dict], List[dict]]:
    base = schema_dir.resolve()
    schema_path = (base / rel_path).resolve()
    try:
        schema_path.relative_to(base)
    except Exception:
        return (
            False,
            None,
            [{"pack": "schema", "code": "SCHEMA_PATH_INVALID", "message": "schema path invalid", "path": "/", "value": rel_path, "expected": str(base)}],
        )

    if not schema_path.exists():
        return (
            False,
            None,
            [{"pack": "schema", "code": "SCHEMA_NOT_FOUND", "message": "schema file not found", "path": "/", "value": str(schema_path), "expected": rel_path}],
        )

    try:
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
        return True, schema, []
    except Exception as e:
        return (
            False,
            None,
            [{"pack": "schema", "code": "SCHEMA_LOAD_FAILED", "message": "schema load failed", "path": "/", "value": str(e), "expected": rel_path}],
        )


@dataclass
class RevState:
    current_rev: Dict[str, int]

    def bump(self, world: str) -> int:
        w = _world_key(world)
        self.current_rev[w] = int(self.current_rev.get(w, 0)) + 1
        return self.current_rev[w]


@dataclass
class TransportState:
    clients: Set[web.WebSocketResponse]
    connected_clients: int
    pxr_ok: bool
    pxr_error: Optional[str]
    rev: RevState
    last_frame_id: Dict[str, Any]
    provider_status: Dict[str, Any]
    atc_region: Optional[Dict[str, Any]]
    aircraft_last_seen_ms: Dict[str, int]
    metar_last_ok_ms: Dict[str, int]


STATE = TransportState(
    clients=set(),
    connected_clients=0,
    pxr_ok=PXR_OK,
    pxr_error=PXR_ERR,
    rev=RevState(current_rev={"Cell": 0, "Human": 0, "Astro": 0}),
    last_frame_id={"Cell": None, "Human": None, "Astro": None},
    provider_status={
        "noaa_nws": {"enabled": ENABLE_NOAA_NWS, "last_ok_ts": None, "last_error": None},
        "aviation_weather": {"enabled": ENABLE_AVIATION_WEATHER, "last_ok_ts": None, "last_error": None},
        "atc_adsb": {"enabled": ENABLE_ATC_ADSB, "last_ok_ts": None, "last_error": None, "source": ATC_ADSB_SOURCE},
        "atc_metar": {"enabled": ENABLE_ATC_METAR, "last_ok_ts": None, "last_error": None},
        "atc_airsigmet": {"enabled": ENABLE_ATC_AIRSIGMET, "last_ok_ts": None, "last_error": None},
    },
    atc_region=None,
    aircraft_last_seen_ms={},
    metar_last_ok_ms={},
)


def _audit_write(event: dict) -> None:
    AUDIT_DIR.mkdir(parents=True, exist_ok=True)
    p = AUDIT_DIR / "audit.jsonl"
    line = json.dumps(event, separators=(",", ":"), ensure_ascii=False)
    with p.open("a", encoding="utf-8") as f:
        f.write(line + "\n")


def _op_id() -> str:
    return str(uuid.uuid4())

def _sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _canonicalize_for_digest(obj: Any) -> Any:
    """
    Canonicalize nested JSON-like objects for stable hashing:
    - dict keys sorted by json.dumps(sort_keys=True)
    - floats rounded to 6 decimals to avoid jitter
    - lists preserved in order
    """
    if obj is None:
        return None
    if isinstance(obj, bool):
        return obj
    if isinstance(obj, int):
        return obj
    if isinstance(obj, float):
        return round(float(obj), 6)
    if isinstance(obj, str):
        return obj
    if isinstance(obj, list):
        return [_canonicalize_for_digest(x) for x in obj]
    if isinstance(obj, dict):
        return {str(k): _canonicalize_for_digest(v) for k, v in obj.items()}
    # Fallback: represent unknown values deterministically.
    return str(obj)


def _canonical_json_bytes(obj: Any) -> bytes:
    canon = _canonicalize_for_digest(obj)
    return json.dumps(canon, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def _write_unique_json(path_base: Path, payload: Any) -> Path:
    """
    Append-only file writer: never overwrites.
    If the target already exists, suffix with _<n>.
    """
    path_base.parent.mkdir(parents=True, exist_ok=True)
    data = json.dumps(payload, indent=2, ensure_ascii=False).encode("utf-8")
    if not path_base.exists():
        path_base.write_bytes(data)
        return path_base
    for i in range(1, 10_000):
        p = path_base.with_name(f"{path_base.stem}_{i}{path_base.suffix}")
        if p.exists():
            continue
        p.write_bytes(data)
        return p
    raise RuntimeError("failed_to_write_unique_artifact")


def _append_rejection_index(entry: dict) -> None:
    """
    Append-only ndjson index for rejected perception ingresses.
    One JSON object per line for fast audit tooling.
    """
    REJECTIONS_DIR.mkdir(parents=True, exist_ok=True)
    p = REJECTIONS_DIR / "rejections.ndjson"
    line = json.dumps(entry, separators=(",", ":"), ensure_ascii=False)
    with p.open("a", encoding="utf-8") as f:
        f.write(line + "\n")


def _append_bio_rejection_index(entry: dict) -> None:
    BIO_REJECTIONS_DIR.mkdir(parents=True, exist_ok=True)
    p = BIO_REJECTIONS_DIR / "rejections.ndjson"
    line = json.dumps(entry, separators=(",", ":"), ensure_ascii=False)
    with p.open("a", encoding="utf-8") as f:
        f.write(line + "\n")


def _request_op_id(body: dict, ops: List[dict], payload_digest: str) -> str:
    rid = body.get("op_id")
    if isinstance(rid, str) and rid.strip():
        return rid.strip()
    for op in ops:
        if isinstance(op, dict):
            oid = op.get("op_id")
            if isinstance(oid, str) and oid.strip():
                return oid.strip()
    return payload_digest


def _reject_perception(
    *,
    body: dict,
    world: str,
    ops: List[dict],
    ts: int,
    reason: str,
    pack_id: str,
    detail: dict,
) -> web.Response:
    payload_digest = _sha256_hex(
        _canonical_json_bytes(
            {
                "world": world,
                "ops": ops,
                "provenance": body.get("provenance", {}),
                "reason": reason,
                "pack_id": pack_id,
                "detail": detail,
            }
        )
    )[:16]
    op_id = _request_op_id(body, ops, payload_digest)

    record = {
        "ts": ts,
        "cell_id": CELL_ID,
        "world": world,
        "op_id": op_id,
        "reason": reason,
        "pack_id": pack_id,
        "payload_digest": payload_digest,
        "ops_count": len(ops),
        "detail": detail,
        "provenance": body.get("provenance", {}),
        "request": body,
    }

    detail_out = dict(detail or {})
    if "violations" not in detail_out:
        tears = detail_out.get("tears")
        if isinstance(tears, list):
            detail_out["violations"] = [{"pack": pack_id, "code": "TEAR", "message": str(t)} for t in tears[:50]]
        else:
            detail_out["violations"] = [{"pack": pack_id, "code": "REJECT", "message": "rejected"}]

    rejected = {
        "accepted": False,
        "reason": reason,
        "pack_id": pack_id,
        "detail": {"violations": detail_out.get("violations", [])},
        "not_truth": True,
        "overlayKind": "counterfactual",
        "cell_id": CELL_ID,
        "world": world,
        "ts": _iso8601_now(ts),
        "ts_ms": ts,
        "op_id": op_id,
        "payload_digest": payload_digest,
        "contract_version": "perception_reject/1.0",
    }

    try:
        fname_base = REJECTIONS_DIR / f"{ts}_{op_id}_{payload_digest}.json"
        fname = _write_unique_json(fname_base, record)
        rejected["stored"] = str(fname)
        try:
            _append_rejection_index(
                {
                    "ts": ts,
                    "cell_id": CELL_ID,
                    "world": world,
                    "op_id": op_id,
                    "reason": reason,
                    "pack_id": pack_id,
                    "payload_digest": payload_digest,
                    "file": str(fname),
                    "ops_count": len(ops),
                }
            )
        except Exception:
            pass
    except Exception:
        pass

    try:
        METRIC_PERCEPTION_REJECTS.labels(world=world, reason=reason).inc()
    except Exception:
        pass
    try:
        METRIC_PERCEPTION_REJECTS_BY_PACK.labels(world=world, reason=reason, pack_id=pack_id).inc()
    except Exception:
        pass

    _audit_write({"ts": ts, "event": "perception_rejected", "cell_id": CELL_ID, "world": world, "op_id": op_id, "payload_digest": payload_digest, "reason": reason, "pack_id": pack_id})

    async def _broadcast_reject() -> None:
        env = {
            "type": "perception_rejected",
            "not_truth": True,
            "cell_id": CELL_ID,
            "world": world,
            "ts": _iso8601_now(ts),
            "ts_ms": ts,
            "payload_digest": payload_digest,
            "reason": reason,
            "pack_id": pack_id,
            "op_id": op_id,
            "contract_version": "ws_reject_preview/1.0",
        }
        # Attach a small preview for UI visibility without inflating WS payloads.
        try:
            viols = detail_out.get("violations")
            if isinstance(viols, list):
                env["violations_preview"] = viols[:3]
        except Exception:
            pass
        try:
            size = len(json.dumps(env, separators=(",", ":"), ensure_ascii=False).encode("utf-8"))
            if size > WS_REJECT_MAX_BYTES:
                logger.warning("perception_rejected envelope too large: %s bytes", size)
        except Exception:
            pass
        await _broadcast(env)

    try:
        asyncio.create_task(_broadcast_reject())
    except Exception:
        pass

    return web.json_response(rejected, status=422)


def _reject_bio(
    *,
    body: dict,
    world: str,
    ops: List[dict],
    ts: int,
    reason: str,
    pack_id: str,
    violations: List[dict],
) -> web.Response:
    payload_digest = _sha256_hex(
        _canonical_json_bytes(
            {
                "world": world,
                "ops": ops,
                "entity_kind": body.get("entity_kind"),
                "provenance": body.get("provenance", {}),
                "reason": reason,
                "pack_id": pack_id,
                "violations": violations,
            }
        )
    )[:16]
    op_id = _request_op_id(body, ops, payload_digest)

    record = {
        "ts": ts,
        "cell_id": CELL_ID,
        "world": world,
        "op_id": op_id,
        "reason": reason,
        "pack_id": pack_id,
        "payload_digest": payload_digest,
        "ops_count": len(ops),
        "detail": {"violations": violations},
        "provenance": body.get("provenance", {}),
        "request": body,
    }

    rejected = {
        "accepted": False,
        "reason": reason,
        "pack_id": pack_id,
        "detail": {"violations": violations},
        "cell_id": CELL_ID,
        "world": world,
        "ts": _iso8601_now(ts),
        "ts_ms": ts,
        "op_id": op_id,
        "payload_digest": payload_digest,
        "contract_version": "perception_reject/1.0",
    }

    try:
        fname_base = BIO_REJECTIONS_DIR / f"{ts}_{op_id}_{payload_digest}.json"
        fname = _write_unique_json(fname_base, record)
        rejected["stored"] = str(fname)
        try:
            _append_bio_rejection_index(
                {
                    "ts": ts,
                    "cell_id": CELL_ID,
                    "world": world,
                    "op_id": op_id,
                    "reason": reason,
                    "pack_id": pack_id,
                    "payload_digest": payload_digest,
                    "file": str(fname),
                    "ops_count": len(ops),
                }
            )
        except Exception:
            pass
    except Exception:
        pass

    try:
        METRIC_PERCEPTION_REJECTS.labels(world=world, reason=reason).inc()
    except Exception:
        pass
    try:
        METRIC_PERCEPTION_REJECTS_BY_PACK.labels(world=world, reason=reason, pack_id=pack_id).inc()
    except Exception:
        pass

    async def _broadcast_reject() -> None:
        env = {
            "type": "perception_rejected",
            "cell_id": CELL_ID,
            "world": world,
            "ts": _iso8601_now(ts),
            "ts_ms": ts,
            "payload_digest": payload_digest,
            "reason": reason,
            "pack_id": pack_id,
            "op_id": op_id,
            "violations_preview": violations[:3],
            "contract_version": "ws_reject_preview/1.0",
        }
        await _broadcast(env)

    try:
        asyncio.create_task(_broadcast_reject())
    except Exception:
        pass

    return web.json_response(rejected, status=422)


def _run_invariant_packs(world: str, ops: List[dict]) -> List[dict]:
    violations: List[dict] = []
    for pack in default_packs():
        for v in pack.check(world=world, ops=ops):
            violations.append({"pack": pack.name, "code": v.code, "message": v.message, "path": v.path, "name": v.name})
    return violations


async def post_bio_perception(request: web.Request) -> web.Response:
    raw = await request.read()
    if len(raw) > 2_000_000:
        return _reject_bio(
            body={"world": "bio", "entity_kind": "discovery", "ops": [], "provenance": {}, "op_id": "", "raw_bytes": len(raw)},
            world="bio",
            ops=[],
            ts=_now_ms(),
            reason="schema_reject",
            pack_id="schema",
            violations=[
                {
                    "pack": "schema",
                    "code": "SIZE",
                    "message": "payload too large",
                    "path": "/",
                    "value": len(raw),
                    "expected": "<= 2000000",
                }
            ],
        )
    try:
        body = json.loads(raw.decode("utf-8"))
    except Exception:
        return web.json_response({"error": "invalid json"}, status=400)

    ops = body.get("ops", [])
    if not isinstance(ops, list):
        ops = []

    if len(ops) > 500:
        return _reject_bio(
            body=body,
            world=str(body.get("world") or "bio"),
            ops=ops,
            ts=_now_ms(),
            reason="invariant_reject",
            pack_id="rate_and_size",
            violations=[{"pack": "rate_and_size", "code": "OPS_COUNT", "message": "too many ops", "path": "/ops", "value": len(ops), "expected": "<= 500"}],
        )
    unique_paths = {str(o.get("path") or "") for o in ops if isinstance(o, dict)}
    if len(unique_paths) > 300:
        return _reject_bio(
            body=body,
            world=str(body.get("world") or "bio"),
            ops=ops,
            ts=_now_ms(),
            reason="invariant_reject",
            pack_id="rate_and_size",
            violations=[{"pack": "rate_and_size", "code": "UNIQUE_PATHS", "message": "too many unique paths", "path": "/ops", "value": len(unique_paths), "expected": "<= 300"}],
        )

    rel = os.getenv("BIO_SCHEMA_REL", "bio_ingress_envelope.schema.json")
    ok, schema, load_violations = _load_json_schema(SCHEMA_DIR, rel)
    if not ok or schema is None:
        return _reject_bio(body=body, world=str(body.get("world") or "bio"), ops=ops, ts=_now_ms(), reason="schema_reject", pack_id="schema", violations=load_violations)

    schema_violations = validate_schema_obj(body, schema, pack="schema")
    if schema_violations:
        viols = [{"pack": "schema", "code": v.code, "message": v.message, "path": v.path, "name": v.name, "value": v.value, "expected": v.expected} for v in schema_violations]
        ops = body.get("ops", [])
        if not isinstance(ops, list):
            ops = []
        return _reject_bio(body=body, world=str(body.get("world") or "bio"), ops=ops, ts=_now_ms(), reason="schema_reject", pack_id="schema", violations=viols)

    world = str(body.get("world") or "bio")

    # Bio invariant packs (cheap, deterministic). Reject before any downstream compute.
    viols = bio_packs(body, ops)
    if viols:
        pack_id = str((viols[0] or {}).get("pack") or "invariant")
        return _reject_bio(body=body, world=world, ops=ops, ts=_now_ms(), reason="invariant_reject", pack_id=pack_id, violations=viols)

    # Accept path: append-only accepted record (no synthetic). Keep cheap and auditable.
    ts = _now_ms()
    op_id = str(body.get("op_id") or "")
    try:
        out_dir = BIO_DIR / "accepted"
        out_dir.mkdir(parents=True, exist_ok=True)
        fname_base = out_dir / f"{ts}_{op_id or 'bio'}_accepted.json"
        fname = _write_unique_json(fname_base, body)
    except Exception:
        fname = None

    return web.json_response({"ok": True, "stored": str(fname) if fname else None, "ts": ts})


def _extract_klein_propositions(ops: List[dict]) -> List[MobiusProposition]:
    """
    Convert incoming perception ops into a deterministic proposition set for Klein closure validation.
    Validation is pure and local: no network calls, no USD reads.
    """

    props: List[MobiusProposition] = []
    for op in ops:
        kind = str(op.get("op") or "")
        path = op.get("path")
        if not isinstance(path, str) or not path:
            continue

        if kind == "SetAttr":
            name = op.get("name")
            if not isinstance(name, str) or not name:
                continue
            props.append(
                MobiusProposition(
                    subject=path,
                    object=name,
                    value=op.get("value"),
                    orientation=1,
                    meta={"op_id": str(op.get("op_id") or "")},
                )
            )
            continue

        if kind == "SetXform":
            translate = op.get("translate")
            orient = op.get("orient")
            scale = op.get("scale")

            def _q(v: Any) -> Any:
                if isinstance(v, (int, float)):
                    return round(float(v), 4)
                return v

            if isinstance(translate, list) and len(translate) == 3:
                props.append(MobiusProposition(subject=path, object="xform:translate", value=[_q(x) for x in translate], orientation=1, meta={"op_id": str(op.get("op_id") or "")}))
            if isinstance(orient, list) and len(orient) == 4:
                props.append(MobiusProposition(subject=path, object="xform:orient", value=[_q(x) for x in orient], orientation=1, meta={"op_id": str(op.get("op_id") or "")}))
            if isinstance(scale, list) and len(scale) == 3:
                props.append(MobiusProposition(subject=path, object="xform:scale", value=[_q(x) for x in scale], orientation=1, meta={"op_id": str(op.get("op_id") or "")}))
            continue

    return props


def _klein_validate_ops(ops: List[dict]) -> Tuple[bool, List[str]]:
    props = _extract_klein_propositions(ops)
    ok, tears = validate_klein_closure(props)
    return bool(ok), list(tears)


def _validate_op(op: dict) -> None:
    if "op" not in op:
        raise ValueError("op missing")
    if "op_id" not in op:
        raise ValueError("op_id missing")
    if "path" in op and not isinstance(op["path"], str):
        raise ValueError("path must be string")


def _ensure_live_layer() -> None:
    if not PXR_OK:
        return
    if LIVE_USDC.exists():
        return
    LIVE_USDC.parent.mkdir(parents=True, exist_ok=True)
    layer = Sdf.Layer.CreateNew(str(LIVE_USDC))
    if layer is None:
        raise RuntimeError("failed to create live.usdc")
    layer.Save()


def _geo_origin_wgs84() -> Tuple[float, float, float]:
    """
    Returns (lat, lon, alt_m) origin for local tangent plane transforms.
    If NWS_POINT_LAT/LON are configured, use them; otherwise default to (0,0,0).
    """
    try:
        if NWS_POINT_LAT and NWS_POINT_LON:
            return float(NWS_POINT_LAT), float(NWS_POINT_LON), 0.0
    except Exception:
        pass
    return 0.0, 0.0, 0.0


def _wgs84_to_local_enu_m(lat: float, lon: float, alt_m: float, origin: Tuple[float, float, float]) -> Tuple[float, float, float]:
    """
    Lightweight local tangent plane approximation (ENU) around origin.
    No external deps; good enough for UI-scale geospatial placement.
    """
    # Earth radius in meters (spherical approximation)
    r = 6_371_000.0
    lat0, lon0, alt0 = origin
    # radians
    lat_r = (lat * 3.141592653589793) / 180.0
    lon_r = (lon * 3.141592653589793) / 180.0
    lat0_r = (lat0 * 3.141592653589793) / 180.0
    lon0_r = (lon0 * 3.141592653589793) / 180.0

    dlat = lat_r - lat0_r
    dlon = lon_r - lon0_r

    east = dlon * r * math.cos(lat0_r)
    north = dlat * r
    up = (alt_m - alt0)
    # Our stage uses Y-up; map ENU -> (X=east, Y=up, Z=north)
    return float(east), float(up), float(north)


def _ensure_stage_geospatial_and_materials(stage: "Usd.Stage") -> None:
    """
    Apple USDZ-style: compact metadata + embedded UsdPreviewSurface materials.
    Only runs when pxr is available.
    """
    if not PXR_OK:
        return

    # Stage-level conventions
    stage.SetMetadata("metersPerUnit", 1.0)
    stage.SetMetadata("upAxis", "Y")

    root = stage.GetPrimAtPath("/GaiaOS")
    if root and root.IsValid():
        # Lightweight geospatial metadata (customData avoids schema dependency).
        origin = _geo_origin_wgs84()
        root.SetCustomDataByKey("geospatial:crs", "EPSG:4326")
        root.SetCustomDataByKey("geospatial:origin_wgs84", [origin[0], origin[1], origin[2]])
        root.SetCustomDataByKey("geospatial:origin_note", "WGS84 (lat,lon,alt_m) origin for local ENU placement")

    # Embedded material (UsdPreviewSurface)
    mat_path = "/GaiaOS/Materials/WeatherStation"
    shader_path = f"{mat_path}/PBRShader"

    mat_prim = stage.GetPrimAtPath(mat_path)
    if mat_prim and mat_prim.IsValid():
        return

    material = UsdShade.Material.Define(stage, mat_path)
    shader = UsdShade.Shader.Define(stage, shader_path)
    shader.CreateIdAttr("UsdPreviewSurface")
    shader.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(0.0, 1.0, 0.53))
    shader.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(0.4)
    shader.CreateInput("metallic", Sdf.ValueTypeNames.Float).Set(0.0)
    material.CreateSurfaceOutput().ConnectToSource(shader.ConnectableAPI(), "surface")


def _upsert_weather_station_usd(
    stage: "Usd.Stage",
    station_id: str,
    lat: float,
    lon: float,
    alt_m: float,
    asset_uri: str,
    raw_metar: str,
) -> None:
    """
    Create proper UsdGeom prims for weather stations with material binding and compact customData.
    """
    if not PXR_OK:
        return

    origin = _geo_origin_wgs84()
    x, y, z = _wgs84_to_local_enu_m(lat, lon, alt_m, origin)

    base = f"/GaiaOS/Worlds/Human/Weather/Stations/{station_id}"
    xform = UsdGeom.Xform.Define(stage, base)
    prim = xform.GetPrim()
    prim.SetMetadata("kind", "component")
    prim.SetCustomDataByKey("geospatial:latitude", float(lat))
    prim.SetCustomDataByKey("geospatial:longitude", float(lon))
    prim.SetCustomDataByKey("geospatial:alt_m", float(alt_m))
    prim.SetCustomDataByKey("weather:station", station_id)
    prim.SetCustomDataByKey("weather:asset", asset_uri)

    ops_existing = xform.GetOrderedXformOps()
    t_op = ops_existing[0] if len(ops_existing) > 0 else xform.AddTranslateOp()
    t_op.Set(Gf.Vec3d(x, y, z))

    sphere_path = f"{base}/Marker"
    sphere = UsdGeom.Sphere.Define(stage, sphere_path)
    sphere.GetRadiusAttr().Set(5.0)

    # Also keep raw METAR as a compact customData field (avoid giant attribute churn).
    sphere.GetPrim().SetCustomDataByKey("weather:raw_metar", raw_metar[:2048])

    # Bind material (UsdPreviewSurface)
    mat_prim = stage.GetPrimAtPath("/GaiaOS/Materials/WeatherStation")
    if mat_prim and mat_prim.IsValid():
        material = UsdShade.Material(mat_prim)
        UsdShade.MaterialBindingAPI(sphere.GetPrim()).Bind(material)


def _open_stage() -> "Usd.Stage":
    if not PXR_OK:
        raise RuntimeError(f"pxr missing: {PXR_ERR}")
    if not USD_ROOT.exists():
        raise RuntimeError(f"missing USD root: {USD_ROOT}")
    _ensure_live_layer()
    stage = Usd.Stage.Open(str(USD_ROOT))
    if not stage:
        raise RuntimeError("failed to open USD stage")
    live_layer = Sdf.Layer.FindOrOpen(str(LIVE_USDC))
    if live_layer is None:
        live_layer = Sdf.Layer.CreateNew(str(LIVE_USDC))
    stage.SetEditTarget(live_layer)
    return stage


def _apply_ops_to_usd(stage: "Usd.Stage", ops: List[dict]) -> None:
    for op in ops:
        _validate_op(op)
        kind = op["op"]
        if kind == "UpsertPrim":
            prim_type = op.get("primType", "Xform")
            stage.DefinePrim(op["path"], prim_type)
        elif kind == "SetXform":
            prim = stage.GetPrimAtPath(op["path"])
            if not prim or not prim.IsValid():
                prim = stage.DefinePrim(op["path"], "Xform")
            xf = UsdGeom.Xformable(prim)
            ops_existing = xf.GetOrderedXformOps()
            t_op = ops_existing[0] if len(ops_existing) > 0 else xf.AddTranslateOp()
            o_op = ops_existing[1] if len(ops_existing) > 1 else xf.AddOrientOp()
            s_op = ops_existing[2] if len(ops_existing) > 2 else xf.AddScaleOp()
            if "translate" in op:
                t = op["translate"]
                t_op.Set(Gf.Vec3d(t[0], t[1], t[2]))
            if "orient" in op:
                q = op["orient"]  # [x,y,z,w]
                o_op.Set(Gf.Quatd(q[3], Gf.Vec3d(q[0], q[1], q[2])))
            if "scale" in op:
                s = op["scale"]
                s_op.Set(Gf.Vec3d(s[0], s[1], s[2]))
        elif kind == "SetAttr":
            prim = stage.GetPrimAtPath(op["path"])
            if not prim or not prim.IsValid():
                prim = stage.DefinePrim(op["path"], "Xform")
            name = op["name"]
            value = op["value"]
            vt = op.get("valueType", "float").lower()
            if vt in ("float", "double"):
                attr = prim.GetAttribute(name) or prim.CreateAttribute(name, Sdf.ValueTypeNames.Float)
                attr.Set(float(value))
            elif vt == "int":
                attr = prim.GetAttribute(name) or prim.CreateAttribute(name, Sdf.ValueTypeNames.Int)
                attr.Set(int(value))
            elif vt == "string":
                attr = prim.GetAttribute(name) or prim.CreateAttribute(name, Sdf.ValueTypeNames.String)
                attr.Set(str(value))
            elif vt == "bool":
                attr = prim.GetAttribute(name) or prim.CreateAttribute(name, Sdf.ValueTypeNames.Bool)
                attr.Set(bool(value))
            else:
                attr = prim.GetAttribute(name) or prim.CreateAttribute(name, Sdf.ValueTypeNames.String)
                attr.Set(str(value))
        elif kind == "RemovePrim":
            stage.RemovePrim(op["path"])
        elif kind == "SetActive":
            prim = stage.GetPrimAtPath(op["path"])
            if prim and prim.IsValid():
                prim.SetActive(bool(op["active"]))
        elif kind == "SetVariant":
            prim = stage.GetPrimAtPath(op["path"])
            if prim and prim.IsValid():
                vset = prim.GetVariantSets().GetVariantSet(op["variantSet"])
                if vset:
                    vset.SetVariantSelection(op["selection"])
        elif kind == "AddRelationship":
            prim = stage.GetPrimAtPath(op["path"])
            if prim and prim.IsValid():
                rel = prim.GetRelationship(op["relName"]) or prim.CreateRelationship(op["relName"])
                rel.AddTarget(op["targetPath"])
        elif kind == "SwitchWorld":
            # UI-scoped hint. MUST NOT mutate world truth state here.
            continue
        else:
            continue


async def _broadcast(envelope: dict) -> None:
    dead: List[web.WebSocketResponse] = []
    msg = json.dumps(envelope, separators=(",", ":"), ensure_ascii=False)
    for ws in list(STATE.clients):
        try:
            await ws.send_str(msg)
        except Exception:
            dead.append(ws)
    for ws in dead:
        STATE.clients.discard(ws)
    STATE.connected_clients = len(STATE.clients)


def _chunk_ops_for_ws(envelope_base: dict, ops: List[dict]) -> List[dict]:
    """
    Omniverse-style batching: split a large ops list into multiple envelopes under a max payload size.
    Keeps `type=usd_deltas` so existing clients continue to work.
    """
    if not ops:
        return []

    out: List[dict] = []
    cur: List[dict] = []
    cur_bytes = 0

    def op_size(o: dict) -> int:
        try:
            return len(json.dumps(o, separators=(",", ":"), ensure_ascii=False).encode("utf-8"))
        except Exception:
            return 256

    for op in ops:
        s = op_size(op)
        # flush if adding would exceed
        if cur and (cur_bytes + s) > WS_MAX_BATCH_BYTES:
            out.append(cur)
            cur = []
            cur_bytes = 0
        cur.append(op)
        cur_bytes += s

    if cur:
        out.append(cur)

    envelopes: List[dict] = []
    total = len(out)
    for idx, chunk in enumerate(out):
        e = dict(envelope_base)
        e["ops"] = chunk
        if total > 1:
            e["batch"] = {"index": idx, "count": total, "max_bytes": WS_MAX_BATCH_BYTES}
        envelopes.append(e)
    return envelopes


async def _broadcast_ops(envelope_base: dict, ops: List[dict]) -> None:
    for env in _chunk_ops_for_ws(envelope_base, ops):
        await _broadcast(env)


async def ws_handler(request: web.Request) -> web.WebSocketResponse:
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    STATE.clients.add(ws)
    STATE.connected_clients = len(STATE.clients)
    _audit_write({"ts": _now_ms(), "event": "ws_connect", "cell_id": CELL_ID})
    try:
        async for msg in ws:
            if msg.type != aiohttp.WSMsgType.TEXT:
                continue
            try:
                data = json.loads(msg.data)
            except Exception:
                continue
            if data.get("type") == "ping":
                await ws.send_json({"type": "pong", "ts": _now_ms()})
    finally:
        STATE.clients.discard(ws)
        STATE.connected_clients = len(STATE.clients)
        _audit_write({"ts": _now_ms(), "event": "ws_disconnect", "cell_id": CELL_ID})
    return ws


async def health(_: web.Request) -> web.Response:
    status = "healthy" if STATE.pxr_ok else "degraded"
    return web.json_response(
        {
            "status": status,
            "cell_id": CELL_ID,
            "pxr_ok": STATE.pxr_ok,
            "ws_clients": STATE.connected_clients,
        }
    )


async def capabilities(_: web.Request) -> web.Response:
    return web.json_response(
        {
            "cell_id": CELL_ID,
            "usd_http_layers": True,
            "usd_ws_deltas": True,
            "usd_write_live_usdc": bool(STATE.pxr_ok),
            "perception_json_ops": True,
            "perception_usd_overlay": True,
            "current_rev": dict(STATE.rev.current_rev),
            # Earth data providers (capability-switched, must be honest).
            "noaa_weather": bool(ENABLE_NOAA_NWS),
            "aviation_weather": bool(ENABLE_AVIATION_WEATHER),
            "atc_adsb": bool(ENABLE_ATC_ADSB),
            "atc_metar": bool(ENABLE_ATC_METAR),
            "atc_airsigmet": bool(ENABLE_ATC_AIRSIGMET),
            "open_satellite": False,
            "earth_engine": False,
            "earth_engine_mode": "disabled_prelaunch",
            "truth_source": "arango_substrate_frames",
            "atc_region": STATE.atc_region,
            "provider_status": STATE.provider_status,
        }
    )

async def metrics(_: web.Request) -> web.Response:
    # Update gauges from live state.
    METRIC_WS_CLIENTS.set(float(STATE.connected_clients))
    METRIC_PXR_OK.set(1.0 if STATE.pxr_ok else 0.0)
    for w, r in STATE.rev.current_rev.items():
        METRIC_CURRENT_REV.labels(world=w).set(float(r))

    # Provider status is optional; export enabled + last_ok_ts when present.
    METRIC_PROVIDER_ENABLED.labels(provider="aviation_weather").set(1.0 if ENABLE_AVIATION_WEATHER else 0.0)
    METRIC_PROVIDER_ENABLED.labels(provider="noaa_nws").set(1.0 if ENABLE_NOAA_NWS else 0.0)
    METRIC_PROVIDER_ENABLED.labels(provider="atc_adsb").set(1.0 if ENABLE_ATC_ADSB else 0.0)
    METRIC_PROVIDER_ENABLED.labels(provider="atc_metar").set(1.0 if ENABLE_ATC_METAR else 0.0)
    METRIC_PROVIDER_ENABLED.labels(provider="atc_airsigmet").set(1.0 if ENABLE_ATC_AIRSIGMET else 0.0)
    for provider, st in (STATE.provider_status or {}).items():
        ts = st.get("last_ok_ts")
        if ts is None:
            continue
        try:
            METRIC_PROVIDER_LAST_OK_TS_MS.labels(provider=provider).set(float(ts))
        except Exception:
            continue

    data = generate_latest()
    # aiohttp forbids charset in the content_type argument; prometheus_client includes it.
    return web.Response(body=data, headers={"Content-Type": CONTENT_TYPE_LATEST})


async def post_perception(request: web.Request) -> web.Response:
    # Ordering invariants (do not reorder):
    # - Klein gate runs before: rev bump, accepted persistence, accepted WS broadcast.
    # - Reject path is: 422 + append-only artifact + audit event + optional minimal WS signal.
    raw = await request.read()
    if len(raw) > 1_500_000:
        ts = _now_ms()
        return _reject_perception(
            body={"world": str(request.query.get("world") or ""), "ops": [], "provenance": {}, "raw_bytes": len(raw)},
            world=_world_key(str(request.query.get("world") or "Astro")),
            ops=[],
            ts=ts,
            reason="invariant_reject",
            pack_id="rate_and_size",
            detail={"violations": [{"pack": "rate_and_size", "code": "rate_and_size.payload_bytes", "message": "payload too large", "path": None, "name": None, "bytes": len(raw)}]},
        )
    try:
        body = json.loads(raw.decode("utf-8"))
    except Exception:
        return web.json_response({"error": "invalid json"}, status=400)
    world = _world_key(str(body.get("world", "Astro")))
    ops = body.get("ops", [])
    if not isinstance(ops, list):
        return web.json_response({"error": "ops must be list"}, status=400)

    if len(ops) > 500:
        return _reject_perception(
            body=body,
            world=world,
            ops=ops,
            ts=_now_ms(),
            reason="invariant_reject",
            pack_id="rate_and_size",
            detail={"violations": [{"pack": "rate_and_size", "code": "rate_and_size.ops_count", "message": "too many ops", "path": None, "name": None, "ops_count": len(ops)}]},
        )

    unique_paths = {str(op.get("path") or "") for op in ops if isinstance(op, dict) and isinstance(op.get("path"), str)}
    if len(unique_paths) > 300:
        return _reject_perception(
            body=body,
            world=world,
            ops=ops,
            ts=_now_ms(),
            reason="invariant_reject",
            pack_id="rate_and_size",
            detail={"violations": [{"pack": "rate_and_size", "code": "rate_and_size.unique_paths", "message": "too many unique paths", "path": None, "name": None, "unique_paths": len(unique_paths)}]},
        )

    # Validate ops and enforce op_id presence for audit/idempotency correlation.
    for op in ops:
        if not isinstance(op, dict):
            return web.json_response({"error": "ops must contain objects"}, status=400)
        try:
            _validate_op(op)
        except Exception as e:
            return web.json_response({"error": f"invalid op: {e}"}, status=400)

    # Invariant packs (cheap, deterministic). Reject before Klein and before any state mutation.
    inv = _run_invariant_packs(world, ops)
    if inv:
        pack_id = str(inv[0].get("pack") or "invariant")
        return _reject_perception(body=body, world=world, ops=ops, ts=_now_ms(), reason="invariant_reject", pack_id=pack_id, detail={"violations": inv})

    # Klein closure gate: reject internally inconsistent perception inputs before we bump rev or persist as accepted.
    ok, tears = _klein_validate_ops(ops)
    if not ok:
        return _reject_perception(body=body, world=world, ops=ops, ts=_now_ms(), reason="klein_closure_reject", pack_id="klein", detail={"tears": tears})

    # Bump revision for this world (perception participates in the monotonic rev).
    ts = _now_ms()
    rev = STATE.rev.bump(world)
    fname = PERCEPTION_DIR / f"perception_{CELL_ID}_{world}_{rev}_{ts}.json"
    fname.write_text(json.dumps(body, indent=2), encoding="utf-8")
    _audit_write(
        {
            "ts": ts,
            "event": "perception_json",
            "cell_id": CELL_ID,
            "world": world,
            "rev": rev,
            "file": str(fname),
            "ops_count": len(ops),
            "provenance": body.get("provenance", {}),
        }
    )

    # Optionally broadcast perception ops to observers (marked not truth).
    try:
        await _broadcast(
            {
                "type": "perception_ops",
                "not_truth": True,
                "cell_id": CELL_ID,
                "world": world,
                "rev": rev,
                "ts": ts,
                "ops": ops,
                "provenance": body.get("provenance", {}),
            }
        )
    except Exception:
        pass

    # Minimal ingestion hook: record operator annotations into ArangoDB 'annotations' collection when present.
    try:
        for op in ops:
            if not isinstance(op, dict):
                continue
            # Operator-configured ATC region (used only to scope real provider queries)
            if op.get("op") == "SetAttr" and str(op.get("path", "")) == "/GaiaOS/UI/ATC/Region":
                name = str(op.get("name", ""))
                val = op.get("value")
                if STATE.atc_region is None:
                    STATE.atc_region = {"airport": None, "center_wgs84": None, "radius_km": ATC_RADIUS_KM_DEFAULT, "corridor": ATC_CORRIDOR_PRESET_DEFAULT}
                if name == "gaiaos:airport" and isinstance(val, str):
                    STATE.atc_region["airport"] = val.strip().upper()
                if name == "gaiaos:corridor" and isinstance(val, str):
                    STATE.atc_region["corridor"] = val.strip().upper()
                if name == "gaiaos:center_wgs84" and isinstance(val, list) and len(val) >= 2:
                    try:
                        lat = float(val[0])
                        lon = float(val[1])
                        STATE.atc_region["center_wgs84"] = [lat, lon]
                    except Exception:
                        pass
                if name == "gaiaos:radius_km":
                    try:
                        STATE.atc_region["radius_km"] = float(val)
                    except Exception:
                        pass
            if op.get("op") == "SetAttr" and op.get("name") == "gaiaos:annotation":
                await _store_annotation_arango(op.get("path", ""), str(op.get("value", "")), body.get("provenance", {}))
    except Exception as e:
        logger.error("perception ingestion error: %s", e)
    return web.json_response({"ok": True, "stored": str(fname)})


def _latlon_to_ui_xyz(lat: float, lon: float, alt_m: float = 0.0) -> Tuple[float, float, float]:
    """
    Deterministic coordinate mapping used for UI placement (no fabricated values).
    This matches the browser's simple equirectangular mapping scale so airport markers
    and provider-driven entities align in the same view.
    """
    scale = 8000.0
    x = (lon / 180.0) * scale
    z = (-lat / 90.0) * scale
    y = max(0.0, float(alt_m) / 50.0) + 15.0
    return float(x), float(y), float(z)


def _bbox_from_center(lat: float, lon: float, radius_km: float) -> Tuple[float, float, float, float]:
    # Rough bounding box in degrees around a center (sufficient for provider queries).
    r = max(10.0, float(radius_km))
    dlat = r / 111.32
    dlon = r / max(1.0, (111.32 * math.cos((lat * math.pi) / 180.0)))
    return lat - dlat, lon - dlon, lat + dlat, lon + dlon


# Northeast corridor (DC/PHL/NYC/BDL/BOS) tiling preset for rate-limited ADS-B sources.
# Coordinates are real WGS84 degree bounds used only to scope provider queries (no fabricated aircraft).
NE_FULL_TILES: List[Tuple[str, float, float, float, float]] = [
    # Small-ish tiles to stay under free rate/credit limits (rotate to build the air picture).
    ("DC", 38.50, -77.90, 39.20, -76.70),
    ("PHL", 39.60, -75.90, 40.25, -74.85),
    ("NYC", 40.35, -74.55, 41.10, -73.20),
    ("CT", 41.00, -73.65, 41.60, -72.50),
    ("BDL", 41.65, -73.25, 42.20, -72.20),
    ("PVD", 41.45, -72.00, 42.00, -71.00),
    ("BOS", 42.10, -71.65, 42.80, -70.60),
    ("OFFSHORE", 40.60, -72.00, 41.60, -70.50),
]


# Minimal WGS84 coordinates for airports we reference for corridor METAR overlays.
AIRPORT_WGS84: Dict[str, Tuple[float, float]] = {
    "KDCA": (38.8512, -77.0402),
    "KIAD": (38.9531, -77.4565),
    "KBWI": (39.1754, -76.6684),
    "KPHL": (39.8744, -75.2424),
    "KTEB": (40.8501, -74.0608),
    "KEWR": (40.6895, -74.1745),
    "KLGA": (40.7769, -73.8740),
    "KJFK": (40.6413, -73.7781),
    "KHPN": (41.0670, -73.7076),
    "KBDR": (41.1635, -73.1262),
    "KHVN": (41.2637, -72.8868),
    "KBDL": (41.9389, -72.6832),
    "KPVD": (41.7263, -71.4325),
    "KBOS": (42.3656, -71.0096),
}


async def _atc_adsb_loop() -> None:
    """
    Real aircraft state vectors → Cell world ops stream.
    Emits ops under /GaiaOS/Worlds/Cell/Perception/Aircraft/*.
    No USD writes required; WS deltas are sufficient for the UI projection.
    """
    if not ENABLE_ATC_ADSB:
        return
    # Bound poll to respect upstream rate limits. airplanes.live is 1 req/sec; OpenSky varies.
    poll = max(1.0, min(ATC_POLL_SEC, 2.0))
    tile_idx = 0
    source_runtime = ATC_ADSB_SOURCE
    async with aiohttp.ClientSession() as session:
        while True:
            sleep_sec = poll
            try:
                region = STATE.atc_region or {}
                center = region.get("center_wgs84")
                if not (isinstance(center, list) and len(center) == 2):
                    await asyncio.sleep(1.0)
                    continue
                lat0 = float(center[0])
                lon0 = float(center[1])
                radius_km = float(region.get("radius_km") or ATC_RADIUS_KM_DEFAULT)
                corridor = str(region.get("corridor") or ATC_CORRIDOR_PRESET_DEFAULT).strip().upper()
                if corridor == "NE_FULL" and NE_FULL_TILES:
                    label, lamin, lomin, lamax, lomax = NE_FULL_TILES[tile_idx % len(NE_FULL_TILES)]
                    tile_idx += 1
                    STATE.provider_status["atc_adsb"]["tile"] = label
                else:
                    lamin, lomin, lamax, lomax = _bbox_from_center(lat0, lon0, radius_km)
                    STATE.provider_status["atc_adsb"]["tile"] = "CENTER_BOX"

                ts = _now_ms()
                ops: List[dict] = []

                if source_runtime == "airplanes_live":
                    # airplanes.live supports a point+radius query (radius up to 250nm).
                    # We approximate the tile coverage by querying the tile center with radius to the farthest corner.
                    center_lat = (lamin + lamax) / 2.0
                    center_lon = (lomin + lomax) / 2.0
                    # Rough distance to corner in km.
                    dlat_km = abs(lamax - center_lat) * 111.32
                    dlon_km = abs(lomax - center_lon) * 111.32 * max(0.2, math.cos((center_lat * math.pi) / 180.0))
                    radius_km = math.sqrt(dlat_km * dlat_km + dlon_km * dlon_km)
                    radius_nm = min(250.0, max(10.0, radius_km / 1.852))
                    url = f"{AIRPLANES_LIVE_BASE_URL}/point/{center_lat:.4f}/{center_lon:.4f}/{radius_nm:.1f}"
                    async with session.get(url, timeout=aiohttp.ClientTimeout(total=15)) as resp:
                        if resp.status == 429:
                            raise aiohttp.ClientResponseError(
                                request_info=resp.request_info,
                                history=resp.history,
                                status=resp.status,
                                message="rate_limited",
                                headers=resp.headers,
                            )
                        resp.raise_for_status()
                        payload = await resp.json()

                    aircraft = payload.get("ac", []) if isinstance(payload, dict) else []
                    if not isinstance(aircraft, list):
                        aircraft = []
                    for a in aircraft:
                        if not isinstance(a, dict):
                            continue
                        icao24 = str(a.get("hex") or "").strip().lower()
                        if not icao24:
                            continue
                        callsign = str(a.get("flight") or "").strip()

                        latf = None
                        lonf = None
                        age_s = None
                        pos_quality = "unknown"

                        # Field semantics per airplanes.live data field descriptions:
                        # - lat/lon present when valid; seen_pos is seconds ago
                        # - lastPosition provided when lat/lon are older than 60s (invalid as current), includes its own seen_pos
                        # - rr_lat/rr_lon is a rough estimate (degraded)
                        if a.get("lat") is not None and a.get("lon") is not None:
                            try:
                                latf = float(a.get("lat"))
                                lonf = float(a.get("lon"))
                                age_s = float(a.get("seen_pos")) if a.get("seen_pos") is not None else None
                                pos_quality = "fresh"
                            except Exception:
                                latf = None
                                lonf = None
                        if (latf is None or lonf is None) and isinstance(a.get("lastPosition"), dict):
                            lp = a.get("lastPosition") or {}
                            try:
                                latf = float(lp.get("lat"))
                                lonf = float(lp.get("lon"))
                                age_s = float(lp.get("seen_pos")) if lp.get("seen_pos") is not None else None
                                pos_quality = "stale"
                            except Exception:
                                latf = None
                                lonf = None
                        if (latf is None or lonf is None) and a.get("rr_lat") is not None and a.get("rr_lon") is not None:
                            try:
                                latf = float(a.get("rr_lat"))
                                lonf = float(a.get("rr_lon"))
                                pos_quality = "estimated"
                                age_s = float(a.get("seen")) if a.get("seen") is not None else None
                            except Exception:
                                latf = None
                                lonf = None

                        if latf is None or lonf is None:
                            continue

                        alt_ft = a.get("alt_baro")
                        alt_m = 0.0
                        if isinstance(alt_ft, (int, float)):
                            alt_m = float(alt_ft) * 0.3048
                        else:
                            alt_m = 0.0
                        x, y, z = _latlon_to_ui_xyz(latf, lonf, alt_m)
                        path = f"/GaiaOS/Worlds/Cell/Perception/Aircraft/{icao24}"

                        ops.append({"op": "UpsertPrim", "op_id": _op_id(), "path": path, "primType": "Xform"})
                        ops.append({"op": "SetXform", "op_id": _op_id(), "path": path, "translate": [x, y, z], "orient": [0, 0, 0, 1], "scale": [1, 1, 1]})
                        if callsign:
                            ops.append({"op": "SetAttr", "op_id": _op_id(), "path": path, "name": "gaiaos:callsign", "valueType": "string", "value": callsign})
                        ops.append({"op": "SetAttr", "op_id": _op_id(), "path": path, "name": "gaiaos:source", "valueType": "string", "value": "airplanes_live"})
                        ops.append({"op": "SetAttr", "op_id": _op_id(), "path": path, "name": "gaiaos:pos_quality", "valueType": "string", "value": pos_quality})
                        if age_s is not None:
                            ops.append({"op": "SetAttr", "op_id": _op_id(), "path": path, "name": "gaiaos:pos_age_s", "valueType": "float", "value": float(age_s)})
                        ops.append({"op": "SetAttr", "op_id": _op_id(), "path": path, "name": "gaiaos:lat", "valueType": "float", "value": latf})
                        ops.append({"op": "SetAttr", "op_id": _op_id(), "path": path, "name": "gaiaos:lon", "valueType": "float", "value": lonf})
                        ops.append({"op": "SetAttr", "op_id": _op_id(), "path": path, "name": "gaiaos:alt_m", "valueType": "float", "value": alt_m})

                        gs_kn = a.get("gs")
                        if isinstance(gs_kn, (int, float)):
                            ops.append({"op": "SetAttr", "op_id": _op_id(), "path": path, "name": "gaiaos:ground_speed_mps", "valueType": "float", "value": float(gs_kn) * 0.514444})
                        trk = a.get("track")
                        if isinstance(trk, (int, float)):
                            ops.append({"op": "SetAttr", "op_id": _op_id(), "path": path, "name": "gaiaos:track_deg", "valueType": "float", "value": float(trk)})
                        seen_any = a.get("seen")
                        if isinstance(seen_any, (int, float)):
                            ops.append({"op": "SetAttr", "op_id": _op_id(), "path": path, "name": "gaiaos:seen_s", "valueType": "float", "value": float(seen_any)})
                        STATE.aircraft_last_seen_ms[path] = ts
                else:
                    url = f"https://opensky-network.org/api/states/all?lamin={lamin:.4f}&lomin={lomin:.4f}&lamax={lamax:.4f}&lomax={lomax:.4f}"
                    auth = None
                    if OPENSKY_USER and OPENSKY_PASS:
                        auth = aiohttp.BasicAuth(OPENSKY_USER, OPENSKY_PASS)
                    async with session.get(url, auth=auth, timeout=aiohttp.ClientTimeout(total=15)) as resp:
                        if resp.status == 429:
                            raise aiohttp.ClientResponseError(
                                request_info=resp.request_info,
                                history=resp.history,
                                status=resp.status,
                                message="rate_limited",
                                headers=resp.headers,
                            )
                        resp.raise_for_status()
                        payload = await resp.json()
                    states = payload.get("states", []) if isinstance(payload, dict) else []

                    for row in states:
                        # OpenSky state vector array format
                        if not isinstance(row, list) or len(row) < 8:
                            continue
                        icao24 = str(row[0] or "").strip().lower()
                        callsign = str(row[1] or "").strip()
                        lon = row[5]
                        lat = row[6]
                        baro_alt = row[7]
                        vel = row[9] if len(row) > 9 else None
                        track = row[10] if len(row) > 10 else None
                        on_ground = row[8] if len(row) > 8 else None
                        if not icao24 or lat is None or lon is None:
                            continue
                        try:
                            latf = float(lat)
                            lonf = float(lon)
                        except Exception:
                            continue
                        alt_m = 0.0
                        try:
                            if baro_alt is not None:
                                alt_m = float(baro_alt)
                        except Exception:
                            alt_m = 0.0

                        path = f"/GaiaOS/Worlds/Cell/Perception/Aircraft/{icao24}"
                        x, y, z = _latlon_to_ui_xyz(latf, lonf, alt_m)

                        ops.append({"op": "UpsertPrim", "op_id": _op_id(), "path": path, "primType": "Xform"})
                        ops.append({"op": "SetXform", "op_id": _op_id(), "path": path, "translate": [x, y, z], "orient": [0, 0, 0, 1], "scale": [1, 1, 1]})
                        if callsign:
                            ops.append({"op": "SetAttr", "op_id": _op_id(), "path": path, "name": "gaiaos:callsign", "valueType": "string", "value": callsign})
                        ops.append({"op": "SetAttr", "op_id": _op_id(), "path": path, "name": "gaiaos:source", "valueType": "string", "value": "opensky"})
                        ops.append({"op": "SetAttr", "op_id": _op_id(), "path": path, "name": "gaiaos:lat", "valueType": "float", "value": latf})
                        ops.append({"op": "SetAttr", "op_id": _op_id(), "path": path, "name": "gaiaos:lon", "valueType": "float", "value": lonf})
                        ops.append({"op": "SetAttr", "op_id": _op_id(), "path": path, "name": "gaiaos:alt_m", "valueType": "float", "value": alt_m})
                        if vel is not None:
                            try:
                                ops.append({"op": "SetAttr", "op_id": _op_id(), "path": path, "name": "gaiaos:ground_speed_mps", "valueType": "float", "value": float(vel)})
                            except Exception:
                                pass
                        if track is not None:
                            try:
                                ops.append({"op": "SetAttr", "op_id": _op_id(), "path": path, "name": "gaiaos:track_deg", "valueType": "float", "value": float(track)})
                            except Exception:
                                pass
                        if on_ground is not None:
                            ops.append({"op": "SetAttr", "op_id": _op_id(), "path": path, "name": "gaiaos:on_ground", "valueType": "bool", "value": bool(on_ground)})

                        STATE.aircraft_last_seen_ms[path] = ts

                # Remove stale aircraft not seen recently.
                stale_cutoff = ts - 60_000
                for pth, last_seen in list(STATE.aircraft_last_seen_ms.items()):
                    if last_seen < stale_cutoff:
                        ops.append({"op": "RemovePrim", "op_id": _op_id(), "path": pth})
                        STATE.aircraft_last_seen_ms.pop(pth, None)

                if ops:
                    rev = STATE.rev.bump("Cell")
                    env_base = {"type": "usd_deltas", "cell_id": CELL_ID, "world": "Cell", "rev": rev, "ts": ts}
                    _audit_write({"ts": ts, "event": "atc_adsb_commit", "cell_id": CELL_ID, "world": "Cell", "rev": rev, "ops_count": len(ops)})
                    await _broadcast_ops(env_base, ops)
                STATE.provider_status["atc_adsb"]["last_ok_ts"] = _now_ms()
                STATE.provider_status["atc_adsb"]["last_error"] = None
                STATE.provider_status["atc_adsb"]["source"] = source_runtime
            except aiohttp.ClientResponseError as e:
                # Specific backoff on 429s.
                if getattr(e, "status", None) == 429:
                    sleep_sec = max(sleep_sec, 15.0)
                STATE.provider_status["atc_adsb"]["last_error"] = f"{getattr(e, 'status', None)}, message='{getattr(e, 'message', '')}'"
                logger.error("ATC ADS-B loop error: %s", e)
                if ATC_ADSB_FALLBACK_ON_429 and source_runtime == "opensky" and getattr(e, "status", None) == 429:
                    logger.warning("ATC ADS-B: OpenSky 429. Switching to airplanes_live fallback.")
                    source_runtime = "airplanes_live"
                    STATE.provider_status["atc_adsb"]["source"] = source_runtime
            except Exception as e:
                STATE.provider_status["atc_adsb"]["last_error"] = str(e)
                logger.error("ATC ADS-B loop error: %s", e)
            await asyncio.sleep(sleep_sec)


async def _atc_metar_loop() -> None:
    """
    Real METAR for selected airport → Cell world station + weather overlay ops.
    Emits ops under /GaiaOS/Worlds/Cell/Perception/Stations/* and /.../Weather/*.
    """
    if not ENABLE_ATC_METAR:
        return
    poll = max(1.0, float(ATC_POLL_SEC))
    async with aiohttp.ClientSession() as session:
        while True:
            try:
                region = STATE.atc_region or {}
                airport = str(region.get("airport") or "").strip().upper()
                center = region.get("center_wgs84")
                if not airport or not (isinstance(center, list) and len(center) == 2):
                    await asyncio.sleep(1.0)
                    continue
                corridor = str(region.get("corridor") or ATC_CORRIDOR_PRESET_DEFAULT).strip().upper()
                # Corridor mode polls a small fixed airport set (staggered) rather than just one station.
                if corridor == "NE_FULL":
                    airports = ["KDCA", "KIAD", "KBWI", "KPHL", "KTEB", "KEWR", "KLGA", "KJFK", "KHPN", "KBDR", "KHVN", "KBDL", "KPVD", "KBOS"]
                else:
                    airports = [airport]

                ts = _now_ms()
                # Choose the next due airport (<= 1 fetch/sec; ~60s per airport).
                chosen = None
                for a in airports:
                    last_ok = int(STATE.metar_last_ok_ms.get(a, 0))
                    if ts - last_ok >= 60_000:
                        chosen = a
                        break
                if not chosen:
                    await asyncio.sleep(1.0)
                    continue

                lat0, lon0 = AIRPORT_WGS84.get(chosen, (float(center[0]), float(center[1])))

                url = f"https://aviationweather.gov/api/data/metar?ids={chosen}&format=json"
                metar_payload = await _fetch_json(session, url)
                asset_uri = _write_artifact("aviationweather_metar", f"metar_{chosen}", metar_payload)

                # Best-effort parse. Payload is list of dicts.
                row = metar_payload[0] if isinstance(metar_payload, list) and metar_payload else {}
                if not isinstance(row, dict):
                    row = {}
                raw = str(row.get("rawOb") or row.get("raw_ob") or row.get("raw") or "")
                wind_speed = row.get("wspd") or row.get("windSpeed") or row.get("wind_speed")
                wind_dir = row.get("wdir") or row.get("windDir") or row.get("wind_dir") or row.get("windDirection")
                vis = row.get("visib") or row.get("visibility") or row.get("vis")

                sx, sy, sz = _latlon_to_ui_xyz(lat0, lon0, 0.0)

                ops: List[dict] = []
                station_path = f"/GaiaOS/Worlds/Cell/Perception/Stations/{chosen}"
                ops.append({"op": "UpsertPrim", "op_id": _op_id(), "path": station_path, "primType": "Xform"})
                ops.append({"op": "SetXform", "op_id": _op_id(), "path": station_path, "translate": [sx, 15.0, sz], "orient": [0, 0, 0, 1], "scale": [1, 1, 1]})
                ops.append({"op": "SetAttr", "op_id": _op_id(), "path": station_path, "name": "gaiaos:station", "valueType": "string", "value": chosen})
                ops.append({"op": "SetAttr", "op_id": _op_id(), "path": station_path, "name": "gaiaos:lat", "valueType": "float", "value": lat0})
                ops.append({"op": "SetAttr", "op_id": _op_id(), "path": station_path, "name": "gaiaos:lon", "valueType": "float", "value": lon0})
                if raw:
                    ops.append({"op": "SetAttr", "op_id": _op_id(), "path": station_path, "name": "gaiaos:raw", "valueType": "string", "value": raw})
                ops.append({"op": "SetAttr", "op_id": _op_id(), "path": station_path, "name": "gaiaos:asset", "valueType": "string", "value": asset_uri})
                if wind_speed is not None:
                    try:
                        ops.append({"op": "SetAttr", "op_id": _op_id(), "path": station_path, "name": "gaiaos:wind_speed", "valueType": "float", "value": float(wind_speed)})
                    except Exception:
                        pass
                if wind_dir is not None:
                    try:
                        ops.append({"op": "SetAttr", "op_id": _op_id(), "path": station_path, "name": "gaiaos:wind_dir_deg", "valueType": "float", "value": float(wind_dir)})
                    except Exception:
                        pass
                if vis is not None:
                    try:
                        ops.append({"op": "SetAttr", "op_id": _op_id(), "path": station_path, "name": "gaiaos:visibility", "valueType": "float", "value": float(vis)})
                    except Exception:
                        pass

                # Weather blob (size derived from available values; if missing, still emit a small marker).
                blob_path = f"/GaiaOS/Worlds/Cell/Perception/Weather/METAR_{chosen}"
                ops.append({"op": "UpsertPrim", "op_id": _op_id(), "path": blob_path, "primType": "Xform"})
                radius = 1.0
                try:
                    if vis is not None:
                        v = float(vis)
                        # Lower visibility -> larger blob (bounded).
                        radius = max(1.0, min(8.0, 8.0 - min(8.0, v)))
                except Exception:
                    radius = 1.0
                ops.append({"op": "SetXform", "op_id": _op_id(), "path": blob_path, "translate": [sx, 15.0, sz], "orient": [0, 0, 0, 1], "scale": [radius, 1.0, radius]})
                ops.append({"op": "SetAttr", "op_id": _op_id(), "path": blob_path, "name": "gaiaos:asset", "valueType": "string", "value": asset_uri})
                if vis is not None:
                    try:
                        ops.append({"op": "SetAttr", "op_id": _op_id(), "path": blob_path, "name": "gaiaos:visibility", "valueType": "float", "value": float(vis)})
                    except Exception:
                        pass

                if ops:
                    rev = STATE.rev.bump("Cell")
                    env_base = {"type": "usd_deltas", "cell_id": CELL_ID, "world": "Cell", "rev": rev, "ts": ts}
                    _audit_write({"ts": ts, "event": "atc_metar_commit", "cell_id": CELL_ID, "world": "Cell", "rev": rev, "ops_count": len(ops)})
                    await _broadcast_ops(env_base, ops)
                STATE.provider_status["atc_metar"]["last_ok_ts"] = _now_ms()
                STATE.provider_status["atc_metar"]["last_error"] = None
                STATE.metar_last_ok_ms[chosen] = ts
            except Exception as e:
                STATE.provider_status["atc_metar"]["last_error"] = str(e)
                logger.error("ATC METAR loop error: %s", e)
            await asyncio.sleep(poll)


async def _atc_airsigmet_loop() -> None:
    """
    Real AviationWeather airsigmet feed (e.g., turbulence/convective hazards) → Cell weather ops.
    Emits ops under /GaiaOS/Worlds/Cell/Perception/Weather/AIRSIGMET/*.
    No synthetic fields: any geometry used for visualization is derived from the provider's reported area.
    """
    if not ENABLE_ATC_AIRSIGMET:
        return
    poll = max(60.0, float(os.getenv("ATC_AIRSIGMET_POLL_SEC", "180")))
    async with aiohttp.ClientSession() as session:
        while True:
            try:
                # Best-effort: API shape may change; we persist the raw payload for audit.
                urls = [
                    "https://aviationweather.gov/api/data/airsigmet?format=json",
                    "https://aviationweather.gov/api/data/airsigmet",
                ]
                payload = None
                last_err = None
                for url in urls:
                    try:
                        payload = await _fetch_json(session, url)
                        break
                    except Exception as e:
                        last_err = str(e)
                        continue
                if payload is None:
                    raise RuntimeError(last_err or "airsigmet fetch failed")

                asset_uri = _write_artifact("aviationweather_airsigmet", "airsigmet", payload)
                ts = _now_ms()
                ops: List[dict] = []

                items = payload if isinstance(payload, list) else payload.get("data", []) if isinstance(payload, dict) else []
                if not isinstance(items, list):
                    items = []
                for item in items[:200]:
                    if not isinstance(item, dict):
                        continue
                    sid = str(item.get("airsigmetId") or item.get("id") or item.get("sigmetId") or item.get("sigmet_id") or "").strip()
                    if not sid:
                        # Fallback: stable-ish key from text.
                        sid = str(item.get("rawText") or item.get("raw_text") or "")[:24].strip().replace(" ", "_")
                    if not sid:
                        continue
                    sid = sid.replace("/", "_")
                    path = f"/GaiaOS/Worlds/Cell/Perception/Weather/AIRSIGMET/{sid}"
                    ops.append({"op": "UpsertPrim", "op_id": _op_id(), "path": path, "primType": "Xform"})

                    # Derived center for visualization if coordinates are present.
                    coords = item.get("coordinates") or item.get("coords") or item.get("geometry") or item.get("geom")
                    center_lat = None
                    center_lon = None
                    poly_wgs84: List[List[float]] = []
                    if isinstance(coords, list) and coords:
                        lats = []
                        lons = []
                        for c in coords:
                            if isinstance(c, dict):
                                lat = c.get("lat")
                                lon = c.get("lon")
                            elif isinstance(c, (list, tuple)) and len(c) >= 2:
                                lon = c[0]
                                lat = c[1]
                            else:
                                continue
                            try:
                                latf = float(lat)
                                lonf = float(lon)
                                lats.append(latf)
                                lons.append(lonf)
                                poly_wgs84.append([latf, lonf])
                            except Exception:
                                continue
                        if lats and lons:
                            center_lat = sum(lats) / len(lats)
                            center_lon = sum(lons) / len(lons)
                    if center_lat is not None and center_lon is not None:
                        x, y, z = _latlon_to_ui_xyz(center_lat, center_lon, 0.0)
                        ops.append({"op": "SetXform", "op_id": _op_id(), "path": path, "translate": [x, 25.0, z], "orient": [0, 0, 0, 1], "scale": [5.0, 1.0, 5.0]})
                        ops.append({"op": "SetAttr", "op_id": _op_id(), "path": path, "name": "gaiaos:center_wgs84", "valueType": "float3", "value": [float(center_lat), float(center_lon), 0.0]})

                    for k, n in (
                        ("hazard", "gaiaos:hazard"),
                        ("severity", "gaiaos:severity"),
                        ("altitude", "gaiaos:altitude"),
                        ("rawText", "gaiaos:raw"),
                        ("raw_text", "gaiaos:raw"),
                    ):
                        if item.get(k) is None:
                            continue
                        ops.append({"op": "SetAttr", "op_id": _op_id(), "path": path, "name": n, "valueType": "string", "value": str(item.get(k))})

                    # If we have polygon coordinates, publish them for the UI to render truthful hazard curtains.
                    if poly_wgs84:
                        ops.append(
                            {
                                "op": "SetAttr",
                                "op_id": _op_id(),
                                "path": path,
                                "name": "gaiaos:poly_wgs84",
                                "valueType": "string",
                                "value": json.dumps(poly_wgs84, separators=(",", ":")),
                            }
                        )

                    ops.append({"op": "SetAttr", "op_id": _op_id(), "path": path, "name": "gaiaos:asset", "valueType": "string", "value": asset_uri})

                if ops:
                    rev = STATE.rev.bump("Cell")
                    env_base = {"type": "usd_deltas", "cell_id": CELL_ID, "world": "Cell", "rev": rev, "ts": ts}
                    _audit_write({"ts": ts, "event": "atc_airsigmet_commit", "cell_id": CELL_ID, "world": "Cell", "rev": rev, "ops_count": len(ops)})
                    await _broadcast_ops(env_base, ops)
                STATE.provider_status["atc_airsigmet"]["last_ok_ts"] = _now_ms()
                STATE.provider_status["atc_airsigmet"]["last_error"] = None
            except Exception as e:
                STATE.provider_status["atc_airsigmet"]["last_error"] = str(e)
                logger.error("ATC AIRSIGMET loop error: %s", e)
            await asyncio.sleep(poll)


async def post_perception_layer(request: web.Request) -> web.Response:
    world = _world_key(request.headers.get("X-World", "Astro"))
    ts = _now_ms()
    rev = STATE.rev.bump(world)
    raw = await request.read()
    fname = PERCEPTION_DIR / f"perception_{CELL_ID}_{world}_{rev}_{ts}.usda"
    fname.write_bytes(raw)
    _audit_write({"ts": ts, "event": "perception_usd", "cell_id": CELL_ID, "world": world, "rev": rev, "file": str(fname), "bytes": len(raw)})
    return web.json_response({"ok": True, "stored": str(fname)})


async def _store_annotation_arango(target: str, annotation: str, provenance: dict) -> None:
    if not target or not annotation:
        return
    doc = {
        "target": target,
        "annotation": annotation,
        "provenance": provenance,
        "timestamp_ms": _now_ms(),
    }
    async with aiohttp.ClientSession() as session:
        async with session.post(
            f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/document/annotations",
            json=doc,
            auth=aiohttp.BasicAuth(ARANGO_USER, ARANGO_PASSWORD),
            timeout=aiohttp.ClientTimeout(total=10),
        ) as resp:
            if resp.status not in (201, 202):
                logger.warning("annotation store failed: %s", resp.status)


async def file_getter(request: web.Request) -> web.StreamResponse:
    rel = request.match_info.get("path", "")
    p = (USD_DIR / rel).resolve()
    if not str(p).startswith(str(USD_DIR)):
        return web.Response(status=403)
    if not p.exists() or not p.is_file():
        return web.Response(status=404)
    data = p.read_bytes()
    ctype = "application/octet-stream"
    if p.suffix == ".usda":
        ctype = "text/plain"
    return web.Response(body=data, content_type=ctype, headers={"Cache-Control": "no-store"})


async def _fetch_json(session: aiohttp.ClientSession, url: str, headers: Optional[dict] = None) -> Any:
    async with session.get(url, headers=headers or {}, timeout=aiohttp.ClientTimeout(total=15)) as resp:
        resp.raise_for_status()
        return await resp.json()


def _write_artifact(provider: str, name: str, payload: Any) -> str:
    """
    Persist raw provider payload for audit/replay. Returns a USD-served URI (/usd/...) that can be referenced from attributes.
    """
    ts = _now_ms()
    safe_provider = provider.replace("/", "_")
    pdir = ARTIFACTS_DIR / safe_provider
    pdir.mkdir(parents=True, exist_ok=True)
    fpath = pdir / f"{name}_{ts}.json"
    fpath.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    _audit_write({"ts": ts, "event": "artifact_write", "provider": provider, "file": str(fpath)})
    rel = fpath.relative_to(USD_DIR)
    return f"/usd/{rel.as_posix()}"


def _extract_lat_lon(row: dict) -> Optional[Tuple[float, float]]:
    # AviationWeather payload shape varies; accept common keys.
    candidates = [
        ("lat", "lon"),
        ("latitude", "longitude"),
        ("lat_deg", "lon_deg"),
        ("latitude_deg", "longitude_deg"),
    ]
    for lat_k, lon_k in candidates:
        if lat_k in row and lon_k in row and row.get(lat_k) is not None and row.get(lon_k) is not None:
            try:
                return float(row[lat_k]), float(row[lon_k])
            except Exception:
                continue
    return None


async def _weather_provider_loop() -> None:
    """
    Provider loop: NOAA/NWS alerts + AviationWeather METAR.
    Emits USD-representable ops under /GaiaOS/Worlds/Human/Fields/* and bumps Human rev.
    """
    if not (ENABLE_NOAA_NWS or ENABLE_AVIATION_WEATHER):
        return

    while True:
        try:
            ops: List[dict] = []
            async with aiohttp.ClientSession() as session:
                if ENABLE_AVIATION_WEATHER and METAR_STATIONS:
                    try:
                        ids = ",".join(METAR_STATIONS)
                        url = f"https://aviationweather.gov/cgi-bin/data/metar.php?ids={ids}&format=json"
                        metar_payload = await _fetch_json(session, url)
                        asset_uri = _write_artifact("aviation_weather", "metar", metar_payload)
                        if isinstance(metar_payload, list):
                            for row in metar_payload:
                                if not isinstance(row, dict):
                                    continue
                                station = str(row.get("station", "")).upper() or str(row.get("icaoId", "")).upper()
                                if not station:
                                    continue
                                prim_path = f"/GaiaOS/Worlds/Human/Fields/METAR/{station}"
                                ops.append({"op": "UpsertPrim", "op_id": _op_id(), "path": prim_path, "primType": "Xform"})

                                raw = row.get("rawOb") or row.get("raw") or ""
                                ops.append(
                                    {
                                        "op": "SetAttr",
                                        "op_id": _op_id(),
                                        "path": prim_path,
                                        "name": "gaiaos:raw",
                                        "valueType": "string",
                                        "value": str(raw),
                                    }
                                )
                                ops.append(
                                    {
                                        "op": "SetAttr",
                                        "op_id": _op_id(),
                                        "path": prim_path,
                                        "name": "gaiaos:station",
                                        "valueType": "string",
                                        "value": station,
                                    }
                                )
                                ops.append(
                                    {
                                        "op": "SetAttr",
                                        "op_id": _op_id(),
                                        "path": prim_path,
                                        "name": "gaiaos:asset",
                                        "valueType": "string",
                                        "value": asset_uri,
                                    }
                                )

                                ll = _extract_lat_lon(row)
                                if ll is not None:
                                    lat, lon = ll
                                    ops.append(
                                        {
                                            "op": "SetAttr",
                                            "op_id": _op_id(),
                                            "path": prim_path,
                                            "name": "gaiaos:lat",
                                            "valueType": "float",
                                            "value": lat,
                                        }
                                    )
                                    ops.append(
                                        {
                                            "op": "SetAttr",
                                            "op_id": _op_id(),
                                            "path": prim_path,
                                            "name": "gaiaos:lon",
                                            "valueType": "float",
                                            "value": lon,
                                        }
                                    )

                        STATE.provider_status["aviation_weather"]["last_ok_ts"] = _now_ms()
                        STATE.provider_status["aviation_weather"]["last_error"] = None
                    except Exception as e:
                        STATE.provider_status["aviation_weather"]["last_error"] = str(e)
                        logger.error("AviationWeather METAR fetch failed: %s", e)

                if ENABLE_NOAA_NWS and NWS_POINT_LAT and NWS_POINT_LON:
                    try:
                        url = f"https://api.weather.gov/alerts/active?point={NWS_POINT_LAT},{NWS_POINT_LON}"
                        nws_payload = await _fetch_json(session, url, headers={"User-Agent": NWS_USER_AGENT})
                        asset_uri = _write_artifact("noaa_nws", "alerts", nws_payload)
                        features = nws_payload.get("features", []) if isinstance(nws_payload, dict) else []
                        for feat in features:
                            props = feat.get("properties", {}) if isinstance(feat, dict) else {}
                            aid = props.get("id") or props.get("event") or props.get("headline") or _op_id()
                            alert_id = str(aid).replace("/", "_")[:128]
                            prim_path = f"/GaiaOS/Worlds/Human/Fields/Alerts/{alert_id}"
                            ops.append({"op": "UpsertPrim", "op_id": _op_id(), "path": prim_path, "primType": "Xform"})
                            for k, n in (
                                ("event", "gaiaos:alert_type"),
                                ("severity", "gaiaos:severity"),
                                ("certainty", "gaiaos:certainty"),
                                ("headline", "gaiaos:headline"),
                            ):
                                if props.get(k) is None:
                                    continue
                                ops.append(
                                    {
                                        "op": "SetAttr",
                                        "op_id": _op_id(),
                                        "path": prim_path,
                                        "name": n,
                                        "valueType": "string",
                                        "value": str(props.get(k)),
                                    }
                                )
                            # Full payload is persisted; reference it for audit.
                            ops.append(
                                {
                                    "op": "SetAttr",
                                    "op_id": _op_id(),
                                    "path": prim_path,
                                    "name": "gaiaos:asset",
                                    "valueType": "string",
                                    "value": asset_uri,
                                }
                            )

                        STATE.provider_status["noaa_nws"]["last_ok_ts"] = _now_ms()
                        STATE.provider_status["noaa_nws"]["last_error"] = None
                    except Exception as e:
                        STATE.provider_status["noaa_nws"]["last_error"] = str(e)
                        logger.error("NWS alerts fetch failed: %s", e)

            if ops:
                if PXR_OK:
                    stage = _open_stage()
                    _ensure_stage_geospatial_and_materials(stage)
                    _apply_ops_to_usd(stage, ops)

                    # If we have lat/lon, create proper UsdGeom station prims (Apple+UsdGeom patterns).
                    # This does not fabricate data: it uses provider payload fields already emitted as attrs.
                    try:
                        # Collect latest station records from this ops set.
                        by_station: Dict[str, Dict[str, Any]] = {}
                        for op in ops:
                            if op.get("op") != "SetAttr":
                                continue
                            path = str(op.get("path", ""))
                            if "/Fields/METAR/" not in path:
                                continue
                            station = path.rsplit("/", 1)[-1]
                            by_station.setdefault(station, {})[str(op.get("name"))] = op.get("value")
                        for station, fields in by_station.items():
                            if not isinstance(fields.get("gaiaos:lat"), (int, float)) or not isinstance(fields.get("gaiaos:lon"), (int, float)):
                                continue
                            _upsert_weather_station_usd(
                                stage=stage,
                                station_id=station,
                                lat=float(fields["gaiaos:lat"]),
                                lon=float(fields["gaiaos:lon"]),
                                alt_m=0.0,
                                asset_uri=str(fields.get("gaiaos:asset") or ""),
                                raw_metar=str(fields.get("gaiaos:raw") or ""),
                            )
                    except Exception as e:
                        logger.warning("weather station USD prim upsert failed: %s", e)

                    stage.GetEditTarget().GetLayer().Save()
                new_rev = STATE.rev.bump("Human")
                envelope_base = {"type": "usd_deltas", "cell_id": CELL_ID, "world": "Human", "rev": new_rev, "ts": _now_ms()}
                _audit_write({"ts": envelope_base["ts"], "event": "provider_commit", "cell_id": CELL_ID, "world": "Human", "rev": new_rev, "ops_count": len(ops)})
                await _broadcast_ops(envelope_base, ops)
        except Exception as e:
            logger.error("weather provider loop error: %s", e)

        await asyncio.sleep(max(5, WEATHER_POLL_SEC))


async def truth_poll_loop() -> None:
    interval = 1.0 / max(POLL_HZ, 1.0)
    query = """
    FOR frame IN substrate_frames
        SORT frame.timestamp_ms DESC
        LIMIT 1

        LET entities = (
            FOR e IN substrate_entities
                FILTER e.frame_id == frame.frame_id
                RETURN e
        )

        RETURN MERGE(frame, {entities: entities})
    """

    while True:
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/cursor",
                    json={"query": query},
                    auth=aiohttp.BasicAuth(ARANGO_USER, ARANGO_PASSWORD),
                    timeout=aiohttp.ClientTimeout(total=10),
                ) as resp:
                    if resp.status != 201:
                        await asyncio.sleep(1.0)
                        continue
                    payload = await resp.json()
                    results = payload.get("result", [])
                    if not results:
                        await asyncio.sleep(interval)
                        continue

                    frame = results[0]
                    world = _world_key(str(frame.get("world_scope", "Astro")))
                    frame_id = frame.get("frame_id") or frame.get("_key") or frame.get("timestamp_ms")
                    if STATE.last_frame_id.get(world) == frame_id:
                        await asyncio.sleep(interval)
                        continue

                    STATE.last_frame_id[world] = frame_id

                    ops: List[dict] = []
                    for ent in frame.get("entities", []):
                        ent_path = f"/GaiaOS/Worlds/{world}/{ent.get('type','Entity')}_{ent.get('substrate_id','0')}"
                        ops.append({"op": "UpsertPrim", "op_id": _op_id(), "path": ent_path, "primType": "Xform"})
                        ops.append(
                            {
                                "op": "SetXform",
                                "op_id": _op_id(),
                                "path": ent_path,
                                "translate": ent.get("position", [0, 0, 0]),
                                "orient": ent.get("rotation", [0, 0, 0, 1]),
                                "scale": ent.get("scale", [1, 1, 1]),
                            }
                        )
                        voxel = ent.get("voxel", {}) or {}
                        for dim in ("space", "time", "energy", "consciousness"):
                            if dim in voxel:
                                ops.append(
                                    {
                                        "op": "SetAttr",
                                        "op_id": _op_id(),
                                        "path": ent_path,
                                        "name": f"gaiaos:{dim}",
                                        "valueType": "float",
                                        "value": voxel.get(dim),
                                    }
                                )

                    # Apply to USD only when pxr is available. When pxr is missing we still
                    # broadcast the ops stream (truth conversation) without claiming file writes.
                    if PXR_OK:
                        stage = _open_stage()
                        _ensure_stage_geospatial_and_materials(stage)
                        _apply_ops_to_usd(stage, ops)
                        stage.GetEditTarget().GetLayer().Save()

                    new_rev = STATE.rev.bump(world)
                    envelope_base = {"type": "usd_deltas", "cell_id": CELL_ID, "world": world, "rev": new_rev, "ts": _now_ms()}
                    _audit_write({"ts": envelope_base["ts"], "event": "truth_commit", "cell_id": CELL_ID, "world": world, "rev": new_rev, "ops_count": len(ops)})
                    await _broadcast_ops(envelope_base, ops)
        except Exception as e:
            logger.error("truth poll error: %s", e)
            await asyncio.sleep(1.0)

        await asyncio.sleep(interval)


async def tick_loop() -> None:
    """
    Truthful liveness heartbeat: emits a lightweight tick envelope so clients can
    show a moving conversation clock even when no new truth/perception ops arrive.
    Does NOT bump revision and does not claim any state change.
    """
    interval = max(100, TICK_MS) / 1000.0
    worlds = ["Cell", "Human", "Astro"]
    idx = 0
    while True:
        try:
            if STATE.clients:
                w = worlds[idx % len(worlds)]
                idx += 1
                await _broadcast(
                    {
                        "type": "tick",
                        "not_truth": False,
                        "source": "transportcell",
                        "cell_id": CELL_ID,
                        "world": w,
                        "rev": int(STATE.rev.current_rev.get(w, 0)),
                        "ts": _now_ms(),
                    }
                )
        except Exception:
            pass
        await asyncio.sleep(interval)


@web.middleware
async def cors_middleware(request: web.Request, handler):
    if request.method == "OPTIONS":
        return web.Response(
            status=204,
            headers={
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type,X-World",
                "Access-Control-Max-Age": "86400",
            },
        )
    resp = await handler(request)
    resp.headers["Access-Control-Allow-Origin"] = "*"
    resp.headers["Access-Control-Allow-Methods"] = "GET,POST,OPTIONS"
    resp.headers["Access-Control-Allow-Headers"] = "Content-Type,X-World"
    return resp


def create_app() -> web.Application:
    _ensure_dirs()
    app = web.Application(middlewares=[cors_middleware])
    app.router.add_route("OPTIONS", "/{tail:.*}", lambda r: web.Response(status=204))
    app.router.add_get("/health", health)
    app.router.add_get("/capabilities", capabilities)
    app.router.add_get("/metrics", metrics)
    app.router.add_get("/ws/usd-deltas", ws_handler)
    app.router.add_post("/perception", post_perception)
    app.router.add_post("/bio/perception", post_bio_perception)
    app.router.add_post("/usd/perception-layer", post_perception_layer)
    app.router.add_get("/usd/{path:.*}", file_getter)

    # Ensure reject counter appears at zero for scrape visibility.
    try:
        reasons = ("klein_closure_reject", "invariant_reject")
        for w in ("Cell", "Human", "Astro"):
            for r in reasons:
                METRIC_PERCEPTION_REJECTS.labels(world=w, reason=r).inc(0)
        for w in ("Cell", "Human", "Astro"):
            for p in ("klein", "rate_and_size", "world_scope", "geo_physics", "entity_identity", "atc_region"):
                METRIC_PERCEPTION_REJECTS_BY_PACK.labels(world=w, reason="invariant_reject", pack_id=p).inc(0)
            METRIC_PERCEPTION_REJECTS_BY_PACK.labels(world=w, reason="klein_closure_reject", pack_id="klein").inc(0)
    except Exception:
        pass
    return app


async def _startup_tasks(app: web.Application) -> None:
    app["truth_task"] = asyncio.create_task(truth_poll_loop())
    app["weather_task"] = asyncio.create_task(_weather_provider_loop())
    app["tick_task"] = asyncio.create_task(tick_loop())
    app["atc_adsb_task"] = asyncio.create_task(_atc_adsb_loop())
    app["atc_metar_task"] = asyncio.create_task(_atc_metar_loop())
    app["atc_airsigmet_task"] = asyncio.create_task(_atc_airsigmet_loop())


async def _cleanup_tasks(app: web.Application) -> None:
    for k in ("truth_task", "weather_task", "tick_task", "atc_adsb_task", "atc_metar_task", "atc_airsigmet_task"):
        t = app.get(k)
        if t:
            t.cancel()
            try:
                await t
            except asyncio.CancelledError:
                pass


def main() -> None:
    app = create_app()
    app.on_startup.append(_startup_tasks)
    app.on_cleanup.append(_cleanup_tasks)
    web.run_app(app, host="0.0.0.0", port=PORT)


if __name__ == "__main__":
    main()


