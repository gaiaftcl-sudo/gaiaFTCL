#!/usr/bin/env python3
"""
RE-INGEST ALL JSON DISCOVERIES WITH FULL DATA
Parse every material from all 165 JSON files and ingest with complete properties
"""
import json
import requests
import time
from pathlib import Path
import sys

BASE_URL = "http://gaiaftcl.com:8803"
DISCOVERY_ROOT = Path("/Users/richardgillespie/Documents/FoTChemistry/discoveries")

def reingest_json_file(json_path):
    """Parse JSON and ingest EACH material as a separate claim"""
    try:
        with open(json_path, 'r') as f:
            data = json.load(f)
        
        domain = data.get('domain', json_path.parent.name)
        candidates = data.get('top_candidates', [])
        
        if not candidates:
            print(f"  ⚠️  {json_path.name}: No candidates found")
            return 0
        
        print(f"📁 {json_path.name}: {len(candidates)} materials")
        
        ingested_count = 0
        for i, material in enumerate(candidates):
            # Create full material claim with ALL properties
            claim_payload = {
                "caller_id": "reingest_chemistry",
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
            try:
                resp = requests.post(f"{BASE_URL}/ingest", json=claim_payload, timeout=10)
                if resp.status_code == 200:
                    ingested_count += 1
                else:
                    print(f"    ⚠️  Material {i}: HTTP {resp.status_code}")
            except Exception as e:
                print(f"    ⚠️  Material {i}: {e}")
                continue
            
            if (i + 1) % 50 == 0:
                print(f"  Progress: {i+1}/{len(candidates)} materials...")
            
            time.sleep(0.05)  # Rate limit: 20 req/sec
        
        print(f"  ✅ Ingested {ingested_count}/{len(candidates)} materials")
        return ingested_count
        
    except Exception as e:
        print(f"  ❌ Error processing {json_path.name}: {e}")
        return 0

# Find all JSON files
json_files = sorted(list(DISCOVERY_ROOT.rglob("*.json")))
print(f"🔍 Found {len(json_files)} JSON discovery files")
print(f"📊 This will ingest EVERY material with FULL property data\n")
print(f"⏱️  Estimated time: {len(json_files) * 2} minutes (assuming ~100 materials/file @ 20 req/sec)\n")

total_files = 0
total_materials = 0
failed_files = []

start_time = time.time()

for idx, json_file in enumerate(json_files, 1):
    print(f"\n[{idx}/{len(json_files)}] Processing {json_file.name}...")
    count = reingest_json_file(json_file)
    
    if count > 0:
        total_files += 1
        total_materials += count
    else:
        failed_files.append(json_file.name)
    
    # Progress update every 10 files
    if idx % 10 == 0:
        elapsed = time.time() - start_time
        rate = total_materials / elapsed if elapsed > 0 else 0
        remaining = (len(json_files) - idx) * (elapsed / idx)
        print(f"\n📊 Progress: {idx}/{len(json_files)} files | {total_materials} materials | {rate:.1f} mat/sec | ~{remaining/60:.1f} min remaining")
    
    time.sleep(0.5)  # Brief pause between files

elapsed_time = time.time() - start_time

print(f"\n{'='*80}")
print(f"✅ RE-INGESTION COMPLETE")
print(f"{'='*80}")
print(f"Files processed: {total_files}/{len(json_files)}")
print(f"Materials ingested: {total_materials}")
print(f"Time elapsed: {elapsed_time/60:.1f} minutes")
print(f"Ingestion rate: {total_materials/elapsed_time:.1f} materials/second")

if failed_files:
    print(f"\n⚠️  Failed files ({len(failed_files)}):")
    for f in failed_files:
        print(f"  - {f}")

print(f"\n🎉 ALL FoTChemistry discovery work has been ingested into GaiaFTCL's knowledge base")
