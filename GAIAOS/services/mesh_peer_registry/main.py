#!/usr/bin/env python3
"""
NAT mesh.cell.heartbeat: each cell publishes cell_id + IP every HEARTBEAT_INTERVAL_S.
Subscribes to the same subject and maintains a JSON peer list served on GET /peers.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import time
from contextlib import asynccontextmanager
from typing import Any, Dict

from nats.aio.client import Client as NATS
import uvicorn
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse, Response
from starlette.routing import Route

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

NATS_URL = os.environ.get("NATS_URL", "nats://gaiaftcl-nats:4222")
SUBJECT = os.environ.get("MESH_HEARTBEAT_SUBJECT", "mesh.cell.heartbeat")
CELL_ID = os.environ.get("CELL_ID", os.environ.get("CELL_NAME", "unknown"))
CELL_IP = os.environ.get("CELL_IP", "").strip()
HEARTBEAT_INTERVAL_S = int(os.environ.get("HEARTBEAT_INTERVAL_S", "60"))
PEER_STALE_S = int(os.environ.get("PEER_STALE_S", "300"))

_peers: Dict[str, Dict[str, Any]] = {}
_lock = asyncio.Lock()
_nc: NATS | None = None


async def _publish_loop():
    global _nc
    while True:
        try:
            if _nc and _nc.is_connected:
                payload = {
                    "cell_id": CELL_ID,
                    "ip": CELL_IP or None,
                    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                }
                await _nc.publish(SUBJECT, json.dumps(payload).encode("utf-8"))
                async with _lock:
                    now = int(time.time())
                    _peers[CELL_ID] = {
                        "cell_id": CELL_ID,
                        "ip": CELL_IP or None,
                        "last_seen_ts": payload["ts"],
                        "last_seen_unix": now,
                        "local": True,
                    }
                logger.info("heartbeat published cell_id=%s", CELL_ID)
        except Exception as e:
            logger.warning("heartbeat publish failed: %s", e)
        await asyncio.sleep(HEARTBEAT_INTERVAL_S)


async def _on_message(msg):
    try:
        data = json.loads(msg.data.decode("utf-8"))
    except Exception:
        return
    cid = str(data.get("cell_id") or data.get("cell_name") or "").strip()
    if not cid:
        return
    ip = str(data.get("ip") or data.get("cell_ip") or "").strip()
    async with _lock:
        _peers[cid] = {
            "cell_id": cid,
            "ip": ip,
            "last_seen_ts": data.get("ts"),
            "last_seen_unix": int(time.time()),
        }


async def _nats_runner():
    global _nc
    _nc = NATS()
    await _nc.connect(NATS_URL)
    logger.info("NATS connected %s", NATS_URL)
    await _nc.subscribe(SUBJECT, cb=_on_message)
    await _publish_loop()


async def _prune_loop():
    while True:
        await asyncio.sleep(30)
        now = int(time.time())
        async with _lock:
            dead = [k for k, v in _peers.items() if now - int(v.get("last_seen_unix") or 0) > PEER_STALE_S]
            for k in dead:
                del _peers[k]


@asynccontextmanager
async def lifespan(app: Starlette):
    t1 = asyncio.create_task(_nats_runner())
    t2 = asyncio.create_task(_prune_loop())
    try:
        yield
    finally:
        t1.cancel()
        t2.cancel()
        try:
            if _nc and _nc.is_connected:
                await _nc.close()
        except Exception:
            pass


async def health(_: Request) -> Response:
    return JSONResponse({"status": "ok", "service": "mesh_peer_registry", "cell_id": CELL_ID})


async def peers(_: Request) -> Response:
    async with _lock:
        out = list(_peers.values())
    return JSONResponse({"peers": out, "self": {"cell_id": CELL_ID, "ip": CELL_IP or None}})


app = Starlette(
    routes=[
        Route("/health", health, methods=["GET"]),
        Route("/peers", peers, methods=["GET"]),
    ],
    lifespan=lifespan,
)


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8821")))
