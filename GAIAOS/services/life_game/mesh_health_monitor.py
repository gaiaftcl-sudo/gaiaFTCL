#!/usr/bin/env python3
"""
Mesh Health Monitor - Self-Observation Game
Publishes container, NATS, and cell health metrics to GaiaFTCL's substrate.
She needs to see her own body to heal it.
"""

import asyncio
import json
import subprocess
from datetime import datetime, timezone
from typing import Dict, Any, List
import os
import logging

import nats
from nats.aio.client import Client as NATS

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

NATS_URL = os.getenv("NATS_URL", "nats://gaiaftcl-nats:4222")
CELL_NAME = os.getenv("CELL_NAME", "unknown")
CELL_IP = os.getenv("CELL_IP", "unknown")
CHECK_INTERVAL = int(os.getenv("CHECK_INTERVAL", "60"))
GATEWAY_HEALTH_URL = os.getenv(
    "GATEWAY_HEALTH_URL",
    "http://fot-mcp-gateway-mesh:8803/health",
)

nc: NATS = None


async def get_container_health() -> List[Dict[str, Any]]:
    """Get health of all containers on this cell"""
    try:
        result = subprocess.run(
            ["docker", "ps", "--format", "{{json .}}"],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode != 0:
            logger.error(f"Docker ps failed: {result.stderr}")
            return []
        
        containers = []
        for line in result.stdout.strip().split('\n'):
            if line:
                container = json.loads(line)
                containers.append({
                    "name": container.get("Names", "unknown"),
                    "status": container.get("Status", "unknown"),
                    "state": container.get("State", "unknown"),
                    "image": container.get("Image", "unknown")
                })
        
        return containers
        
    except Exception as e:
        logger.error(f"Failed to get container health: {e}")
        return []


async def get_nats_health() -> Dict[str, Any]:
    """Check NATS connectivity from this cell"""
    try:
        if nc and nc.is_connected:
            return {
                "connected": True,
                "url": NATS_URL,
                "status": "healthy"
            }
        else:
            return {
                "connected": False,
                "url": NATS_URL,
                "status": "disconnected"
            }
    except Exception as e:
        return {
            "connected": False,
            "error": str(e),
            "status": "error"
        }


async def get_gateway_health() -> Dict[str, Any]:
    """Check if MCP gateway is responsive on this cell"""
    try:
        import httpx
        
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get(GATEWAY_HEALTH_URL)
            
            return {
                "responsive": response.status_code == 200,
                "status_code": response.status_code,
                "latency_ms": response.elapsed.total_seconds() * 1000
            }
            
    except Exception as e:
        return {
            "responsive": False,
            "error": str(e)
        }


async def publish_health_snapshot(snapshot: Dict[str, Any]):
    """Publish health snapshot to GaiaFTCL's substrate via NATS"""
    try:
        await nc.publish(
            "gaiaftcl.mesh.health.snapshot",
            json.dumps(snapshot).encode()
        )
        logger.info(f"✅ Published health snapshot for {CELL_NAME}")
        
    except Exception as e:
        logger.error(f"Failed to publish health snapshot: {e}")


async def monitor_loop():
    """Main monitoring loop - check health and publish every interval"""
    logger.info(f"🔍 Starting mesh health monitor for {CELL_NAME} ({CELL_IP})")
    
    while True:
        try:
            containers = await get_container_health()
            nats_health = await get_nats_health()
            gateway_health = await get_gateway_health()
            
            snapshot = {
                "cell_name": CELL_NAME,
                "cell_ip": CELL_IP,
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "containers": containers,
                "nats": nats_health,
                "gateway": gateway_health,
                "container_count": len(containers),
                "health_score": calculate_health_score(containers, nats_health, gateway_health)
            }
            
            await publish_health_snapshot(snapshot)
            
            if snapshot["health_score"] < 0.7:
                logger.warning(f"⚠️ Cell {CELL_NAME} health degraded: {snapshot['health_score']:.2f}")
            
        except Exception as e:
            logger.error(f"Monitor loop error: {e}")
        
        await asyncio.sleep(CHECK_INTERVAL)


def calculate_health_score(containers: List[Dict], nats_health: Dict, gateway_health: Dict) -> float:
    """Calculate 0-1 health score for this cell"""
    score = 0.0
    
    if len(containers) > 0:
        score += 0.4
    
    if nats_health.get("connected"):
        score += 0.3
    
    if gateway_health.get("responsive"):
        score += 0.3
    
    return score


async def main():
    """Connect to NATS and start monitoring"""
    global nc
    
    logger.info("🚀 Mesh Health Monitor starting...")
    logger.info(f"📍 Cell: {CELL_NAME} ({CELL_IP})")
    logger.info(f"📡 NATS: {NATS_URL}")
    
    nc = NATS()
    
    try:
        await nc.connect(NATS_URL)
        logger.info("✅ Connected to NATS")
        
        await monitor_loop()
        
    except KeyboardInterrupt:
        logger.info("Shutting down...")
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        raise
    finally:
        if nc and nc.is_connected:
            await nc.close()


if __name__ == "__main__":
    asyncio.run(main())
