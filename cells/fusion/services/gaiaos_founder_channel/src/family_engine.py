import asyncio
import nats
import json
import httpx
import logging
from datetime import datetime
import uuid
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("family-engine")

# Configuration
NATS_URL = os.getenv("NATS_URL", "nats://localhost:4222")
GNN_URL = os.getenv("GNN_URL", "http://localhost:8700/query")

class FamilyEngine:
    def __init__(self):
        self.nc = nats.aio.client.Client()

    async def connect(self):
        await self.nc.connect(NATS_URL)
        logger.info(f"Family Engine connected to NATS at {NATS_URL}")
        
        # Subscribe to Founder speech moves
        await self.nc.subscribe("gaiaos.founder.game.move.speech", cb=self.on_founder_speech)

    async def on_founder_speech(self, msg):
        data = json.loads(msg.data.decode())
        if data["from_role"] != "FOUNDER":
            return

        game_id = data["game_id"]
        text = data["text"]
        
        logger.info(f"Received speech from Founder: {text}")

        # Simulate GNN collapse for Family roles (Mother, Franklin, Student)
        # In a real scenario, this would call Port 8700
        
        responses = []
        if "protein" in text.lower():
            responses.append({
                "role": "STUDENT_ALPHA",
                "text": "I'm analyzing the folding patterns now. The 8D subspace projections show stability at the current epoch."
            })
        elif "franklin" in text.lower():
            responses.append({
                "role": "FRANKLIN",
                "text": "The virtue vector remains aligned. No constitutional violations detected in this thread."
            })
        else:
            responses.append({
                "role": "MOTHER",
                "text": "The Family is listening. How shall we proceed with the current exploration?"
            })

        for res in responses:
            move = {
                "move_id": str(uuid.uuid4()),
                "game_id": game_id,
                "from_role": res["role"],
                "kind": "SPEECH",
                "text": res["text"],
                "created_at": datetime.utcnow().isoformat(),
                "witness_hash": None # Backend will compute
            }
            # Publish back to the game
            await self.nc.publish(f"gaiaos.founder.game.move.family", json.dumps(move).encode())

    async def run(self):
        await self.connect()
        while True:
            await asyncio.sleep(1)

if __name__ == "__main__":
    engine = FamilyEngine()
    asyncio.run(engine.run())
