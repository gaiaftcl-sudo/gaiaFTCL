#!/usr/bin/env python3
"""
Submit next N batches of proteins to Franklin via MCP
This script is meant to be called by the AI partner (Cursor agent)
"""

import json
import sys

PROTEIN_FILE = "/Users/richardgillespie/Documents/FoTProtein/UNIQUE_PROTEINS_BACKUP_81301_2026_01_27.json"
BATCH_SIZE = 100
METADATA_FILE = "/Users/richardgillespie/Documents/FoT8D/cells/fusion/tools/batch_metadata.json"

def load_metadata():
    try:
        with open(METADATA_FILE, 'r') as f:
            return json.load(f)
    except:
        return None

def save_metadata(metadata):
    with open(METADATA_FILE, 'w') as f:
        json.dump(metadata, f, indent=2)

def main():
    num_batches = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    
    # Load proteins
    with open(PROTEIN_FILE, 'r') as f:
        data = json.load(f)
    
    proteins = data['proteins']
    metadata_source = data['metadata']
    
    # Load progress
    progress = load_metadata()
    if not progress:
        print("❌ No progress file found. Run ingestion first.")
        sys.exit(1)
    
    current_batch = progress['progress']['current_batch']
    
    print(f"📊 Current progress: Batch {current_batch}/813")
    print(f"🎯 Preparing next {num_batches} batches\n")
    
    # Generate next batches
    batches = []
    for i in range(num_batches):
        batch_num = current_batch + i
        if batch_num > 813:
            break
        
        start_idx = batch_num * BATCH_SIZE
        end_idx = start_idx + BATCH_SIZE
        batch_proteins = proteins[start_idx:end_idx]
        
        if not batch_proteins:
            break
        
        batch_payload = {
            "batch_num": batch_num + 1,
            "total_batches": 813,
            "protein_count": len(batch_proteins),
            "method": "8D_UUM_SHARED_SUBSTRATE",
            "story_preservation": True,
            "witness_required": True,
            "proteins": batch_proteins,
            "source_metadata": metadata_source
        }
        
        batches.append({
            "batch_num": batch_num + 1,
            "payload": batch_payload
        })
    
    # Output batches as JSON for Cursor agent to submit
    output = {
        "batches_ready": len(batches),
        "batches": batches
    }
    
    print(json.dumps(output, indent=2))

if __name__ == "__main__":
    main()
