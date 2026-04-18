#!/usr/bin/env python3
import json
import sys
import os
from pathlib import Path

try:
    import jsonschema
except ImportError:
    print("ERROR: jsonschema package is required. Run 'pip3 install jsonschema'")
    sys.exit(1)

def validate_json(file_path, schema_path):
    print(f"Validating {file_path.name} against {schema_path.name}...")
    
    if not file_path.exists():
        print(f"  -> SKIPPED: File {file_path} not found.")
        return True
        
    if not schema_path.exists():
        print(f"  -> ERROR: Schema {schema_path} not found.")
        return False
        
    try:
        with open(file_path, 'r') as f:
            data = json.load(f)
        with open(schema_path, 'r') as f:
            schema = json.load(f)
            
        jsonschema.validate(instance=data, schema=schema)
        print(f"  -> ✅ VALID")
        return True
    except jsonschema.exceptions.ValidationError as err:
        print(f"  -> ❌ INVALID: {err.message}")
        return False
    except Exception as e:
        print(f"  -> ❌ ERROR: {str(e)}")
        return False

def main():
    print("=== GAMP 5 Schema Validation ===")
    
    root_dir = Path(__file__).resolve().parent.parent
    evidence_dir = root_dir / "evidence"
    schema_dir = root_dir / "config" / "schemas"
    
    # We will validate the latest PQ receipt against the pq_receipt schema
    pq_dir = evidence_dir / "pq"
    pq_schema = schema_dir / "pq_receipt.schema.json"
    
    success = True
    
    if pq_dir.exists():
        pq_files = sorted(pq_dir.glob("pq_interactive_receipt_*.json"), reverse=True)
        if pq_files:
            latest_pq = pq_files[0]
            if not validate_json(latest_pq, pq_schema):
                success = False
        else:
            print("No interactive PQ receipts found.")
            
    # We can also add validation for plant configs
    plants_dir = root_dir / "config" / "plants"
    plant_schema = schema_dir / "plant_config.schema.json"
    
    # Since plants are YAML, we'd need PyYAML to parse them.
    # For now, we will just validate the JSON receipts.
    
    if not success:
        print("\n❌ GAMP 5 Validation Failed.")
        sys.exit(1)
        
    print("\n✅ All checked receipts conform to GAMP 5 schemas.")

if __name__ == "__main__":
    main()
