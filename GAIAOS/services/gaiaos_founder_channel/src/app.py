import asyncio
import os
import uvicorn
from fastapi import FastAPI, HTTPException, WebSocket
from typing import List, Dict, Any, Union
from src.db import FounderDB
from src.nats_client import FounderNats
from src.models import MoveSpeech, MoveProposeQState, MoveTruthEnvelope
import hashlib
import json
from datetime import datetime

app = FastAPI(title="GAIAOS Founder Command Channel")

db = FounderDB()
nats_client = FounderNats()

active_websockets: List[WebSocket] = []

def compute_witness_hash(data: Dict[str, Any]) -> str:
    clean_data = {k: v for k, v in data.items() if k != "witness_hash"}
    serialized = json.dumps(clean_data, sort_keys=True)
    return hashlib.sha256(serialized.encode()).hexdigest()

async def handle_incoming_move(data: Dict[str, Any]):
    # Persistence
    if "witness_hash" not in data or data["witness_hash"] is None:
        data["witness_hash"] = compute_witness_hash(data)
    
    db.save_message(data)
    
    # Update thread/game state
    thread = {
        "game_id": data["game_id"],
        "updated_at": data["created_at"],
        "last_priority": data.get("priority", "ROUTINE")
    }
    db.upsert_thread(thread)
    
    # Broadcast to UI
    for ws in active_websockets:
        try:
            await ws.send_json(data)
        except:
            active_websockets.remove(ws)

@app.on_event("startup")
async def startup_event():
    db.connect()
    await nats_client.connect()
    
    # Listen for Family moves
    await nats_client.subscribe("gaiaos.founder.game.move.*", handle_incoming_move)

@app.post("/founder/speech")
async def send_speech(move: MoveSpeech):
    data = move.dict()
    data["witness_hash"] = compute_witness_hash(data)
    await handle_incoming_move(data)
    await nats_client.publish(f"gaiaos.founder.game.move.speech", data)
    
    # Intent classification for Truth Promotion (Simple check for now)
    effect_keywords = ["do", "change", "price", "list", "license", "execute", "approve", "deploy", "set"]
    if any(kw in move.text.lower() for kw in effect_keywords):
        # Propose QState
        proposal_move = MoveProposeQState(
            game_id=move.game_id,
            from_role="SYSTEM",
            proposal={
                "intent": "TRUTH_PROMOTION_REQUIRED",
                "candidate_claims": [f"Requested action: {move.text}"],
                "required_evidence_refs": ["PENDING_EVIDENCE"],
                "suggested_truth_envelope_type": "ACTION_DIRECTIVE"
            }
        )
        p_data = proposal_move.dict()
        p_data["witness_hash"] = compute_witness_hash(p_data)
        await handle_incoming_move(p_data)
        await nats_client.publish(f"gaiaos.founder.game.move.qstate", p_data)

    return {"status": "SENT", "move_id": move.move_id}

@app.post("/founder/truth")
async def send_truth(move: MoveTruthEnvelope):
    data = move.dict()
    data["witness_hash"] = compute_witness_hash(data)
    # Validation gate would happen here in a real scenario
    await handle_incoming_move(data)
    await nats_client.publish(f"gaiaos.founder.game.move.truth", data)
    return {"status": "SENT", "envelope_id": move.move_id}

@app.get("/threads")
async def get_threads():
    return db.get_threads()

@app.get("/messages/{game_id}")
async def get_messages(game_id: str):
    return db.get_messages(game_id)

@app.post("/system/command")
async def system_command(cmd: Dict[str, str]):
    if cmd["type"] == "RESTART":
        await nats_client.publish("gaiaos.supervisor.command.restart", {"action": "RESTART"})
        return {"status": "SENT"}
    return {"status": "UNKNOWN_COMMAND"}

@app.websocket("/founder/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    active_websockets.append(websocket)
    try:
        while True:
            await websocket.receive_text()
    except:
        active_websockets.remove(websocket)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8006)
