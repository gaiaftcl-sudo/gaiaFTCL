"""
Reverse proxy in front of fot-mcp-gateway-mesh.
- GET /health: local gate liveness (no wallet, no upstream call).
- All other paths: X-Gaiaftcl-Internal-Key == GAIAFTCL_INTERNAL_SERVICE_KEY, OR
  UUM-8D wallet headers with valid signature and address in authorized_wallets.
"""

from __future__ import annotations

import os

import httpx
from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse

from wallet_verify import is_valid_wallet_address, verify_signature

try:
    from license_check import entropy_license_response, license_enabled
except ImportError:
    entropy_license_response = None  # type: ignore[misc, assignment]
    license_enabled = lambda: False  # type: ignore[misc, assignment]

UPSTREAM = os.environ.get("UPSTREAM_GATEWAY_URL", "http://fot-mcp-gateway-mesh:8803").rstrip("/")
GRAPH_FOLLOW = os.environ.get("MESH_GRAPH_FOLLOW_URL", "").strip().rstrip("/")
INTERNAL_KEY = os.environ.get("GAIAFTCL_INTERNAL_SERVICE_KEY", "").strip()
ARANGO_URL = os.environ.get("ARANGO_URL", "http://gaiaftcl-arangodb:8529").rstrip("/")
ARANGO_DB = os.environ.get("ARANGO_DB", "gaiaos")
ARANGO_USER = os.environ.get("ARANGO_USER", "root")
ARANGO_PASSWORD = os.environ.get("ARANGO_PASSWORD", "gaiaftcl2026")
AUTH_COLLECTION = os.environ.get("AUTHORIZED_WALLETS_COLLECTION", "authorized_wallets")
MAX_AGE = int(os.environ.get("WALLET_SIG_MAX_AGE_SECONDS", "300"))

HOP_BY_HOP: frozenset[str] = frozenset(
    {
        "connection",
        "keep-alive",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailers",
        "transfer-encoding",
        "upgrade",
        "host",
        "content-length",
    }
)

app = FastAPI(title="gaiaftcl-wallet-gate")
_upstream: httpx.AsyncClient | None = None
_graph_follow: httpx.AsyncClient | None = None
_arango: httpx.AsyncClient | None = None


@app.on_event("startup")
async def _startup() -> None:
    global _upstream, _graph_follow, _arango
    _upstream = httpx.AsyncClient(base_url=UPSTREAM, timeout=httpx.Timeout(300.0))
    _graph_follow = (
        httpx.AsyncClient(base_url=GRAPH_FOLLOW, timeout=httpx.Timeout(300.0)) if GRAPH_FOLLOW else None
    )
    _arango = httpx.AsyncClient(timeout=httpx.Timeout(30.0))


@app.on_event("shutdown")
async def _shutdown() -> None:
    if _upstream:
        await _upstream.aclose()
    if _graph_follow:
        await _graph_follow.aclose()
    if _arango:
        await _arango.aclose()


def _forward_headers(request: Request) -> dict[str, str]:
    out: dict[str, str] = {}
    for k, v in request.headers.items():
        if k.lower() in HOP_BY_HOP:
            continue
        out[k] = v
    return out


async def _wallet_authorized(address: str) -> bool:
    if not _arango:
        return False
    aql = (
        f"FOR w IN {AUTH_COLLECTION} "
        "FILTER LOWER(w.address) == LOWER(@addr) "
        "AND (w.active == true OR !HAS(w, \"active\")) "
        "LIMIT 1 RETURN 1"
    )
    try:
        r = await _arango.post(
            f"{ARANGO_URL}/_db/{ARANGO_DB}/_api/cursor",
            json={"query": aql, "bindVars": {"addr": address}},
            auth=(ARANGO_USER, ARANGO_PASSWORD),
        )
        if r.status_code != 200:
            return False
        data = r.json()
        return bool(data.get("result"))
    except Exception:
        return False


async def _require_auth(request: Request) -> JSONResponse | None:
    if INTERNAL_KEY:
        got = request.headers.get("x-gaiaftcl-internal-key", "")
        if got == INTERNAL_KEY:
            return None

    addr = (
        request.headers.get("x-wallet-address")
        or request.headers.get("x-gaiaftcl-wallet-address")
        or ""
    ).strip()
    sig = (request.headers.get("x-gaiaftcl-signature") or request.headers.get("x-signature") or "").strip()
    ts_raw = request.headers.get("x-gaiaftcl-timestamp") or request.headers.get("x-timestamp") or ""
    msg = request.headers.get("x-gaiaftcl-auth-message") or request.headers.get("x-auth-message") or "gateway"

    if not addr or not sig or not ts_raw:
        return JSONResponse(
            status_code=400,
            content={
                "error": "missing_wallet_proof",
                "detail": "Provide X-Gaiaftcl-Internal-Key or wallet headers: "
                "X-Wallet-Address, X-Gaiaftcl-Signature, X-Gaiaftcl-Timestamp, "
                "optional X-Gaiaftcl-Auth-Message",
            },
        )
    if not is_valid_wallet_address(addr):
        return JSONResponse(status_code=400, content={"error": "invalid_wallet_address"})
    try:
        ts = int(ts_raw)
    except ValueError:
        return JSONResponse(status_code=400, content={"error": "invalid_timestamp"})

    ok, err = verify_signature(addr, msg, sig, ts, max_age_seconds=MAX_AGE)
    if not ok:
        return JSONResponse(status_code=400, content={"error": "invalid_signature", "detail": err})

    if not await _wallet_authorized(addr):
        return JSONResponse(
            status_code=403,
            content={"error": "wallet_not_authorized", "detail": "Address not in authorized_wallets"},
        )
    return None


@app.get("/health")
async def gate_health() -> dict[str, str]:
    return {"status": "ok", "service": "gaiaftcl-wallet-gate", "upstream": UPSTREAM}


def _graph_get_public(full_path: str, method: str) -> bool:
    """Read-only graph projection; no wallet round-trip for mesh health / operators."""
    if method != "GET":
        return False
    return (
        full_path == "graph/stats"
        or full_path == "vqbit/torsion"
        or full_path.startswith("graph/neighborhood")
        or full_path.startswith("graph/path")
    )


@app.api_route("/{full_path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"])
async def proxy(full_path: str, request: Request) -> Response:
    if not _graph_get_public(full_path, request.method):
        deny = await _require_auth(request)
        if deny is not None:
            return deny

    if license_enabled() and entropy_license_response and _arango:
        waddr = (
            request.headers.get("x-wallet-address")
            or request.headers.get("x-gaiaftcl-wallet-address")
            or ""
        ).strip()
        lic = await entropy_license_response(
            _arango,
            full_path=full_path,
            query_string=str(request.url.query or ""),
            wallet_address=waddr,
        )
        if lic is not None:
            return lic

    assert _upstream is not None
    use_graph_follow = _graph_get_public(full_path, request.method) and _graph_follow is not None
    client = _graph_follow if use_graph_follow else _upstream
    path = f"/{full_path}" if full_path else "/"
    if request.url.query:
        path = f"{path}?{request.url.query}"
    body = await request.body()
    headers = _forward_headers(request)
    try:
        r = await client.request(
            request.method,
            path,
            content=body if body else None,
            headers=headers,
        )
    except httpx.RequestError as e:
        return JSONResponse(status_code=502, content={"error": "upstream_unreachable", "detail": str(e)})

    out_h = {k: v for k, v in r.headers.items() if k.lower() not in HOP_BY_HOP}
    return Response(content=r.content, status_code=r.status_code, headers=out_h)
