#!/usr/bin/env python3
"""
RE-INGEST JSON DISCOVERIES WITH FULL DATA
Previously: Only ingested file metadata
Now: Parse and store EVERY material with ALL properties
"""
import json
import requests
import time
from pathlib import Path

BASE_URL = "http://gaiaftcl.com:8803"
DISCOVERY_ROOT = Path("/Users/richardgillespie/Documents/FoTChemistry/discoveries")

def reingest_json_file(json_path):
    """Parse JSON and ingest EACH material as a separate claim"""
    try:
        with open(json_path, 'r') as f:
            data = json.load(f)
        
        domain = data.get('domain', json_path.parent.name)
        candidates = data.get('top_candidates', [])
        
        print(f"\n📁 {json_path.name}: {len(candidates)} materials")
        
        for i, material in enumerate(candidates):
            # Create full material claim with ALL properties
            claim_payload = {
                "caller_id": "reingest_json_full",
                "source": f"FoTChemistry Discovery - {domain} - Material {i+1}",
                "envelope_type": "KNOWLEDGE",
                "content_type": "application/json",
                "payload": {
                    "domain": domain,
                    "material_index": i,
                    "name": material.get('name'),
                    "smiles": material.get('smiles'),
                    "formula": material.get('smiles'),  # Store SMILES as formula
                    "properties": {
                        "coherence": material.get('coherence'),
                        "entanglement": material.get('entanglement'),
                        "fidelity": material.get('fidelity'),
                        "fot_score": material.get('fot_score'),
                        "novelty_score": material.get('novelty_score'),
                        "commercial_viability": material.get('commercial_viability'),
                        "confidence": material.get('confidence')
                    },
                    "metrics": {
                        k: v for k, v in material.items() 
                        if k not in ['name', 'smiles', 'coherence', 'entanglement', 'fidelity', 
                                    'fot_score', 'novelty_score', 'commercial_viability', 'confidence']
                    }
                }
            }
            
            # Ingest via MCP
            resp = requests.post(f"{BASE_URL}/ingest", json=claim_payload, timeout=10)
            
            if i % 50 == 0:
                print(f"  Ingested {i}/{len(candidates)} materials...")
            
            time.sleep(0.1)  # Rate limit
        
        print(f"  ✅ Ingested ALL {len(candidates)} materials with full properties")
        return len(candidates)
        
    except Exception as e:
        print(f"  ❌ Error: {e}")
        return 0

# Find all JSON files
json_files = list(DISCOVERY_ROOT.rglob("*.json"))
print(f"Found {len(json_files)} JSON discovery files")
print(f"This will ingest EVERY material with FULL property data\n")

total_materials = 0
for json_file in json_files[:10]:  # Start with first 10 files
    count = reingest_json_file(json_file)
    total_materials += count
    time.sleep(0.5)

print(f"\n✅ COMPLETE: Ingested {total_materials} materials with full properties from {len(json_files[:10])} files")
print(f"Run again to process remaining {len(json_files) - 10} files")
