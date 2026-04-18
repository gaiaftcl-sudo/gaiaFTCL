#!/usr/bin/env python3
"""Ingest material science documents into GaiaFTCL substrate"""

import json
import requests
import sys
from pathlib import Path

GATEWAY_URL = "http://gaiaftcl.com:8803"

def ingest_document(filepath: str, source: str, key_facts: dict):
    """Ingest a document into GaiaFTCL"""
    path = Path(filepath)
    if not path.exists():
        print(f"❌ File not found: {filepath}")
        return None
    
    content = path.read_text()
    
    payload = {
        "caller_id": "ingest_documents",
        "source": source,
        "content_type": "KNOWLEDGE",
        "envelope_type": "KNOWLEDGE",
        "payload": {
            "document": path.name,
            "content": content,
            "key_facts": key_facts
        }
    }
    
    resp = requests.post(f"{GATEWAY_URL}/ingest", json=payload, timeout=10)
    
    if resp.status_code == 200:
        data = resp.json()
        print(f"✅ {path.name}: {data.get('claim_id')}")
        return data.get('claim_id')
    else:
        print(f"❌ {path.name}: {resp.status_code} {resp.text}")
        return None

def main():
    base = Path("/Users/richardgillespie/Documents/FoT8D")
    
    documents = [
        {
            "path": base / "B2CN_SUPERCONDUCTOR_SYNTHESIS.md",
            "source": "Rick Gillespie - B2CN Superconductor Complete Guide",
            "key_facts": {
                "material": "B₂CN",
                "tc_k": 363,
                "tc_celsius": 90,
                "applications": ["underwater_levitation", "space_propulsion", "zero_loss_power"],
                "synthesis_method": "HPHT",
                "cost_per_kg_industrial": 2000,
                "levitation_capacity": "509,684 tons per 10kg",
                "replaces": "Neodymium_magnets"
            }
        },
        {
            "path": base / "B4C_DIAMOND_SYNTHESIS.md",
            "source": "Rick Gillespie - B4C Diamond Composite Guide",
            "key_facts": {
                "material": "B₄C-Diamond",
                "composition": "60% B₄C + 40% Diamond",
                "strength_gpa": 12.0,
                "density_g_cm3": 3.2,
                "max_depth_km": 541,
                "lifetime_years": 88,
                "synthesis_method": "Spark_Plasma_Sintering",
                "cost_per_kg_industrial": 80,
                "applications": ["underwater_hulls", "space_shielding"]
            }
        },
        {
            "path": base / "cells/fusion/TOP_5_MATERIALS_DEVELOPING_COUNTRIES_CORRECT.md",
            "source": "Rick Gillespie - Top 5 Materials for Global Entropy Reduction",
            "key_facts": {
                "focus": "developing_countries",
                "count": 5,
                "materials": ["B2CN_superconductor", "Boron_Diamond", "O2_membrane", "H_Diamond", "B2CN_levitation"],
                "impact_areas": ["energy", "infrastructure", "transport", "disaster_relief"],
                "economic_impact_billions": 500,
                "entropy_reduction": "planetary_scale"
            }
        },
        {
            "path": base / "cells/fusion/knowledge_corpus/REE_NEGATION_PATHWAYS.md",
            "source": "Rick Gillespie - REE Negation via UUM-8D",
            "key_facts": {
                "focus": "REE_replacement",
                "alternatives": {
                    "Neodymium": {"alternative": "Iron_Nitride_Fe16N2", "performance": "2x_stronger"},
                    "Dysprosium": {"alternative": "Tetrataenite_Fe_Ni", "formation": "seconds_vs_millions_years"},
                    "Cobalt": {"alternative": "Iron_Nitride_magnet_free_motors"},
                    "Cerium_Lanthanum": {"alternative": "3D_printed_catalysts_vQbit"}
                },
                "mining_projects_negated": ["Greenland_REE", "DRC_Cobalt", "China_refineries"],
                "timeline_years": 5,
                "entropy_impact": "eliminates_2000_tons_waste_per_ton"
            }
        }
    ]
    
    claim_ids = []
    for doc in documents:
        if doc["path"].exists():
            claim_id = ingest_document(str(doc["path"]), doc["source"], doc["key_facts"])
            if claim_id:
                claim_ids.append(claim_id)
        else:
            print(f"⚠️  Skipping {doc['path'].name} (not found)")
    
    print(f"\n📊 Ingested {len(claim_ids)} documents")
    print(f"📋 Claim IDs: {', '.join(claim_ids)}")
    
    return len(claim_ids)

if __name__ == "__main__":
    count = main()
    sys.exit(0 if count > 0 else 1)
