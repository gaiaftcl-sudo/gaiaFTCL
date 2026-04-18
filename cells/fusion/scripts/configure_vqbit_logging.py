#!/usr/bin/env python3
"""
Configure automatic vQbit logging for human-cleared blockers
Seals all blocker clearances to ArangoDB interaction_logs collection
"""

import os
import sys
from datetime import datetime
from arango import ArangoClient

# ArangoDB connection
ARANGO_URL = os.getenv('ARANGO_URL', 'http://77.42.85.60:8529')
ARANGO_DB = os.getenv('ARANGO_DB', 'gaiaos')
ARANGO_PASSWORD = os.getenv('ARANGO_PASSWORD', 'gaiaftcl2026')

def setup_interaction_logs_collection():
    """Create and configure interaction_logs collection"""
    client = ArangoClient(hosts=ARANGO_URL)
    sys_db = client.db('_system', username='root', password=ARANGO_PASSWORD)
    
    # Create database if not exists
    if not sys_db.has_database(ARANGO_DB):
        sys_db.create_database(ARANGO_DB)
    
    db = client.db(ARANGO_DB, username='root', password=ARANGO_PASSWORD)
    
    # Create collection if not exists
    if not db.has_collection('interaction_logs'):
        collection = db.create_collection('interaction_logs')
        print("✅ Created interaction_logs collection")
    else:
        collection = db.collection('interaction_logs')
        print("✅ interaction_logs collection already exists")
    
    # Add indexes
    if not collection.has_hash_index(['blocker_type']):
        collection.add_hash_index(fields=['blocker_type'], unique=False)
        print("✅ Added blocker_type index")
    
    if not collection.has_hash_index(['timestamp']):
        collection.add_hash_index(fields=['timestamp'], unique=False)
        print("✅ Added timestamp index")
    
    if not collection.has_hash_index(['workflow_context']):
        collection.add_hash_index(fields=['workflow_context'], unique=False)
        print("✅ Added workflow_context index")
    
    return collection

def seal_blocker_clearance(blocker_data):
    """
    Seal a blocker clearance to ArangoDB
    
    Args:
        blocker_data: dict with keys:
            - blocker_type: Identity/Firewall/Physical
            - vqbit_vector: Specific classification
            - resolution_status: cleared/failed/refused
            - workflow_context: What workflow was affected
            - game_step: Current game step
            - s4_action: Action Cell-Operator performed
            - c4_expectation: Expected outcome
            - evidence_hash: Hash of screenshots/logs
            - duration_ms: Time to clear blocker
    """
    client = ArangoClient(hosts=ARANGO_URL)
    db = client.db(ARANGO_DB, username='root', password=ARANGO_PASSWORD)
    collection = db.collection('interaction_logs')
    
    document = {
        "_key": f"blocker_{int(datetime.utcnow().timestamp() * 1000)}",
        "timestamp": datetime.utcnow().isoformat(),
        "blocker_type": blocker_data.get('blocker_type'),
        "vqbit_vector": blocker_data.get('vqbit_vector'),
        "resolution_status": blocker_data.get('resolution_status', 'cleared'),
        "workflow_context": blocker_data.get('workflow_context'),
        "game_step": blocker_data.get('game_step'),
        "s4_action": blocker_data.get('s4_action'),
        "c4_expectation": blocker_data.get('c4_expectation'),
        "evidence_hash": blocker_data.get('evidence_hash'),
        "duration_ms": blocker_data.get('duration_ms', 0),
        "cell_operator": "Hunter-01"
    }
    
    result = collection.insert(document)
    print(f"✅ vQbit sealed: {result['_key']}")
    return result

if __name__ == "__main__":
    print("🔧 Configuring vQbit logging system...")
    collection = setup_interaction_logs_collection()
    
    # Test seal
    test_blocker = {
        "blocker_type": "Identity",
        "vqbit_vector": "Test Authentication",
        "resolution_status": "cleared",
        "workflow_context": "vQbit Logging Configuration",
        "game_step": "System Setup",
        "s4_action": "Configuration script executed",
        "c4_expectation": "interaction_logs collection created and indexed",
        "evidence_hash": "sha256:test",
        "duration_ms": 1000
    }
    
    seal_blocker_clearance(test_blocker)
    print("\n✅ vQbit logging system configured successfully")
    print(f"📊 Collection: interaction_logs")
    print(f"📍 Database: {ARANGO_DB}")
    print(f"🔗 URL: {ARANGO_URL}")
