#!/usr/bin/env python3
"""Ingest ALL FoTChemistry discoveries into GaiaFTCL substrate"""

import json
import requests
import sys
from pathlib import Path
from time import sleep

GATEWAY_URL = "http://gaiaftcl.com:8803"
CHEMISTRY_BASE = Path("/Users/richardgillespie/Documents/FoTChemistry")
WIKI_BASE = Path("/Users/richardgillespie/Documents/FoTChemistry.wiki")

def ingest_json_discovery(filepath: Path):
    """Ingest a JSON discovery file"""
    try:
        with open(filepath, 'r') as f:
            data = json.load(f)
        
        # Extract domain from path
        domain = filepath.parent.name
        
        payload = {
            "caller_id": "ingest_all_chemistry",
            "source": f"FoTChemistry Discovery - {domain}",
            "content_type": "DISCOVERY",
            "envelope_type": "KNOWLEDGE",
            "payload": {
                "domain": domain,
                "file": filepath.name,
                "data": data
            }
        }
        
        resp = requests.post(f"{GATEWAY_URL}/ingest", json=payload, timeout=10)
        
        if resp.status_code == 200:
            claim_id = resp.json().get('claim_id')
            print(f"✅ {domain}/{filepath.name}: {claim_id}")
            return True
        else:
            print(f"❌ {filepath.name}: {resp.status_code}")
            return False
            
    except Exception as e:
        print(f"❌ {filepath.name}: {e}")
        return False

def ingest_markdown_doc(filepath: Path):
    """Ingest a markdown documentation file"""
    try:
        content = filepath.read_text()
        
        payload = {
            "caller_id": "ingest_all_chemistry",
            "source": f"FoTChemistry Documentation - {filepath.stem}",
            "content_type": "DOCUMENTATION",
            "envelope_type": "KNOWLEDGE",
            "payload": {
                "document": filepath.name,
                "content": content[:5000]  # First 5k chars
            }
        }
        
        resp = requests.post(f"{GATEWAY_URL}/ingest", json=payload, timeout=10)
        
        if resp.status_code == 200:
            claim_id = resp.json().get('claim_id')
            print(f"✅ {filepath.name}: {claim_id}")
            return True
        else:
            print(f"❌ {filepath.name}: {resp.status_code}")
            return False
            
    except Exception as e:
        print(f"❌ {filepath.name}: {e}")
        return False

def main():
    print("🔬 INGESTING ALL FOTCHEMISTRY DISCOVERIES\n")
    
    # Find all discovery JSON files
    discovery_files = list(CHEMISTRY_BASE.glob("discoveries/**/*.json"))
    print(f"📊 Found {len(discovery_files)} discovery JSON files")
    
    # Find all markdown docs
    wiki_files = list(WIKI_BASE.glob("*.md"))
    print(f"📚 Found {len(wiki_files)} wiki documentation files\n")
    
    success_count = 0
    fail_count = 0
    
    # Ingest discoveries
    print("🔬 INGESTING DISCOVERIES...")
    for i, filepath in enumerate(discovery_files, 1):
        if ingest_json_discovery(filepath):
            success_count += 1
        else:
            fail_count += 1
        
        # Rate limit: 10 per second
        if i % 10 == 0:
            print(f"  Progress: {i}/{len(discovery_files)}")
            sleep(1)
    
    print(f"\n📚 INGESTING DOCUMENTATION...")
    for filepath in wiki_files:
        if ingest_markdown_doc(filepath):
            success_count += 1
        else:
            fail_count += 1
        sleep(0.5)
    
    print(f"\n📊 FINAL RESULTS:")
    print(f"✅ Success: {success_count}")
    print(f"❌ Failed: {fail_count}")
    print(f"📈 Total: {success_count + fail_count}")
    
    return success_count

if __name__ == "__main__":
    count = main()
    sys.exit(0 if count > 0 else 1)
