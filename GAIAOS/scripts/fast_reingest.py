#!/usr/bin/env python3
"""Fast re-ingestion with immediate feedback"""
import json, requests, time, sys
from pathlib import Path

print("🚀 Starting FoTChemistry re-ingestion...", flush=True)

BASE_URL = "http://gaiaftcl.com:8803"
DISCOVERY_ROOT = Path("/Users/richardgillespie/Documents/FoTChemistry/discoveries")

print(f"📂 Scanning {DISCOVERY_ROOT}...", flush=True)
json_files = sorted(list(DISCOVERY_ROOT.rglob("*.json")))
print(f"✅ Found {len(json_files)} JSON files\n", flush=True)

total_materials = 0
total_ingested = 0
start_time = time.time()

for idx, json_file in enumerate(json_files, 1):
    try:
        with open(json_file, 'r') as f:
            data = json.load(f)
        
        domain = data.get('domain', json_file.parent.name)
        candidates = data.get('top_candidates', [])
        
        print(f"[{idx}/{len(json_files)}] {json_file.name}: {len(candidates)} materials", flush=True)
        
        for i, material in enumerate(candidates):
            payload = {
                "caller_id": "fast_reingest",
                "source": f"FoTChemistry - {domain} - {material.get('name', f'mat_{i}')}",
                "envelope_type": "KNOWLEDGE",
                "content_type": "application/json",
                "payload": {
                    "domain": domain,
                    "material_index": i,
                    "name": material.get('name'),
                    "smiles": material.get('smiles'),
                    "formula": material.get('smiles'),
                    "properties": {
                        k: v for k, v in material.items()
                        if k in ['coherence', 'entanglement', 'fidelity', 'fot_score', 
                                'novelty_score', 'commercial_viability', 'confidence']
                    },
                    "metrics": {
                        k: v for k, v in material.items()
                        if k not in ['name', 'smiles', 'coherence', 'entanglement', 
                                    'fidelity', 'fot_score', 'novelty_score', 
                                    'commercial_viability', 'confidence']
                    }
                }
            }
            
            try:
                resp = requests.post(f"{BASE_URL}/ingest", json=payload, timeout=5)
                if resp.status_code == 200:
                    total_ingested += 1
            except:
                pass
            
            total_materials += 1
            
            if total_materials % 100 == 0:
                elapsed = time.time() - start_time
                rate = total_materials / elapsed
                print(f"  ⚡ {total_materials} materials | {rate:.1f}/sec | {total_ingested} ingested", flush=True)
            
            time.sleep(0.03)  # ~33 req/sec
        
    except Exception as e:
        print(f"  ❌ Error: {e}", flush=True)
        continue
    
    if idx % 10 == 0:
        elapsed = time.time() - start_time
        rate = total_materials / elapsed
        remaining_files = len(json_files) - idx
        est_remaining = (remaining_files * total_materials / idx) / rate / 60
        print(f"\n📊 Progress: {idx}/{len(json_files)} files | {total_materials} materials | ~{est_remaining:.1f} min remaining\n", flush=True)

elapsed = time.time() - start_time
print(f"\n{'='*80}", flush=True)
print(f"✅ COMPLETE", flush=True)
print(f"{'='*80}", flush=True)
print(f"Files: {len(json_files)}", flush=True)
print(f"Materials: {total_materials}", flush=True)
print(f"Ingested: {total_ingested}", flush=True)
print(f"Time: {elapsed/60:.1f} minutes", flush=True)
print(f"Rate: {total_materials/elapsed:.1f} materials/sec", flush=True)
