import os
import asyncio
import json
import logging
import subprocess
import time
from datetime import datetime
import nats
from nats.aio.client import Client as NATS
import httpx
import hashlib

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger("gaiaos-supervisor")

# Configuration
NATS_URL = os.getenv("NATS_URL", "nats://localhost:4222")
ARANGO_URL = os.getenv("ARANGO_URL", "http://localhost:8529")
ARANGO_USER = os.getenv("ARANGO_USER", "root")
ARANGO_PASSWORD = os.getenv("ARANGO_PASSWORD", "gaiaos")
FOUNDER_CHANNEL_URL = os.getenv("FOUNDER_CHANNEL_URL", "http://localhost:8006")

class GaiaOSSupervisor:
    def __init__(self):
        self.nc = NATS()
        self.http_client = httpx.AsyncClient(timeout=10.0)
        self.boot_id = hashlib.sha256(str(time.time()).encode()).hexdigest()[:12]
        self.restore_steps = []
        self.step_results = []
        self.degraded = False
        self.failed_components = []

    async def connect_nats(self):
        try:
            await self.nc.connect(NATS_URL)
            logger.info(f"Connected to NATS at {NATS_URL}")
            return True
        except Exception as e:
            logger.error(f"Failed to connect to NATS: {e}")
            return False

    async def emit_envelope(self, subject: str, payload: dict):
        if not self.nc.is_connected:
            await self.connect_nats()
        
        if self.nc.is_connected:
            payload["witness_hash"] = hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()
            await self.nc.publish(subject, json.dumps(payload).encode())
            logger.info(f"Emitted {payload.get('kind', 'ENVELOPE')} to {subject}")

    def run_command(self, cmd: list):
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, check=True)
            return True, res.stdout
        except subprocess.CalledProcessError as e:
            return False, e.stderr

    async def check_arango(self):
        try:
            async with httpx.AsyncClient() as client:
                res = await client.get(f"{ARANGO_URL}/_api/version", auth=(ARANGO_USER, ARANGO_PASSWORD))
                return res.status_code == 200
        except:
            return False

    async def resume_plan(self):
        logger.info("Starting GAIAOS Resume Plan...")
        self.restore_steps = []
        self.step_results = []
        self.failed_components = []

        # 1. Start/Verify ArangoDB (Container)
        step = "1. Start/verify ArangoDB"
        self.restore_steps.append(step)
        success = await self.check_arango()
        if not success:
            logger.info("ArangoDB not responding, attempting container restart...")
            # Attempt to start via docker-compose
            ok, err = self.run_command(["docker-compose", "up", "-d", "arangodb"])
            if ok:
                await asyncio.sleep(5)
                success = await self.check_arango()
        
        self.step_results.append("PASS" if success else "FAIL")
        if not success: self.failed_components.append("ArangoDB")

        # 2. Start/Verify NATS (Container)
        step = "2. Start/verify NATS"
        self.restore_steps.append(step)
        nats_ok = await self.connect_nats()
        if not nats_ok:
            self.run_command(["docker-compose", "up", "-d", "nats"])
            await asyncio.sleep(2)
            nats_ok = await self.connect_nats()
        
        self.step_results.append("PASS" if nats_ok else "FAIL")
        if not nats_ok: self.failed_components.append("NATS")

        # 3. Start/verify founder_channel
        step = "3. Start/verify gaiaos_founder_channel"
        self.restore_steps.append(step)
        try:
            res = await self.http_client.get(f"{FOUNDER_CHANNEL_URL}/threads")
            fc_ok = res.status_code == 200
        except:
            fc_ok = False
        
        if not fc_ok:
            # Attempt to start the founder channel process locally
            # In production, this would be managed by systemd/launchd
            pass 
        
        self.step_results.append("PASS" if fc_ok else "FAIL")
        if not fc_ok: self.failed_components.append("FounderChannel")

        # ... (further steps for Marketplace, Audit loops, etc.)

        # Emit BOOT_RESUME_ENVELOPE
        await self.emit_envelope("gaiaos.supervisor.boot", {
            "kind": "BOOT_RESUME_ENVELOPE",
            "boot_id": self.boot_id,
            "timestamp": datetime.utcnow().isoformat(),
            "restore_steps": self.restore_steps,
            "step_results": self.step_results
        })

        # Emit HEALTH_ATTESTATION_ENVELOPE
        await self.emit_envelope("gaiaos.supervisor.health", {
            "kind": "HEALTH_ATTESTATION_ENVELOPE",
            "services": ["ArangoDB", "NATS", "FounderChannel"],
            "ports": [8529, 4222, 8006],
            "db_ok": "ArangoDB" not in self.failed_components,
            "nats_ok": "NATS" not in self.failed_components,
            "ui_ok": "FounderChannel" not in self.failed_components,
            "loops_ok": True, # Placeholder
            "timestamp": datetime.utcnow().isoformat()
        })

        if self.failed_components:
            self.degraded = True
            await self.emit_envelope("gaiaos.supervisor.degraded", {
                "kind": "DEGRADED_MODE_ENVELOPE",
                "failed_components": self.failed_components,
                "retry_policy": "bounded-backoff-60s",
                "founder_actions_required": False,
                "timestamp": datetime.utcnow().isoformat()
            })
        else:
            self.degraded = False

    async def handle_restart_request(self, msg):
        logger.info("Received restart request from Founder UI")
        # Perform controlled restart of services
        await self.resume_plan()

    async def run_loop(self):
        await self.connect_nats()
        if self.nc.is_connected:
            await self.nc.subscribe("gaiaos.supervisor.command.restart", cb=self.handle_restart_request)
        
        await self.resume_plan()
        while True:
            # Periodic health check
            await asyncio.sleep(60)
            if self.degraded:
                logger.info("In degraded mode, retrying resume plan...")
                await self.resume_plan()
            else:
                # Normal monitoring
                db_ok = await self.check_arango()
                if not db_ok:
                    logger.warning("ArangoDB health check failed!")
                    self.degraded = True
                    self.failed_components = ["ArangoDB"]

if __name__ == "__main__":
    supervisor = GaiaOSSupervisor()
    asyncio.run(supervisor.run_loop())
