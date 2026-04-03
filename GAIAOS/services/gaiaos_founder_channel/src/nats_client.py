import os
import asyncio
import json
import nats
from nats.aio.client import Client as NATS
from typing import Callable, Any, Dict

class FounderNats:
    def __init__(self):
        self.url = os.getenv("NATS_URL", "nats://localhost:4222")
        self.nc = NATS()
        
    async def connect(self):
        await self.nc.connect(self.url)
        
    async def publish(self, subject: str, data: Dict[str, Any]):
        await self.nc.publish(subject, json.dumps(data).encode())
        
    async def subscribe(self, subject: str, callback: Callable):
        async def handler(msg):
            data = json.loads(msg.data.decode())
            await callback(data)
        await self.nc.subscribe(subject, cb=handler)
        
    async def close(self):
        await self.nc.close()
