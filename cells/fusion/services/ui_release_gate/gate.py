import asyncio
import os
import json
import nats
import logging
from datetime import datetime
import uuid

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("ui-release-gate")

ENVELOPES_DIR = "../../ftcl/ui_validation/envelopes"

class UIReleaseGate:
    def __init__(self):
        self.nc = None

    async def connect(self):
        self.nc = await nats.connect(os.getenv("NATS_URL", "nats://localhost:4222"))
        logger.info("Mother Release Gate online")
        
        await self.nc.subscribe("gaiaos.ui.validation.result", cb=self.on_validation_result)

    async def on_validation_result(self, msg):
        data = json.loads(msg.data.decode())
        surface_id = data["surface_id"]
        iq = data["iq"]
        oq = data["oq"]
        pq = data["pq"]
        
        logger.info(f"Evaluating release for {surface_id}...")
        
        # Check for DEV_TRUTH_ENVELOPE if this is an identity-affecting change
        game_truth_path = f"{ENVELOPES_DIR}/IDENTITY_RENAME_V1.truth.json"
        has_truth_envelope = os.path.exists(game_truth_path)
        
        if iq["status"] == "PASS" and oq["status"] == "PASS" and pq["status"] == "PASS":
            if surface_id == "GAIAFTCL_PORTAL_V1" and not has_truth_envelope:
                logger.error(f"❌ RELEASE BLOCKED: Missing DEV_TRUTH_ENVELOPE for {surface_id}")
                return

            logger.info(f"✅ ALL CHECKS PASS for {surface_id}. Emitting UI_RELEASE_ENVELOPE.")
            
            release_envelope = {
                "envelope_type": "UI_RELEASE",
                "release_id": str(uuid.uuid4()),
                "surface_id": surface_id,
                "iq_envelope_ref": iq["witness_hash"],
                "oq_envelope_ref": oq["witness_hash"],
                "pq_envelope_ref": pq["witness_hash"],
                "verdict": "PASS",
                "mother_signature": "SIGNED_BY_MOTHER_GATE",
                "created_at": datetime.utcnow().isoformat()
            }
            
            # Persist to disk for the UI service to pick up
            path = f"{ENVELOPES_DIR}/{surface_id}.release.json"
            with open(path, "w") as f:
                json.dump(release_envelope, f, indent=2)
            
            logger.info(f"Persisted release envelope to {path}")
            
            # Broadcast release
            await self.nc.publish("gaiaos.ui.release", json.dumps(release_envelope).encode())
        else:
            logger.error(f"❌ CHECKS FAILED for {surface_id}. Release blocked.")

async def main():
    gate = UIReleaseGate()
    await gate.connect()
    while True:
        await asyncio.sleep(1)

if __name__ == "__main__":
    asyncio.run(main())
