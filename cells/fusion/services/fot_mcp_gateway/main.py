#!/usr/bin/env python3
"""
GaiaFTCL MCP Gateway - OPEN AND DYNAMIC
NO TEMPLATES. NO HARDCODED RESPONSES.
SHE SHAPES OUTPUT BASED ON SUBSTRATE CONTENT + QUERY CONTEXT.
"""

import os
import asyncio
import math
import secrets
import re
from datetime import datetime, timezone
from typing import Dict, Any, Optional, List, Tuple
from fastapi import FastAPI, HTTPException, Header, Query

from universal_ingest import universal_ingest
import httpx
import json
import nats
from nats.aio.client import Client as NATS

try:
    from vie_v2.transformer import InvariantTransformer
    from vie_v2.projection import vie_to_legacy_measurement
except ImportError:
    InvariantTransformer = None  # type: ignore[misc, assignment]
    vie_to_legacy_measurement = None  # type: ignore[misc, assignment]

try:
    from wallet_auth import (
        verify_signature,
        validate_authentication_payload,
        is_valid_wallet_address,
    )
except ImportError:
    verify_signature = None
    validate_authentication_payload = None
    is_valid_wallet_address = None  # type: ignore

app = FastAPI(title="GaiaFTCL MCP Gateway - Dynamic")

# Docker container names. Production mesh: gaiaftcl-arangodb, gaiaftcl-nats.
ARANGO_URL = os.getenv("ARANGO_URL", "http://gaiaftcl-arangodb:8529")
ARANGO_DB = os.getenv("ARANGO_DB", "gaiaos")
ARANGO_USER = os.getenv("ARANGO_USER", "root")
ARANGO_PASSWORD = os.getenv("ARANGO_PASSWORD", "gaiaftcl2026")
NATS_URL = os.getenv("NATS_URL", "nats://gaiaftcl-nats:4222")
PROJECTION_URL = os.getenv("PROJECTION_URL", "http://gaiaos-mcp-server:9000")
# Mailcow: internal ops only via mailcow-bridge (docker exec mysql/doveadm). No Mailcow HTTP API.
MAILCOW_BRIDGE_URL = os.getenv("MAILCOW_BRIDGE_URL", "http://mailcow-bridge:8840")
# Self-wholeness: when NATS→reflection has no subscriber, call substrate-generative directly (Franklin path).
SUBSTRATE_GENERATIVE_URL = os.getenv(
    "SUBSTRATE_GENERATIVE_URL",
    os.getenv("SUBSTRATE_URL", "http://localhost:8805"),
)

# Sovereign UI / heavy AQL (e.g. materials domain COLLECT) may exceed 60s on large gaiaos DB.
HTTP_CLIENT = httpx.AsyncClient(timeout=float(os.getenv("GATEWAY_HTTP_TIMEOUT", "180")), verify=False)
NATS_CLIENT: Optional[NATS] = None

GRAPH_NAME = "gaiaftcl_knowledge_graph"
GRAPH_EDGE_COLLECTIONS = [
    "discovery_has_envelope",
    "discovery_has_claim",
    "compound_has_molecule",
    "material_has_candidate",
    "protein_targets_domain",
    "claim_references_discovery",
    "closure_closes_claim",
    "entity_has_vqbit",
    "vqbit_has_envelope",
    "domain_shares_invariant",
]


async def _arango_aql(query: str, bind_vars: Optional[Dict[str, Any]] = None) -> List[Any]:
    payload: Dict[str, Any] = {"query": query}
    if bind_vars:
        payload["bindVars"] = bind_vars
    resp = await HTTP_CLIENT.post(
        f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/cursor",
        json=payload,
        auth=(ARANGO_USER, ARANGO_PASSWORD),
    )
    if resp.status_code not in (200, 201):
        raise HTTPException(status_code=502, detail=f"Arango: {resp.text[:2000]}")
    return resp.json().get("result", [])


@app.on_event("startup")
async def startup():
    """Connect to NATS on startup"""
    global NATS_CLIENT
    try:
        NATS_CLIENT = await nats.connect(NATS_URL)
        print(f"✅ Connected to NATS: {NATS_URL}", flush=True)
    except Exception as e:
        print(f"⚠️ NATS connection failed: {e} - notifications disabled", flush=True)


@app.on_event("shutdown")
async def shutdown():
    """Disconnect from NATS on shutdown"""
    global NATS_CLIENT
    if NATS_CLIENT:
        await NATS_CLIENT.close()


@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "service": "gaiaftcl-mcp-gateway-dynamic",
        "nats_connected": NATS_CLIENT is not None and NATS_CLIENT.is_connected
    }


TYPE1_MOOR_SHARED_SECRET = os.getenv("TYPE1_MOOR_SHARED_SECRET", "").strip()
GAIAFTCL_INTERNAL_KEY = os.getenv("GAIAFTCL_INTERNAL_KEY", "").strip()


@app.get("/moor/ping")
async def moor_ping(x_type1_auth: Optional[str] = Header(None, alias="X-Type1-Auth")):
    """
    Authenticated witness for Type I PQ (Performance Qualification).
    Disabled unless TYPE1_MOOR_SHARED_SECRET is set on the gateway.
    """
    if not TYPE1_MOOR_SHARED_SECRET:
        raise HTTPException(status_code=503, detail="TYPE1 moor ping not configured")
    if not x_type1_auth or not secrets.compare_digest(x_type1_auth, TYPE1_MOOR_SHARED_SECRET):
        raise HTTPException(status_code=401, detail="invalid or missing X-Type1-Auth")
    return {
        "moor": "ok",
        "service": "gaiaftcl-mcp-gateway-dynamic",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


def _validate_claim_at_door(claim: Dict[str, Any]) -> bool:
    """
    Constitutional door validation. No keyword blacklists.
    Extractiveness is validated by axiom audit after envelope is produced.
    """
    # Requires wallet or caller for audit trail
    if not claim.get("wallet_address") and not claim.get("caller_id"):
        return False
    # Query must exist and have substance (or payload for knowledge claims)
    query = claim.get("query") or claim.get("content") or claim.get("intent") or str(claim.get("payload", ""))
    if not query or len(str(query).split()) < 2:
        return False
    return True


@app.post("/ingest")
async def ingest_claim(request: Dict[str, Any]):
    """Ingest knowledge into GaiaFTCL substrate. Substrate validates extractiveness via axiom audit."""
    if not _validate_claim_at_door(request):
        raise HTTPException(
            status_code=400,
            detail="Invalid claim: need wallet_address or caller_id, and query/content with substance"
        )

    # External callers (wallet_address, no caller_id) must authenticate via signature
    if request.get("wallet_address") and not request.get("caller_id"):
        if not verify_signature or not validate_authentication_payload:
            raise HTTPException(
                status_code=503,
                detail="Wallet authentication not available (eth_account not installed)"
            )
        ok, err = validate_authentication_payload(request)
        if not ok:
            raise HTTPException(status_code=401, detail=err)
        ok, err = verify_signature(
            request["wallet_address"],
            request["message"],
            request["signature"],
            int(request["timestamp"]),
        )
        if not ok:
            raise HTTPException(status_code=401, detail=err)

    claim_id = f"claim-{int(datetime.now(timezone.utc).timestamp() * 1000)}"
    cell_id = os.getenv("CELL_ID", os.getenv("GAIA_CELL_ID", "unknown-cell"))

    claim_doc = {
        "_key": claim_id,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "status": "pending",
        "cell_id": cell_id,
        **request
    }
    
    resp = await HTTP_CLIENT.post(
        f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/document/mcp_claims",
        json=claim_doc,
        auth=(ARANGO_USER, ARANGO_PASSWORD)
    )
    
    if resp.status_code not in [201, 202]:
        raise HTTPException(status_code=500, detail=f"Failed to store claim: {resp.text}")
    
    if NATS_CLIENT and NATS_CLIENT.is_connected:
        try:
            await NATS_CLIENT.publish(
                "gaiaftcl.claim.created",
                json.dumps({
                    "claim_id": claim_id,
                    "cell_id": cell_id,
                    "type": request.get("type", "unknown"),
                    "created_at": claim_doc["created_at"]
                }).encode()
            )
        except Exception as e:
            print(f"⚠️ NATS publish failed: {e}", flush=True)
    
    return {
        "claim_id": claim_id,
        "message": "Claim ingested - will notify when envelope ready"
    }


@app.post("/universal_ingest")
async def universal_ingest_route(
    request: Dict[str, Any],
    x_gaiaftcl_internal_key: Optional[str] = Header(None, alias="X-Gaiaftcl-Internal-Key"),
):
    """
    Delegates to universal_ingest.universal_ingest: typed claim (type/payload/from),
    secondary routing hooks, optional game_closure_events / philosophical_reflections writes.
    Does not replace POST /ingest (constitutional door + wallet path).
    """
    if GAIAFTCL_INTERNAL_KEY:
        if not x_gaiaftcl_internal_key or not secrets.compare_digest(
            x_gaiaftcl_internal_key, GAIAFTCL_INTERNAL_KEY
        ):
            raise HTTPException(status_code=403, detail="invalid X-Gaiaftcl-Internal-Key")
    return await universal_ingest(request)


@app.post("/envelope/close")
async def envelope_close_http(
    request: Dict[str, Any],
    x_gaiaftcl_internal_key: Optional[str] = Header(None, alias="X-Gaiaftcl-Internal-Key"),
):
    """Close envelope terminal state; broadcast receipt on NATS for Discord #receipts fan-in."""
    if GAIAFTCL_INTERNAL_KEY:
        if not x_gaiaftcl_internal_key or not secrets.compare_digest(
            x_gaiaftcl_internal_key, GAIAFTCL_INTERNAL_KEY
        ):
            raise HTTPException(status_code=403, detail="invalid X-Gaiaftcl-Internal-Key")
    terminal = str(request.get("terminal_state") or request.get("terminal") or "").strip()
    if not terminal:
        raise HTTPException(status_code=400, detail="terminal_state required")
    game_room = str(request.get("game_room") or "").strip()
    justified = str(request.get("justified_by") or request.get("source") or "gateway").strip()
    iso = datetime.now(timezone.utc).isoformat()
    receipt: Dict[str, Any] = {
        "kind": terminal,
        "type": "ENVELOPE_CLOSE",
        "terminal_state": terminal,
        "game_room": game_room,
        "justified_by": justified,
        "timestamp": iso,
    }
    if NATS_CLIENT and NATS_CLIENT.is_connected:
        try:
            subj = os.getenv("ENVELOPE_CLOSE_RECEIPT_SUBJECT", "gaiaftcl.receipts.envelope_close")
            await NATS_CLIENT.publish(subj, json.dumps(receipt).encode("utf-8"))
        except Exception as e:
            print(f"⚠️ envelope close NATS publish failed: {e}", flush=True)
    ledger_coll = os.getenv("ENVELOPE_LEDGER_COLLECTION", "envelope_ledger")
    lr = await HTTP_CLIENT.post(
        f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/document/{ledger_coll}",
        json={
            "kind": terminal,
            "game_room": game_room,
            "source": justified,
            "timestamp": iso,
            "channel": "discord_frontier",
        },
        auth=(ARANGO_USER, ARANGO_PASSWORD),
    )
    if lr.status_code == 404:
        raise HTTPException(status_code=503, detail=f"ledger collection missing: {ledger_coll}")
    if lr.status_code not in (200, 201, 202):
        raise HTTPException(status_code=503, detail=f"envelope_ledger write failed: {lr.text[:400]}")
    return {"accepted": True, "receipt": receipt}


def _vqbit_measurements_collection() -> str:
    coll = os.getenv("VQBIT_MEASUREMENTS_COLLECTION", "vqbit_measurements").strip()
    if not re.fullmatch(r"[A-Za-z0-9_]+", coll):
        raise ValueError("invalid VQBIT_MEASUREMENTS_COLLECTION")
    return coll


def _vqbit_vec(m: Dict[str, Any]) -> List[float]:
    s4 = m.get("s4") if isinstance(m.get("s4"), dict) else {}
    c4 = m.get("c4") if isinstance(m.get("c4"), dict) else {}
    return [
        float(s4.get("s1_structural") or 0),
        float(s4.get("s2_temporal") or 0),
        float(s4.get("s3_spatial") or 0),
        float(s4.get("s4_observable") or 0),
        float(c4.get("c1_trust") or 0),
        float(c4.get("c2_identity") or 0),
        float(c4.get("c3_closure") or 0),
        float(c4.get("c4_consequence") or 0),
    ]


@app.get("/vqbit/torsion")
async def get_torsion():
    """
    vQbit torsion vs mean anchor (last 1000 rows in vqbit_measurements).
    HTTP 200 always; failures → NOHARM + note (no uncaught gateway errors).
    """
    try:
        coll = _vqbit_measurements_collection()
        aql_main = """
        FOR m IN @@coll
          SORT m.timestamp DESC
          LIMIT @lim
          RETURN m
        """
        measurements_raw = await _arango_aql(
            aql_main,
            bind_vars={"@coll": coll, "lim": 1000},
        )
        measurements = [x for x in measurements_raw if isinstance(x, dict)]

        if len(measurements) < 2:
            return {
                "current_torsion": 0.0,
                "anchor_state": None,
                "system_state": "NOHARM",
                "measurement_count": len(measurements),
                "note": "insufficient measurements for torsion",
            }

        current = measurements[0]
        current_vec = _vqbit_vec(current)
        n = len(measurements)
        anchor_vec = [0.0] * 8
        for m in measurements:
            v = _vqbit_vec(m)
            for i in range(8):
                anchor_vec[i] += v[i]
        anchor_vec = [x / n for x in anchor_vec]
        anchor_mag = math.sqrt(sum(x * x for x in anchor_vec))

        if anchor_mag == 0.0:
            torsion = 0.0
        else:
            diff = [current_vec[i] - anchor_vec[i] for i in range(8)]
            diff_mag = math.sqrt(sum(x * x for x in diff))
            torsion = diff_mag / anchor_mag

        if torsion < 0.1:
            state = "NOHARM"
        elif torsion < 0.2:
            state = "STRESSED"
        elif torsion < 0.4:
            state = "APPROACHING_LIMIT"
        else:
            state = "COLLAPSED"

        aql_weakest = """
        FOR m IN @@coll
          SORT m.timestamp DESC
          LIMIT 100
          FILTER HAS(m, "cell_origin") && IS_OBJECT(m.c4) && IS_NUMBER(m.c4.c3_closure)
          COLLECT cell = m.cell_origin
          AGGREGATE avg_closure = AVG(m.c4.c3_closure)
          SORT avg_closure ASC
          LIMIT 1
          RETURN {cell: cell, avg_closure: avg_closure}
        """
        weakest: List[Any] = []
        try:
            weakest = await _arango_aql(
                aql_weakest,
                bind_vars={"@coll": coll},
            )
        except Exception:
            weakest = []

        return {
            "schema": "gaiaftcl.lean.bridge.v1",
            "current_torsion": {
                "value": round(torsion, 6),
                "measurement_timestamp": current.get("timestamp"),
            },
            "system_state": state,
            "anchor_state": {
                "magnitude": round(anchor_mag, 6),
                "measurement_count": len(measurements),
            },
            "weakest_cell": weakest[0] if weakest else None,
            "torsion_limit": 0.4,
            "sovereign_anchor": {
                "value": round(anchor_mag, 6),
                "derivation": "mean magnitude across last 1000 measurements",
            },
        }
    except Exception as e:
        err = str(e).lower()
        if "1203" in str(e) or "collection or view not found" in err:
            return {
                "current_torsion": 0.0,
                "anchor_state": None,
                "system_state": "NOHARM",
                "measurement_count": 0,
                "note": "insufficient measurements for torsion",
            }
        return {
            "current_torsion": {"value": 0.0},
            "system_state": "NOHARM",
            "error": str(e),
            "note": "vqbit_measurements empty or unreachable",
        }


# --- VIE-v2 (Vortex Ingestion Engine) -------------------------------------------------

VIE_EVENTS_COLLECTION = os.getenv("VIE_EVENTS_COLLECTION", "vie_events").strip()
DOMAIN_SCHEMAS_COLLECTION = os.getenv("DOMAIN_SCHEMAS_COLLECTION", "domain_schemas").strip()
VORTEX_ROOMS_COLLECTION = os.getenv("VORTEX_ROOMS_COLLECTION", "vortex_rooms").strip()
ENTITY_HAS_VQBIT_COLL = os.getenv("ENTITY_HAS_VQBIT_COLLECTION", "entity_has_vqbit").strip()
VQBIT_HAS_ENVELOPE_COLL = os.getenv("VQBIT_HAS_ENVELOPE_COLLECTION", "vqbit_has_envelope").strip()


def _vie_require_internal(x_gaiaftcl_internal_key: Optional[str]) -> None:
    if GAIAFTCL_INTERNAL_KEY:
        if not x_gaiaftcl_internal_key or not secrets.compare_digest(
            x_gaiaftcl_internal_key, GAIAFTCL_INTERNAL_KEY
        ):
            raise HTTPException(status_code=403, detail="invalid X-Gaiaftcl-Internal-Key")


def get_vie_engine_cfg() -> Dict[str, Any]:
    """Reload from disk + optional VIE_INVARIANT_CONFIG_PATH each call (dynamic substrate)."""
    try:
        from vie_v2.config_loader import load_invariant_config

        return load_invariant_config()
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"vie engine config: {e}")


def _vie_transformer_from(cfg: Dict[str, Any]) -> Any:
    if InvariantTransformer is None:
        raise HTTPException(status_code=503, detail="vie_v2 package not available on gateway")
    return InvariantTransformer(config=cfg)


def _vie_arango_insert_id(resp: Any) -> Optional[str]:
    if resp is None:
        return None
    try:
        j = resp.json()
    except Exception:
        return None
    if not isinstance(j, dict):
        return None
    if j.get("_id"):
        return str(j["_id"])
    new = j.get("new")
    if isinstance(new, dict) and new.get("_id"):
        return str(new["_id"])
    return None


def _vie_safe_subject_token(s: str) -> str:
    t = re.sub(r"[^a-zA-Z0-9_-]", "_", s)[:80]
    return t or "unknown"


@app.get("/vie/engine-config")
async def vie_engine_config_endpoint():
    """
    Full invariant engine JSON (thresholds, UI tokens, NATS prefix).
    No auth — treat as non-secret tuning surface; lock behind mesh if needed.
    """
    try:
        from vie_v2.config_loader import load_invariant_config

        return load_invariant_config()
    except Exception as e:
        raise HTTPException(status_code=503, detail=str(e))


async def _vie_load_domain_schema(name: str) -> Dict[str, Any]:
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", name):
        raise HTTPException(status_code=400, detail="invalid domain_schema_name")
    rows = await _arango_aql("RETURN DOCUMENT(@id)", {"id": f"{DOMAIN_SCHEMAS_COLLECTION}/{name}"})
    doc = rows[0] if rows and rows[0] is not None else None
    if isinstance(doc, dict) and doc:
        if "mapping" in doc and isinstance(doc["mapping"], dict):
            return doc
        if isinstance(doc.get("schema"), dict):
            return {"mapping": doc["schema"]}
        return doc
    path = os.path.join(os.path.dirname(__file__), "vie_v2", "domain_schemas", f"{name}.json")
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail=f"domain schema not found: {name}")
    with open(path, encoding="utf-8") as f:
        return json.load(f)


@app.post("/vie/schema")
async def vie_register_schema(
    request: Dict[str, Any],
    x_gaiaftcl_internal_key: Optional[str] = Header(None, alias="X-Gaiaftcl-Internal-Key"),
):
    """Register or replace a domain facade (constants + mapping + optional engine_override)."""
    _vie_require_internal(x_gaiaftcl_internal_key)
    name = str(request.get("name") or request.get("domain_schema_name") or "").strip()
    mapping = request.get("mapping")
    if not name or not isinstance(mapping, dict):
        raise HTTPException(status_code=400, detail="name and mapping object required")
    iso = datetime.now(timezone.utc).isoformat()
    doc: Dict[str, Any] = {
        "_key": name,
        "mapping": mapping,
        "registered_at": iso,
        "source": "vie_v2_post_schema",
    }
    if isinstance(request.get("constants"), dict):
        doc["constants"] = request["constants"]
    if isinstance(request.get("engine_override"), dict):
        doc["engine_override"] = request["engine_override"]
    resp = await HTTP_CLIENT.post(
        f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/document/{DOMAIN_SCHEMAS_COLLECTION}",
        json=doc,
        auth=(ARANGO_USER, ARANGO_PASSWORD),
        params={"overwriteMode": "replace", "returnNew": "true"},
    )
    if resp.status_code == 404:
        raise HTTPException(status_code=503, detail=f"collection missing: {DOMAIN_SCHEMAS_COLLECTION}")
    if resp.status_code not in (200, 201, 202):
        raise HTTPException(status_code=503, detail=f"domain_schemas write failed: {resp.text[:400]}")
    return {"accepted": True, "name": name, "registered_at": iso}


@app.post("/vie/ingest")
async def vie_ingest(
    request: Dict[str, Any],
    x_gaiaftcl_internal_key: Optional[str] = Header(None, alias="X-Gaiaftcl-Internal-Key"),
):
    """
    Transform raw_data through named domain schema; persist VqBit + legacy measurement projection.
    """
    _vie_require_internal(x_gaiaftcl_internal_key)
    if vie_to_legacy_measurement is None:
        raise HTTPException(status_code=503, detail="vie_v2 projection unavailable")
    raw_data = request.get("raw_data")
    schema_name = str(request.get("domain_schema_name") or "").strip()
    entity_id = str(request.get("entity_id") or "").strip()
    if not isinstance(raw_data, dict) or not schema_name:
        raise HTTPException(
            status_code=400,
            detail="raw_data (object) and domain_schema_name required",
        )
    domain_schema = await _vie_load_domain_schema(schema_name)
    cfg = get_vie_engine_cfg()
    tr = _vie_transformer_from(cfg)
    vqbit = tr.map_to_vqbit(raw_data, domain_schema, entity_id_override=entity_id or None)
    if not str(vqbit.get("entity_id") or "").strip():
        raise HTTPException(status_code=400, detail="entity_id missing after mapping")

    iso = datetime.now(timezone.utc).isoformat()
    measure_doc = vie_to_legacy_measurement(vqbit, engine_config=cfg)
    measure_doc["receipt_hash"] = vqbit["receipt_hash"]
    measure_doc["_key"] = f"v2-{vqbit['receipt_hash']}"
    vq_coll = _vqbit_measurements_collection()
    mresp = await HTTP_CLIENT.post(
        f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/document/{vq_coll}",
        json=measure_doc,
        auth=(ARANGO_USER, ARANGO_PASSWORD),
        params={"overwriteMode": "replace", "returnNew": "true"},
    )
    if mresp.status_code == 404:
        raise HTTPException(status_code=503, detail=f"collection missing: {vq_coll}")
    if mresp.status_code not in (200, 201, 202):
        raise HTTPException(status_code=503, detail=f"vqbit_measurements write failed: {mresp.text[:400]}")
    vqbit_id = _vie_arango_insert_id(mresp)
    if not vqbit_id:
        raise HTTPException(status_code=503, detail="vqbit insert did not return _id")

    ve_key = f"vie-{int(datetime.now(timezone.utc).timestamp() * 1000)}-{vqbit['receipt_hash']}"
    ve_doc = {
        "_key": ve_key[:250],
        **vqbit,
        "schema_name": schema_name,
        "vqbit_measurement_id": vqbit_id,
        "ingested_at": iso,
    }
    veresp = await HTTP_CLIENT.post(
        f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/document/{VIE_EVENTS_COLLECTION}",
        json=ve_doc,
        auth=(ARANGO_USER, ARANGO_PASSWORD),
        params={"returnNew": "true"},
    )
    if veresp.status_code == 404:
        raise HTTPException(status_code=503, detail=f"collection missing: {VIE_EVENTS_COLLECTION}")
    if veresp.status_code not in (200, 201, 202):
        raise HTTPException(status_code=503, detail=f"vie_events write failed: {veresp.text[:400]}")
    vie_id = _vie_arango_insert_id(veresp)
    if not vie_id:
        raise HTTPException(status_code=503, detail="vie_events insert did not return _id")

    ledger_coll = os.getenv("ENVELOPE_LEDGER_COLLECTION", "envelope_ledger")
    ledger_doc: Dict[str, Any] = {
        "kind": str(vqbit.get("terminal_signal") or "VIE"),
        "game_room": "vie_v2",
        "source": "vie_ingest",
        "timestamp": vqbit.get("timestamp"),
        "channel": "gateway",
        "entity_id": vqbit.get("entity_id"),
        "domain": vqbit.get("domain"),
        "receipt_hash": vqbit.get("receipt_hash"),
        "terminal_signal": vqbit.get("terminal_signal"),
    }
    lresp = await HTTP_CLIENT.post(
        f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/document/{ledger_coll}",
        json=ledger_doc,
        auth=(ARANGO_USER, ARANGO_PASSWORD),
        params={"returnNew": "true"},
    )
    ledger_id = None
    if lresp.status_code in (200, 201, 202):
        ledger_id = _vie_arango_insert_id(lresp)

    now_iso = datetime.now(timezone.utc).isoformat()
    if vie_id and vqbit_id:
        await HTTP_CLIENT.post(
            f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/document/{ENTITY_HAS_VQBIT_COLL}",
            json={
                "_from": vie_id,
                "_to": vqbit_id,
                "created_at": now_iso,
                "relationship_type": "entity_has_vqbit",
                "source": "vie_ingest",
            },
            auth=(ARANGO_USER, ARANGO_PASSWORD),
        )
    if ledger_id and vqbit_id:
        await HTTP_CLIENT.post(
            f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/document/{VQBIT_HAS_ENVELOPE_COLL}",
            json={
                "_from": vqbit_id,
                "_to": ledger_id,
                "created_at": now_iso,
                "relationship_type": "vqbit_has_envelope",
                "source": "vie_ingest",
            },
            auth=(ARANGO_USER, ARANGO_PASSWORD),
        )

    mirror = str(request.get("mirror_collection") or "").strip()
    if mirror and re.fullmatch(r"discovered_[a-z0-9_]+", mirror):
        ent_key = re.sub(r"[^a-zA-Z0-9_-]", "_", str(vqbit["entity_id"]))[:200] or "entity"
        disc_doc: Dict[str, Any] = {
            "_key": ent_key,
            "vie_v2_mirror": True,
            "last_vqbit": vqbit,
            "domain": vqbit.get("domain"),
            "updated_at": iso,
        }
        dresp = await HTTP_CLIENT.post(
            f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/document/{mirror}",
            json=disc_doc,
            auth=(ARANGO_USER, ARANGO_PASSWORD),
            params={"overwriteMode": "replace", "returnNew": "true"},
        )
        if dresp.status_code not in (200, 201, 202):
            print(f"⚠️ vie mirror to {mirror} failed: {dresp.text[:300]}", flush=True)

    gway = cfg.get("gateway") or {}
    min_p = float(os.getenv("VIE_VORTEX_PUBLISH_MIN_PSB", str(gway.get("vortex_publish_min_psb", 0.85))))
    subj_prefix = str(gway.get("vortex_nats_subject_prefix") or "gaiaftcl.vie.vortex").strip()
    if (
        NATS_CLIENT
        and NATS_CLIENT.is_connected
        and float(vqbit.get("symmetry_break_probability") or 0) >= min_p
    ):
        subj = f"{subj_prefix}.{_vie_safe_subject_token(str(vqbit['entity_id']))}"
        try:
            await NATS_CLIENT.publish(
                subj,
                json.dumps(
                    {"vqbit": vqbit, "schema_name": schema_name, "vie_event_id": vie_id},
                    default=str,
                ).encode("utf-8"),
            )
        except Exception as e:
            print(f"⚠️ VIE vortex NATS publish failed: {e}", flush=True)

    return {
        "vqbit": vqbit,
        "terminal_signal": vqbit.get("terminal_signal"),
        "receipt_hash": vqbit.get("receipt_hash"),
        "vie_event_id": vie_id,
        "vqbit_measurement_id": vqbit_id,
        "envelope_ledger_id": ledger_id,
    }


@app.get("/vie/probe")
async def vie_probe(
    entity_id: str = Query(..., min_length=1),
    domain: str = Query(""),
    x_gaiaftcl_internal_key: Optional[str] = Header(None, alias="X-Gaiaftcl-Internal-Key"),
):
    _vie_require_internal(x_gaiaftcl_internal_key)
    cfg = get_vie_engine_cfg()
    tr = _vie_transformer_from(cfg)
    rows = await _arango_aql(
        """
        FOR v IN @@coll
          FILTER v.entity_id == @eid
          FILTER @dom == "" OR v.domain == @dom
          SORT v.ingested_at DESC, v.timestamp DESC
          LIMIT 1
          RETURN v
        """,
        {"@coll": VIE_EVENTS_COLLECTION, "eid": entity_id, "dom": domain.strip()},
    )
    if not rows or not isinstance(rows[0], dict):
        raise HTTPException(status_code=404, detail="no VqBit row for entity/domain")
    stored = dict(rows[0])
    for k in ("_id", "_key", "_rev"):
        stored.pop(k, None)
    live = tr.derive_live(stored, cfg=cfg)
    return {
        "entity_id": entity_id,
        "domain": domain or stored.get("domain"),
        "stored": stored,
        "live": live,
        "coordinates": {
            "origin": stored.get("origin"),
            "gravity": stored.get("gravity"),
            "entropy_potential": stored.get("entropy_potential"),
            "vortex": stored.get("vortex"),
        },
    }


@app.get("/vie/vortex")
async def vie_vortex(
    domain: str = Query(""),
    threshold: float = Query(0.65, ge=0.0, le=1.0),
    limit: int = Query(20, ge=1, le=200),
    x_gaiaftcl_internal_key: Optional[str] = Header(None, alias="X-Gaiaftcl-Internal-Key"),
):
    _vie_require_internal(x_gaiaftcl_internal_key)
    rows = await _arango_aql(
        """
        FOR v IN @@coll
          FILTER @dom == "" OR v.domain == @dom
          FILTER TO_NUMBER(v.symmetry_break_probability) > @thr
          SORT TO_NUMBER(v.symmetry_break_probability) DESC
          LIMIT @lim
          RETURN {
            entity_id: v.entity_id,
            domain: v.domain,
            domain_instance: v.domain_instance,
            symmetry_break_probability: v.symmetry_break_probability,
            terminal_signal: v.terminal_signal,
            timestamp: v.timestamp,
            receipt_hash: v.receipt_hash
          }
        """,
        {"@coll": VIE_EVENTS_COLLECTION, "dom": domain.strip(), "thr": threshold, "lim": limit},
    )
    return {
        "domain": domain or None,
        "threshold": threshold,
        "count": len(rows),
        "events": rows,
    }


@app.post("/vie/vortex-room")
async def vie_vortex_room_register(
    request: Dict[str, Any],
    x_gaiaftcl_internal_key: Optional[str] = Header(None, alias="X-Gaiaftcl-Internal-Key"),
):
    """Discord membrane registers a provisioned vortex channel (vortex_rooms ledger)."""
    _vie_require_internal(x_gaiaftcl_internal_key)
    cid = str(request.get("channel_id") or "").strip()
    if not cid:
        raise HTTPException(status_code=400, detail="channel_id required")
    eid = str(request.get("entity_id") or "").strip()
    iso = datetime.now(timezone.utc).isoformat()
    doc = {
        "_key": f"vr-{cid}"[:250],
        "channel_id": cid,
        "entity_id": eid,
        "guild_id": str(request.get("guild_id") or ""),
        "opened_at": iso,
        "expires_at": request.get("expires_at"),
        "terminal_signal": request.get("terminal_signal"),
        "psb": request.get("symmetry_break_probability"),
        "bloom": request.get("bloom"),
        "vortex_parent_key": request.get("vortex_parent_key"),
    }
    resp = await HTTP_CLIENT.post(
        f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/document/{VORTEX_ROOMS_COLLECTION}",
        json=doc,
        auth=(ARANGO_USER, ARANGO_PASSWORD),
        params={"overwriteMode": "replace", "returnNew": "true"},
    )
    if resp.status_code == 404:
        raise HTTPException(status_code=503, detail=f"collection missing: {VORTEX_ROOMS_COLLECTION}")
    if resp.status_code not in (200, 201, 202):
        raise HTTPException(status_code=503, detail=f"vortex_rooms write failed: {resp.text[:400]}")
    return {"accepted": True, "key": doc["_key"]}


@app.get("/vie/schemas")
async def vie_list_schemas(
    x_gaiaftcl_internal_key: Optional[str] = Header(None, alias="X-Gaiaftcl-Internal-Key"),
):
    """Registered Arango schemas plus bundled JSON filenames (union)."""
    _vie_require_internal(x_gaiaftcl_internal_key)
    reg_q = f"FOR d IN {DOMAIN_SCHEMAS_COLLECTION} SORT d._key RETURN d._key"
    reg: List[Any] = []
    try:
        reg = await _arango_aql(reg_q)
    except Exception:
        reg = []
    bundled: List[str] = []
    ddir = os.path.join(os.path.dirname(__file__), "vie_v2", "domain_schemas")
    if os.path.isdir(ddir):
        for fn in sorted(os.listdir(ddir)):
            if fn.endswith(".json"):
                bundled.append(fn[: -len(".json")])
    keys = sorted({str(x) for x in reg if x} | set(bundled))
    return {"registered_in_arango": reg, "bundled_files": bundled, "all_names": keys}


@app.get("/discovery/{discovery_id}")
async def discovery_entropy_gate(
    discovery_id: str,
    x_wallet_address: Optional[str] = Header(None, alias="X-Wallet-Address"),
    discovery_collection: str = Query(default="discovered_compounds"),
):
    """Gated read: valid wallet + active entropy_licenses row for this discovery."""
    wallet = (x_wallet_address or "").strip()
    if not wallet:
        raise HTTPException(status_code=400, detail="X-Wallet-Address required")
    if is_valid_wallet_address:
        wok = is_valid_wallet_address(wallet)
    else:
        wok = bool(re.fullmatch(r"(?i)0x[a-f0-9]{40}", wallet))
    if not wok:
        raise HTTPException(status_code=400, detail="invalid X-Wallet-Address")
    coll = (discovery_collection or "discovered_compounds").strip()
    doc_id = f"{coll}/{discovery_id}"
    dq = await HTTP_CLIENT.post(
        f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/cursor",
        json={"query": "RETURN DOCUMENT(@id)", "bindVars": {"id": doc_id}},
        auth=(ARANGO_USER, ARANGO_PASSWORD),
    )
    if dq.status_code != 200:
        raise HTTPException(status_code=503, detail=f"substrate read failed: {dq.text[:200]}")
    drows = dq.json().get("result") or []
    if not drows or drows[0] is None:
        raise HTTPException(status_code=404, detail=f"discovery not found: {doc_id}")
    lic_coll = os.getenv("ENTROPY_LICENSES_COLLECTION", "entropy_licenses")
    ex_q = await HTTP_CLIENT.post(
        f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/cursor",
        json={
            "query": (
                f"FOR l IN {lic_coll} "
                "FILTER LOWER(l.wallet_address) == LOWER(@w) AND l.discovery_id == @d "
                'AND l.license_status == "ACTIVE" LIMIT 1 RETURN l'
            ),
            "bindVars": {"w": wallet, "d": discovery_id},
        },
        auth=(ARANGO_USER, ARANGO_PASSWORD),
    )
    if ex_q.status_code != 200:
        raise HTTPException(status_code=503, detail="license query failed")
    ex = ex_q.json().get("result") or []
    if not ex:
        raise HTTPException(
            status_code=402,
            detail="no active entropy license for this wallet and discovery",
        )
    return {
        "discovery_id": discovery_id,
        "discovery_collection": coll,
        "wallet_address": wallet,
        "license": ex[0],
    }


@app.get("/claims")
async def get_claims(
    limit: int = Query(default=20, ge=1, le=1000, description="Max claim documents to return"),
    payload_filter: str = Query(
        default="",
        alias="filter",
        description="Case-insensitive substring match against TO_STRING(c.payload)",
    ),
):
    """
    Raw mcp_claims documents, newest first (by created_at, same basis as query_full_substrate recent_claims).
    Optional filter narrows to rows whose payload string contains the given substring.
    """
    aql = """
    FOR c IN mcp_claims
      FILTER @payload_match == "" OR CONTAINS(LOWER(TO_STRING(c.payload)), LOWER(@payload_match))
      SORT c.created_at DESC
      LIMIT @lim
      RETURN c
    """
    resp = await HTTP_CLIENT.post(
        f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/cursor",
        json={"query": aql, "bindVars": {"lim": limit, "payload_match": payload_filter or ""}},
        auth=(ARANGO_USER, ARANGO_PASSWORD),
    )
    if resp.status_code not in [200, 201]:
        raise HTTPException(status_code=500, detail=f"Claims query failed: {resp.text}")
    return resp.json().get("result", [])


@app.post("/mailcow/mailbox")
async def mailcow_create_mailbox(request: Dict[str, Any]):
    """
    Create mailbox via mailcow-bridge (docker exec mysql). Internal ops only — no Mailcow HTTP API.
    Requires caller_id. Proxies to mailcow-bridge.
    """
    if not request.get("caller_id"):
        raise HTTPException(status_code=400, detail="caller_id required for mailcow operations")
    payload = {
        "caller_id": request["caller_id"],
        "local_part": request.get("local_part") or (request.get("email", "").split("@")[0]),
        "domain": request.get("domain", "gaiaftcl.com"),
        "name": request.get("name", request.get("local_part", "")),
        "password": request.get("password", ""),
        "quota": request.get("quota", 0),
    }
    resp = await HTTP_CLIENT.post(f"{MAILCOW_BRIDGE_URL}/mailbox/create", json=payload)
    if resp.status_code in [200, 201]:
        return resp.json()
    raise HTTPException(status_code=resp.status_code, detail=resp.text)


@app.get("/mailcow/mailboxes")
async def mailcow_list_mailboxes(caller_id: str = ""):
    """List mailboxes via mailcow-bridge (docker exec mysql). Internal ops only. Requires caller_id."""
    if not caller_id:
        raise HTTPException(status_code=400, detail="caller_id required")
    resp = await HTTP_CLIENT.get(f"{MAILCOW_BRIDGE_URL}/mailboxes", params={"caller_id": caller_id})
    if resp.status_code != 200:
        raise HTTPException(status_code=resp.status_code, detail=resp.text)
    return resp.json()


@app.post("/mailcow/fetch_verification")
async def mailcow_fetch_verification(request: Dict[str, Any]):
    """Fetch verification email via mailcow-bridge (doveadm). Requires caller_id."""
    if not request.get("caller_id"):
        raise HTTPException(status_code=400, detail="caller_id required")
    email = request.get("email")
    if not email:
        raise HTTPException(status_code=400, detail="email required")
    try:
        resp = await HTTP_CLIENT.post(
            f"{MAILCOW_BRIDGE_URL}/fetch_verification_email",
            json={"caller_id": request["caller_id"], "email": email},
            timeout=35,
        )
        if resp.status_code != 200:
            raise HTTPException(status_code=resp.status_code, detail=resp.text)
        return resp.json()
    except httpx.ConnectError:
        raise HTTPException(status_code=503, detail="mailcow-bridge not reachable")


def extract_comparables_from_query(query: str) -> List[Tuple[str, float, str]]:
    """Extract valuation comparables mentioned in query - handles B and T suffixes"""
    comparables = []
    q_lower = query.lower()
    
    # Tesla mentioned
    if 'tesla' in q_lower:
        val_match = re.search(r'tesla[:\s]*\$?(\d+\.?\d*)([bt])', q_lower)
        if val_match:
            val = float(val_match.group(1))
            if val_match.group(2) == 't':
                val *= 1000  # Convert trillions to billions
        else:
            val = 850
        comparables.append(('Tesla', val, 'energy/transport/battery/AI'))
    
    # SpaceX
    if 'spacex' in q_lower:
        val_match = re.search(r'spacex[:\s]*\$?(\d+\.?\d*)([bt])', q_lower)
        if val_match:
            val = float(val_match.group(1))
            if val_match.group(2) == 't':
                val *= 1000
        else:
            val = 350
        comparables.append(('SpaceX', val, 'aerospace/materials/launch'))
    
    # Palantir
    if 'palantir' in q_lower:
        val_match = re.search(r'palantir[:\s]*\$?(\d+\.?\d*)([bt])', q_lower)
        if val_match:
            val = float(val_match.group(1))
            if val_match.group(2) == 't':
                val *= 1000
        else:
            val = 150
        comparables.append(('Palantir', val, 'AI/data/defense/government'))
    
    # NVIDIA
    if 'nvidia' in q_lower:
        val_match = re.search(r'nvidia[:\s]*\$?(\d+\.?\d*)([bt])', q_lower)
        if val_match:
            val = float(val_match.group(1))
            if val_match.group(2) == 't':
                val *= 1000
        else:
            val = 2200  # $2.2T default
        comparables.append(('NVIDIA', val, 'AI infrastructure/compute platform'))
    
    # xAI
    if 'xai' in q_lower:
        val_match = re.search(r'xai[:\s]*\$?(\d+\.?\d*)([bt])', q_lower)
        if val_match:
            val = float(val_match.group(1))
            if val_match.group(2) == 't':
                val *= 1000
        else:
            val = 50
        comparables.append(('xAI', val, 'frontier AI'))
    
    # Neuralink
    if 'neuralink' in q_lower:
        val_match = re.search(r'neuralink[:\s]*\$?(\d+\.?\d*)([bt])', q_lower)
        if val_match:
            val = float(val_match.group(1))
            if val_match.group(2) == 't':
                val *= 1000
        else:
            val = 8
        comparables.append(('Neuralink', val, 'brain-computer interfaces'))
    
    # OpenAI
    if 'openai' in q_lower:
        val_match = re.search(r'openai[:\s]*\$?(\d+\.?\d*)([bt])', q_lower)
        if val_match:
            val = float(val_match.group(1))
            if val_match.group(2) == 't':
                val *= 1000
        else:
            val = 200
        comparables.append(('OpenAI', val, 'frontier AI/ChatGPT'))
    
    # Anthropic
    if 'anthropic' in q_lower:
        val_match = re.search(r'anthropic[:\s]*\$?(\d+\.?\d*)([bt])', q_lower)
        if val_match:
            val = float(val_match.group(1))
            if val_match.group(2) == 't':
                val *= 1000
        else:
            val = 60
        comparables.append(('Anthropic', val, 'frontier AI/Claude'))
    
    return comparables


async def _load_prior_turns_for_wallet(wallet_address: str) -> List[Dict[str, Any]]:
    """Load prior turns from truth_envelopes for this wallet. For friend context."""
    try:
        resp = await HTTP_CLIENT.post(
            f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/cursor",
            json={
                "query": """
                    FOR e IN truth_envelopes
                    FILTER e.wallet_address == @wallet
                    SORT e.created_at DESC
                    LIMIT 5
                    FILTER e.turn_log != null
                    RETURN e.turn_log
                """,
                "bindVars": {"wallet": wallet_address}
            },
            auth=(ARANGO_USER, ARANGO_PASSWORD)
        )
        if resp.status_code not in [200, 201]:
            return []
        results = resp.json().get("result", [])
        turns = []
        for log in results:
            if isinstance(log, list):
                for t in log[-3:]:  # Last 3 per envelope
                    if isinstance(t, dict) and t.get("query"):
                        turns.append({"query": t["query"], "discovery_refs": t.get("discovery_refs", [])})
        return turns[-10:]  # Max 10 prior turns
    except Exception as e:
        print(f"⚠️ Load prior turns failed: {e}", flush=True)
        return []


async def query_full_substrate() -> Dict[str, Any]:
    """Query GaiaFTCL's complete substrate state - works with actual collections"""
    query = """
    LET metrics = {
        claims: LENGTH(FOR c IN mcp_claims RETURN 1),
        envelopes: LENGTH(FOR e IN truth_envelopes RETURN 1)
    }
    
    LET knowledge = (
        FOR c IN mcp_claims
        FILTER c.envelope_type == "KNOWLEDGE" AND c.payload != null
        SORT c.created_at DESC
        LIMIT 50
        RETURN {
            source: c.source,
            content: c.payload.content,
            title: c.payload.title,
            document_type: c.payload.document_type,
            category: c.payload.category,
            created: c.created_at
        }
    )
    
    LET all_envelopes = (
        FOR e IN truth_envelopes
        SORT e.created_at DESC
        LIMIT 100
        RETURN {
            id: e._key,
            type: e.envelope_type,
            state: e.state,
            turn: e.turn,
            game_id: e.game_id,
            delta_entropy: e.delta_entropy,
            created: e.created_at
        }
    )
    
    LET game_states = (
        FOR e IN truth_envelopes
        FILTER e.game_id != null
        COLLECT game_id = e.game_id INTO game_envelopes = e
        SORT game_id
        RETURN {
            game_id: game_id,
            envelope_count: LENGTH(game_envelopes),
            latest_turn: MAX(game_envelopes[*].turn),
            total_delta_entropy: SUM(game_envelopes[*].delta_entropy)
        }
    )
    
    LET recent_claims = (
        FOR c IN mcp_claims
        SORT c.created_at DESC
        LIMIT 30
        RETURN {
            id: c._key,
            type: c.type,
            envelope_type: c.envelope_type,
            source: c.source,
            status: c.status,
            created: c.created_at,
            mail_summary: (c.type == "MAIL" && c.payload != null) ? {
                game_room: c.payload.game_room,
                mail_from: c.payload.from,
                subject: c.payload.subject,
                body_preview: SUBSTRING(c.payload.body != null ? c.payload.body : "", 0, 500)
            } : null
        }
    )
    
    RETURN {
        metrics: metrics,
        knowledge: knowledge,
        envelopes: all_envelopes,
        games: game_states,
        recent_claims: recent_claims
    }
    """
    
    resp = await HTTP_CLIENT.post(
        f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/cursor",
        json={"query": query},
        auth=(ARANGO_USER, ARANGO_PASSWORD)
    )
    
    if resp.status_code != 201:
        print(f"❌ ArangoDB query failed: status={resp.status_code}, body={resp.text[:200]}", flush=True)
        return {"error": "Substrate query failed"}
    
    result = resp.json().get("result", [{}])
    return result[0] if result else {}


async def invoke_substrate_generative_direct(
    query: str,
    substrate: Dict[str, Any],
    wallet_address: Optional[str] = None,
    audience_position: Optional[List[float]] = None,
    prior_turns: Optional[List[Dict[str, Any]]] = None,
) -> str:
    """
    GaiaFTCL self-wholeness path: same /api/generate as franklin_reflection_game when NATS ring is open.
    Does not replace reflection+NATS when both work; fills the gap when no consumer responds.
    """
    context: Dict[str, Any] = {
        "substrate_metrics": substrate.get("metrics", {}),
        "knowledge_count": len(substrate.get("knowledge", [])),
        "envelope_count": substrate.get("metrics", {}).get("envelopes", 0),
    }
    if wallet_address:
        context["wallet_address"] = wallet_address
    if audience_position:
        context["audience_position"] = audience_position
    if prior_turns:
        context["prior_turns"] = prior_turns
        context["is_continuation"] = len(prior_turns) > 0
    try:
        url = f"{SUBSTRATE_GENERATIVE_URL.rstrip('/')}/api/generate"
        resp = await HTTP_CLIENT.post(
            url,
            json={"query": query, "context": context},
            timeout=60.0,
        )
        if resp.status_code != 200:
            print(f"⚠️ Direct substrate /api/generate HTTP {resp.status_code}", flush=True)
            return ""
        data = resp.json()
        if not data.get("generated"):
            return ""
        out = data.get("output") or {}
        text = out.get("narrative") or data.get("essay") or data.get("response") or ""
        if text:
            print(f"✅ Self-heal: direct substrate narrative ({len(text)} chars)", flush=True)
        return text if isinstance(text, str) else ""
    except Exception as e:
        print(f"⚠️ Direct substrate generate (self-heal) failed: {e}", flush=True)
        return ""


async def invoke_quantum_language_game(
    query: str,
    substrate: Dict[str, Any],
    wallet_address: Optional[str] = None,
    audience_position: Optional[List[float]] = None,
    prior_turns: Optional[List[Dict[str, Any]]] = None
) -> str:
    """
    Route philosophical query to G_FRANKLIN_REFLECTION_L0 game via NATS.
    Pass wallet + prior_turns so she treats you like a friend, in context.
    Substrate queries its own DB internally - MCP never touches GaiaFTCL's database.
    """
    if not NATS_CLIENT or not NATS_CLIENT.is_connected:
        return "Error: NATS not connected - cannot invoke quantum substrate"
    
    try:
        request_id = f"reflection-{int(datetime.now(timezone.utc).timestamp() * 1000)}"
        
        context = {
            "substrate_metrics": substrate.get('metrics', {}),
            "knowledge_count": len(substrate.get('knowledge', [])),
            "envelope_count": substrate.get('metrics', {}).get('envelopes', 0)
        }
        if wallet_address:
            context["wallet_address"] = wallet_address
        if audience_position:
            context["audience_position"] = audience_position
        if prior_turns:
            context["prior_turns"] = prior_turns
            context["is_continuation"] = len(prior_turns) > 0
        
        request_payload = {
            "request_id": request_id,
            "query": query,
            "context": context,
            "game_id": "G_FRANKLIN_REFLECTION_L0",
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
        
        print(f"📡 Publishing reflection request to NATS: {request_id}", flush=True)
        
        # Subscribe to response before publishing request
        response_subject = f"gaiaftcl.reflection.response.{request_id}"
        subscription = await NATS_CLIENT.subscribe(response_subject)
        
        # Publish request
        await NATS_CLIENT.publish(
            "gaiaftcl.reflection.request",
            json.dumps(request_payload).encode()
        )
        
        # Wait for response (30 second timeout for quantum substrate to generate essay)
        try:
            msg = await asyncio.wait_for(subscription.next_msg(timeout=30), timeout=35)
            response = json.loads(msg.data.decode())
            
            print(f"✅ Received quantum language game response ({len(response.get('essay', ''))} chars)", flush=True)
            
            return response.get('essay', response.get('response', 'Error: No essay in response'))
        except asyncio.TimeoutError:
            print(f"⏱️ Quantum language game timeout after 30s", flush=True)
            return "Error: Quantum substrate did not respond in time"
        finally:
            await subscription.unsubscribe()
            
    except Exception as e:
        print(f"❌ Quantum language game invocation failed: {e}", flush=True)
        return f"Error: {str(e)}"


def _audience_position_indicates_investor(audience_position: Optional[List[float]]) -> bool:
    """Derive investor-like audience from 8D manifold position. No keyword routing."""
    if not audience_position or len(audience_position) != 8:
        return False
    # D2 (charge/finance), D5 (time_dynamics) - high values indicate investor-like position
    return audience_position[2] > 0.65 and audience_position[5] > 0.65


async def generate_dynamic_response(
    query: str,
    substrate: Dict[str, Any],
    audience_position: Optional[List[float]] = None,
    wallet_address: Optional[str] = None,
    prior_turns: Optional[List[Dict[str, Any]]] = None
) -> str:
    """
    Thin adapter per G_FREESTYLE_L0. Route by manifold only. No keyword routing. Valuation = substrate query.
    NO direct DB access - GaiaFTCL's database is internal. All discovery queries flow via MCP dialog → NATS → substrate.
    """
    # Invoke quantum language game (NATS -> reflection game)
    # Substrate queries its own DB internally; MCP gateway never touches ArangoDB
    essay = await invoke_quantum_language_game(
        query, substrate,
        wallet_address=wallet_address,
        audience_position=audience_position,
        prior_turns=prior_turns
    )
    if essay and not essay.startswith("Error:"):
        return essay
    # Self-wholeness: NATS timeout / no reflection consumer → direct substrate-generative (her own API).
    healed = await invoke_substrate_generative_direct(
        query, substrate,
        wallet_address=wallet_address,
        audience_position=audience_position,
        prior_turns=prior_turns,
    )
    if healed:
        return healed
    # Minimal fallback — still surface recent MAIL rows so /ask can witness owl_protocol / INV3 threads
    metrics = substrate.get('metrics', {})
    claims = metrics.get('claims', 0)
    envelopes = metrics.get('envelopes', 0)
    mail_blocks: list[str] = []
    for rc in substrate.get('recent_claims') or []:
        if not isinstance(rc, dict):
            continue
        ms = rc.get('mail_summary')
        if isinstance(ms, dict) and (ms.get('mail_from') or ms.get('subject') or ms.get('body_preview')):
            mail_blocks.append(
                f"MAIL {rc.get('id')}: from={ms.get('mail_from')} room={ms.get('game_room')} "
                f"subject={ms.get('subject')} preview={str(ms.get('body_preview', ''))[:320]}"
            )
    if mail_blocks:
        return (
            "Inbound research mail (substrate recent_claims):\n"
            + "\n".join(mail_blocks[:15])
            + f"\n\nMetrics: {claims:,} claims, {envelopes:,} envelopes. (NATS/generative path skipped.)"
        )
    return f"Substrate unreachable. {claims:,} claims, {envelopes:,} envelopes. Valuation = substrate query."


# Legacy valuation synthesis removed per G_FREESTYLE_L0. Valuation = substrate query.


@app.post("/deploy")
async def trigger_self_deployment(request: Dict[str, Any]):
    """Trigger GaiaFTCL to deploy herself across all 9 cells via NATS."""
    if not NATS_CLIENT or not NATS_CLIENT.is_connected:
        raise HTTPException(status_code=503, detail="NATS not connected")
    try:
        service_name = request.get("service", "gaiaftcl-mcp-gateway")
        image_name = f"{service_name}:latest"
        compose_service = request.get("compose_service", "fot-mcp-gateway-mesh")
        registry_url = request.get("registry_url", "localhost:5000")
        upgrade_id = f"upgrade-{int(datetime.now(timezone.utc).timestamp() * 1000)}"
        upgrade_request = {
            "upgrade_id": upgrade_id,
            "service": service_name,
            "image": image_name,
            "compose_service": compose_service,
            "registry_url": registry_url,
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
        print(f"🚀 Broadcasting self-upgrade to all cells: {upgrade_id}", flush=True)
        print(f"   Service: {service_name}", flush=True)
        print(f"   Image: {registry_url}/{image_name}", flush=True)
        
        # Subscribe to results from all cells
        results_subscription = await NATS_CLIENT.subscribe(f"gaiaftcl.upgrade.result.{upgrade_id}")
        
        # Broadcast upgrade request to ALL cells
        await NATS_CLIENT.publish(
            "gaiaftcl.upgrade.request",
            json.dumps(upgrade_request).encode()
        )
        
        print(f"📡 Upgrade broadcast sent, waiting for cell responses...", flush=True)
        
        # Collect results from all cells (30 second timeout)
        cells_succeeded = 0
        cells_failed = 0
        cell_results = {}
        
        try:
            # Wait for up to 9 responses (one per cell) or 30 second timeout
            for _ in range(9):
                try:
                    msg = await asyncio.wait_for(results_subscription.next_msg(timeout=5), timeout=6)
                    result = json.loads(msg.data.decode())
                    cell_id = result.get("cell", "unknown")
                    
                    cell_results[cell_id] = result
                    if result.get("success"):
                        cells_succeeded += 1
                        print(f"  ✅ {cell_id}: Upgraded successfully", flush=True)
                    else:
                        cells_failed += 1
                        error = result.get("error", "Unknown error")
                        print(f"  ❌ {cell_id}: {error}", flush=True)
                except asyncio.TimeoutError:
                    # No more responses, break
                    break
        finally:
            await results_subscription.unsubscribe()
        
        print(f"📊 Upgrade complete: {cells_succeeded} succeeded, {cells_failed} failed", flush=True)
        
        return {
            "status": "deployed" if cells_failed == 0 else "partial",
            "upgrade_id": upgrade_id,
            "cells_succeeded": cells_succeeded,
            "cells_failed": cells_failed,
            "total_cells": 9,
            "cell_results": cell_results,
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
            
    except Exception as e:
        print(f"❌ Self-deployment trigger failed: {e}", flush=True)
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/ask")
async def ask_gaiaftcl(request: Dict[str, Any]):
    """
    Ask GaiaFTCL - Fully Dynamic Response
    She reads substrate, analyzes query, synthesizes answer.
    NO HARDCODED TEMPLATES.
    """
    try:
        query = request.get("query", "").strip()
        if not query:
            raise HTTPException(status_code=400, detail="query required")
        audience_position = request.get("audience_position")
        wallet_address = request.get("wallet_address")
        if audience_position is None and wallet_address:
            profile_resp = await HTTP_CLIENT.post(
                f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/cursor",
                json={
                    "query": "FOR p IN user_profiles FILTER p.wallet_address == @wallet LIMIT 1 RETURN p.uum_8d",
                    "bindVars": {"wallet": wallet_address}
                },
                auth=(ARANGO_USER, ARANGO_PASSWORD)
            )
            if profile_resp.status_code in [200, 201]:
                prof_results = profile_resp.json().get("result", [])
                if prof_results and prof_results[0] and len(prof_results[0]) == 8:
                    audience_position = prof_results[0]
        if audience_position is None:
            audience_position = [0.5] * 8
        print(f"🔍 Query: {query[:100]}...", flush=True)
        substrate = await query_full_substrate()
        if "error" in substrate:
            raise HTTPException(status_code=500, detail=substrate["error"])
        prior_turns = await _load_prior_turns_for_wallet(wallet_address) if wallet_address else []
        document = await generate_dynamic_response(
            query, substrate,
            audience_position=audience_position,
            wallet_address=wallet_address,
            prior_turns=prior_turns
        )
        
        return {
            "status": "complete",
            "document": document,
            "essay": document,  # Alias for shareable content
            "response": f"Response generated ({len(document)} chars)",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "raw_data": {
                "metrics": substrate.get('metrics', {}),
                "knowledge_count": len(substrate.get('knowledge', []))
            }
        }
    
    except Exception as e:
        print(f"❌ /ask error: {e}", flush=True)
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/query")
async def direct_query(request: Dict[str, Any]):
    """Execute raw AQL query on substrate"""
    query_str = request.get("query", "")
    bind_vars = request.get("bind_vars", {})
    
    resp = await HTTP_CLIENT.post(
        f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/cursor",
        json={"query": query_str, "bindVars": bind_vars},
        auth=(ARANGO_USER, ARANGO_PASSWORD)
    )
    
    if resp.status_code != 201:
        raise HTTPException(status_code=500, detail=f"Query failed: {resp.text}")
    
    return resp.json().get("result", [])


@app.get("/graph/neighborhood")
async def graph_neighborhood(
    node_id: str = Query(..., alias="id", description="Full document id, e.g. discovered_compounds/AML-CHEM-001"),
    depth: int = Query(2, ge=1, le=3),
    direction: str = Query("any", description="outbound | inbound | any"),
):
    """
    Graph traversal from a node over gaiaftcl_knowledge_graph (1..depth hops).
    """
    d = (direction or "any").lower().strip()
    if d not in ("outbound", "inbound", "any"):
        raise HTTPException(status_code=400, detail="direction must be outbound, inbound, or any")
    mode = "OUTBOUND" if d == "outbound" else "INBOUND" if d == "inbound" else "ANY"
    q = f"""
    FOR v, e, p IN 1..@depth {mode} @start GRAPH @g
      RETURN {{
        vertex: v._id,
        vertex_collection: PARSE_IDENTIFIER(v._id).collection,
        edge: e._id,
        edge_collection: e != null ? PARSE_IDENTIFIER(e._id).collection : null,
        path_edges: LENGTH(p.edges),
        relationship_type: e != null ? e.relationship_type : null
      }}
    """
    try:
        rows = await _arango_aql(q, {"start": node_id, "depth": depth, "g": GRAPH_NAME})
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    return {
        "graph": GRAPH_NAME,
        "start": node_id,
        "depth": depth,
        "direction": d,
        "count": len(rows),
        "rows": rows,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/graph/path")
async def graph_shortest_path(
    start: str = Query(..., alias="from", description="From document id"),
    to_id: str = Query(..., alias="to", description="To document id"),
):
    """Shortest path between two vertices (any direction) on gaiaftcl_knowledge_graph."""
    q = """
    FOR v, e IN ANY SHORTEST_PATH @a TO @b GRAPH @g
      RETURN {
        vertex: v._id,
        vertex_collection: PARSE_IDENTIFIER(v._id).collection,
        edge: e._id,
        edge_collection: e != null ? PARSE_IDENTIFIER(e._id).collection : null,
        relationship_type: e != null ? e.relationship_type : null
      }
    """
    try:
        rows = await _arango_aql(q, {"a": start, "b": to_id, "g": GRAPH_NAME})
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    return {
        "graph": GRAPH_NAME,
        "from": start,
        "to": to_id,
        "count": len(rows),
        "rows": rows,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/graph/stats")
async def graph_stats():
    """Edge counts per collection; approximate vertex and edge totals for the knowledge graph."""
    parts: List[str] = []
    for name in GRAPH_EDGE_COLLECTIONS:
        parts.append(f'"{name}": LENGTH({name})')
    edge_q = "RETURN {" + ", ".join(parts) + "}"
    try:
        edge_counts_list = await _arango_aql(edge_q)
        edge_counts = edge_counts_list[0] if edge_counts_list else {}
    except HTTPException:
        edge_counts = {"error": "edge LENGTH query failed (collections or graph missing?)"}
    except Exception as e:
        edge_counts = {"error": str(e)}

    vert_q = """
    RETURN {
      discovery_domain: LENGTH(discovery_domain),
      truth_envelopes: LENGTH(truth_envelopes),
      mcp_claims: LENGTH(mcp_claims),
      game_closure_events: LENGTH(game_closure_events)
    }
    """
    try:
        vrows = await _arango_aql(vert_q)
        vertices: Dict[str, Any] = dict(vrows[0]) if vrows and isinstance(vrows[0], dict) else {}
    except Exception:
        vertices = {}

    disc_names = await _arango_aql(
        """
        FOR c IN COLLECTIONS()
          FILTER c.type == 2 AND LIKE(c.name, "discovered_%", true)
          SORT c.name
          RETURN c.name
        """
    )
    discovered_total = 0
    disc_breakdown: Dict[str, int] = {}
    if isinstance(disc_names, list):
        for cn in disc_names:
            if not isinstance(cn, str):
                continue
            try:
                nrows = await _arango_aql(f"RETURN LENGTH({cn})")
                n = int(nrows[0]) if nrows else 0
                disc_breakdown[cn] = n
                discovered_total += n
            except Exception:
                disc_breakdown[cn] = -1

    vertices["discovered_by_collection"] = disc_breakdown
    vertices["discovered_vertices"] = discovered_total

    total_edges = 0
    if isinstance(edge_counts, dict) and "error" not in edge_counts:
        for _k, v in edge_counts.items():
            if isinstance(v, int):
                total_edges += v

    approx_vertices = discovered_total
    if isinstance(vertices, dict):
        approx_vertices += int(vertices.get("truth_envelopes") or 0)
        approx_vertices += int(vertices.get("mcp_claims") or 0)
        approx_vertices += int(vertices.get("game_closure_events") or 0)
        approx_vertices += int(vertices.get("discovery_domain") or 0)

    return {
        "graph": GRAPH_NAME,
        "edge_counts": edge_counts,
        "vertex_counts": vertices,
        "total_edges": total_edges,
        "approx_total_vertices_substrate": approx_vertices,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/envelopes/recent")
async def recent_envelopes():
    """Get recent truth envelopes"""
    query = """
    FOR e IN truth_envelopes
    SORT e.created_at DESC
    LIMIT 100
    RETURN e
    """
    
    resp = await HTTP_CLIENT.post(
        f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/cursor",
        json={"query": query},
        auth=(ARANGO_USER, ARANGO_PASSWORD)
    )
    
    if resp.status_code != 201:
        raise HTTPException(status_code=500, detail="Query failed")
    
    return resp.json().get("result", [])


@app.get("/state")
async def get_state():
    """Get GaiaFTCL system state"""
    substrate = await query_full_substrate()
    return substrate


@app.post("/project")
async def project_envelope_to_language(request: Dict[str, Any]):
    """
    Project truth envelope STATE to surface language.
    CONSTITUTIONAL: Language is NEVER stored, only projected at query time.
    
    Request: { "wallet_address": "0xABC...", "audience_position": [f64; 8] }
    Response: { "language": "...", "manifold_position": [...], "lifecycle_state": "..." }
    """
    try:
        wallet_address = request.get("wallet_address", "").strip()
        audience_position = request.get("audience_position")
        
        if not wallet_address:
            raise HTTPException(status_code=400, detail="wallet_address required")
        
        # When audience_position not provided, lookup from user_profiles (wallet identity)
        if audience_position is None:
            profile_resp = await HTTP_CLIENT.post(
                f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/cursor",
                json={
                    "query": """
                        FOR p IN user_profiles
                        FILTER p.wallet_address == @wallet
                        LIMIT 1
                        RETURN p.uum_8d
                    """,
                    "bindVars": {"wallet": wallet_address}
                },
                auth=(ARANGO_USER, ARANGO_PASSWORD)
            )
            if profile_resp.status_code in [200, 201]:
                prof_results = profile_resp.json().get("result", [])
                if prof_results and prof_results[0] and len(prof_results[0]) == 8:
                    audience_position = prof_results[0]
            if audience_position is None:
                # First contact: create profile with default uum_8d
                audience_position = [0.5] * 8
                profile_key = f"wallet-{wallet_address.replace('0x', '')[:24]}"
                create_resp = await HTTP_CLIENT.post(
                    f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/document/user_profiles",
                    json={
                        "_key": profile_key,
                        "wallet_address": wallet_address,
                        "uum_8d": audience_position,
                        "created_at": datetime.now(timezone.utc).isoformat(),
                        "role": "user",
                    },
                    auth=(ARANGO_USER, ARANGO_PASSWORD)
                )
                if create_resp.status_code in [201, 202]:
                    print(f"   📝 Created wallet profile: {wallet_address[:12]}...", flush=True)
        
        if len(audience_position) != 8:
            raise HTTPException(status_code=400, detail="audience_position must be 8D vector")
        
        print(f"🎯 Projecting envelope for wallet: {wallet_address[:12]}...", flush=True)
        
        # Query latest envelope for this wallet
        query_aql = {
            "query": """
            FOR e IN truth_envelopes
            FILTER e.wallet_address == @wallet
            SORT e.created_at DESC
            LIMIT 1
            RETURN e
            """,
            "bindVars": {"wallet": wallet_address}
        }
        
        resp = await HTTP_CLIENT.post(
            f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/cursor",
            json=query_aql,
            auth=(ARANGO_USER, ARANGO_PASSWORD)
        )
        
        if resp.status_code not in [200, 201]:
            raise HTTPException(status_code=500, detail="Failed to query envelope")
        
        results = resp.json().get("result", [])
        if not results:
            raise HTTPException(status_code=404, detail="No envelope found for wallet")
        
        envelope = results[0]
        
        # Extract state
        manifold_position = envelope.get("manifold_position")
        discovery_refs = envelope.get("discovery_refs", [])
        lifecycle_state = envelope.get("lifecycle_state", "UNKNOWN")
        
        if not manifold_position:
            raise HTTPException(status_code=500, detail="Envelope missing manifold_position (old format)")
        
        print(f"   📍 Manifold position: {manifold_position[:3]}...", flush=True)
        print(f"   🔗 Discovery refs: {len(discovery_refs)}", flush=True)
        
        # Call Rust projection layer (gaiaos_mcp_server POST /project)
        projection_payload = {
            "manifold_position": manifold_position,
            "discovery_refs": discovery_refs,
            "audience_position": audience_position,
            "arango_url": ARANGO_URL,
            "arango_db": ARANGO_DB
        }
        
        try:
            proj_resp = await HTTP_CLIENT.post(
                f"{PROJECTION_URL}/project",
                json=projection_payload,
                timeout=30.0
            )
            if proj_resp.status_code == 200:
                proj_data = proj_resp.json()
                projected_language = proj_data.get("language", "")
            else:
                projected_language = f"[Projection failed: {proj_resp.status_code}] {proj_resp.text[:200]}"
        except Exception as e:
            print(f"   ⚠️ Projection call failed: {e}", flush=True)
            projected_language = f"[Projection unavailable: {e}] Manifold: {manifold_position[:3]}... Lifecycle: {lifecycle_state}"
        
        return {
            "status": "projected",
            "language": projected_language,
            "manifold_position": manifold_position,
            "lifecycle_state": lifecycle_state,
            "discovery_count": len(discovery_refs),
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
    
    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ /project error: {e}", flush=True)
        raise HTTPException(status_code=500, detail=str(e))


def _eth_addr_norm(addr: str) -> str:
    a = (addr or "").strip().lower()
    if not a.startswith("0x"):
        a = "0x" + a
    return a


def _eth_tx_hash_norm(h: str) -> str:
    x = (h or "").strip().lower()
    if x.startswith("0x"):
        return x
    return "0x" + x


@app.post("/license/activate")
async def license_activate(payload: Dict[str, Any]):
    """
    Verify payment tx (eth_getTransactionReceipt), then write entropy_licenses + envelope_ledger.
    Returns 503 if ETH_RPC_URL / ENTROPY_LICENSE_TREASURY unset — no simulated activation.
    """
    wallet = str(payload.get("wallet_address") or "").strip()
    discovery_id = str(payload.get("discovery_id") or "").strip()
    tx_hash = str(payload.get("transaction_hash") or "").strip()
    collection = str(payload.get("discovery_collection") or "discovered_compounds").strip()
    doc_id_full = str(payload.get("discovery_document_id") or "").strip()

    if not wallet or not discovery_id or not tx_hash:
        raise HTTPException(
            status_code=400,
            detail="wallet_address, discovery_id, transaction_hash required",
        )

    eth_rpc = os.getenv("ETH_RPC_URL", "").strip()
    treasury = os.getenv("ENTROPY_LICENSE_TREASURY", "").strip()
    if not eth_rpc or not treasury:
        raise HTTPException(
            status_code=503,
            detail=(
                "ETH_RPC_URL and ENTROPY_LICENSE_TREASURY must be set for verified activation; "
                "refusing simulated success"
            ),
        )

    txh = _eth_tx_hash_norm(tx_hash)
    treasury_n = _eth_addr_norm(treasury)

    rpc_receipt = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "eth_getTransactionReceipt",
        "params": [txh],
    }
    try:
        rr = await HTTP_CLIENT.post(eth_rpc, json=rpc_receipt, timeout=60.0)
        rr.raise_for_status()
        rj = rr.json()
        if rj.get("error"):
            raise HTTPException(status_code=502, detail=f"rpc_error: {rj.get('error')}")
        receipt = rj.get("result")
        if not receipt:
            raise HTTPException(
                status_code=400,
                detail="transaction receipt not found (pending or invalid hash)",
            )
        if (receipt.get("status") or "") != "0x1":
            raise HTTPException(status_code=400, detail="transaction not successful on-chain")
        to_raw = receipt.get("to") or ""
        if _eth_addr_norm(to_raw) != treasury_n:
            raise HTTPException(
                status_code=400,
                detail="transaction recipient does not match ENTROPY_LICENSE_TREASURY",
            )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"chain_verify_failed: {e!s}")

    min_wei_s = os.getenv("ENTROPY_LICENSE_MIN_WEI", "").strip()
    if min_wei_s:
        rpc_tx = {
            "jsonrpc": "2.0",
            "id": 2,
            "method": "eth_getTransactionByHash",
            "params": [txh],
        }
        tr = await HTTP_CLIENT.post(eth_rpc, json=rpc_tx, timeout=60.0)
        tr.raise_for_status()
        tj = tr.json()
        if tj.get("error"):
            raise HTTPException(status_code=502, detail=f"rpc_error: {tj.get('error')}")
        tx = tj.get("result")
        if not tx:
            raise HTTPException(status_code=400, detail="transaction not found")
        value_hex = tx.get("value") or "0x0"
        try:
            value_wei = int(value_hex, 16)
            min_wei = int(min_wei_s, 10)
        except ValueError:
            raise HTTPException(status_code=400, detail="invalid ENTROPY_LICENSE_MIN_WEI or tx value")
        if value_wei < min_wei:
            raise HTTPException(status_code=400, detail="transaction value below ENTROPY_LICENSE_MIN_WEI")

    arango_doc_id = doc_id_full if doc_id_full else f"{collection}/{discovery_id}"
    dq = await HTTP_CLIENT.post(
        f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/cursor",
        json={"query": "RETURN DOCUMENT(@id)", "bindVars": {"id": arango_doc_id}},
        auth=(ARANGO_USER, ARANGO_PASSWORD),
    )
    if dq.status_code != 200:
        raise HTTPException(status_code=503, detail=f"substrate read failed: {dq.text[:200]}")
    drows = dq.json().get("result") or []
    if not drows or drows[0] is None:
        raise HTTPException(status_code=400, detail=f"discovery document not found: {arango_doc_id}")

    lic_coll = os.getenv("ENTROPY_LICENSES_COLLECTION", "entropy_licenses")
    ex_q = await HTTP_CLIENT.post(
        f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/cursor",
        json={
            "query": (
                f"FOR l IN {lic_coll} "
                "FILTER LOWER(l.wallet_address) == LOWER(@w) AND l.discovery_id == @d "
                'AND l.license_status == "ACTIVE" LIMIT 1 RETURN l'
            ),
            "bindVars": {"w": wallet, "d": discovery_id},
        },
        auth=(ARANGO_USER, ARANGO_PASSWORD),
    )
    if ex_q.status_code == 200:
        ex = ex_q.json().get("result") or []
        if ex:
            return {
                "status": "already_active",
                "wallet_address": wallet,
                "discovery_id": discovery_id,
                "transaction_hash": txh,
            }

    safe_key = re.sub(r"[^a-zA-Z0-9_-]", "_", f"{wallet[:24]}_{discovery_id}_{txh[:18]}")
    safe_key = safe_key[:250]

    iso = datetime.now(timezone.utc).isoformat()
    lic_doc: Dict[str, Any] = {
        "_key": safe_key,
        "wallet_address": wallet,
        "discovery_id": discovery_id,
        "discovery_collection": collection,
        "discovery_document_id": arango_doc_id,
        "transaction_hash": txh,
        "license_status": "ACTIVE",
        "activated_at": iso,
    }
    lr = await HTTP_CLIENT.post(
        f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/document/{lic_coll}",
        json=lic_doc,
        auth=(ARANGO_USER, ARANGO_PASSWORD),
        params={"returnNew": "true"},
    )
    if lr.status_code not in (200, 201, 202):
        if lr.status_code == 404:
            raise HTTPException(status_code=503, detail=f"Arango collection missing: {lic_coll}")
        raise HTTPException(status_code=503, detail=f"entropy_licenses write failed: {lr.text[:300]}")

    ledger_coll = os.getenv("ENVELOPE_LEDGER_COLLECTION", "envelope_ledger")
    ledger_doc: Dict[str, Any] = {
        "kind": "CALORIE",
        "wallet_address": wallet,
        "discovery_id": discovery_id,
        "transaction_hash": txh,
        "source": "entropy_license_activation",
        "timestamp": iso,
        "entropy_license_key": safe_key,
    }
    er = await HTTP_CLIENT.post(
        f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/document/{ledger_coll}",
        json=ledger_doc,
        auth=(ARANGO_USER, ARANGO_PASSWORD),
        params={"returnNew": "true"},
    )
    if er.status_code not in (200, 201, 202):
        if er.status_code == 404:
            raise HTTPException(
                status_code=503,
                detail=(
                    f"entropy_licenses written but envelope_ledger collection missing: {ledger_coll}"
                ),
            )
        raise HTTPException(status_code=503, detail=f"envelope_ledger write failed: {er.text[:300]}")

    return {
        "status": "activated",
        "wallet_address": wallet,
        "discovery_id": discovery_id,
        "transaction_hash": txh,
        "entropy_license": lic_doc,
        "envelope_ledger": ledger_doc,
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8803)
