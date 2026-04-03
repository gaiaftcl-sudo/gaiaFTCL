import os
import logging
from typing import Any, Dict, List, Optional
from arango import ArangoClient
from datetime import datetime

logger = logging.getLogger("founder-channel-db")

class FounderDB:
    def __init__(self):
        self.url = os.getenv("ARANGO_URL", "http://localhost:8529")
        self.db_name = os.getenv("ARANGO_DB", "gaiaos")
        self.username = os.getenv("ARANGO_USER", "root")
        self.password = os.getenv("ARANGO_PASSWORD", "gaiaos")
        
        self.client = ArangoClient(hosts=self.url)
        self.db = None
        
    def connect(self):
        sys_db = self.client.db("_system", username=self.username, password=self.password)
        if not sys_db.has_database(self.db_name):
            sys_db.create_database(self.db_name)
        
        self.db = self.client.db(self.db_name, username=self.username, password=self.password)
        self._ensure_collections()
        
    def _ensure_collections(self):
        collections = [
            "founder_threads",
            "founder_messages",
            "founder_escalations"
        ]
        for coll in collections:
            if not self.db.has_collection(coll):
                self.db.create_collection(coll)
                logger.info(f"Created collection: {coll}")
                
    def save_message(self, message: Dict[str, Any]):
        self.db.collection("founder_messages").insert(message)
        
    def get_messages(self, game_id: str) -> List[Dict[str, Any]]:
        cursor = self.db.aql.execute(
            "FOR m IN founder_messages FILTER m.game_id == @game_id SORT m.created_at ASC RETURN m",
            bind_vars={"game_id": game_id}
        )
        return [doc for doc in cursor]
    
    def get_threads(self) -> List[Dict[str, Any]]:
        cursor = self.db.aql.execute(
            "FOR t IN founder_threads SORT t.updated_at DESC RETURN t"
        )
        return [doc for doc in cursor]
    
    def upsert_thread(self, thread: Dict[str, Any]):
        game_id = thread["game_id"]
        if self.db.collection("founder_threads").has(game_id):
            self.db.collection("founder_threads").update_match({"game_id": game_id}, thread)
        else:
            thread["_key"] = game_id
            self.db.collection("founder_threads").insert(thread)

    def save_escalation(self, escalation: Dict[str, Any]):
        self.db.collection("founder_escalations").insert(escalation)
