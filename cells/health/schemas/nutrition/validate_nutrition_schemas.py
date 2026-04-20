#!/usr/bin/env python3
"""Validate nutrition fixtures against Draft 2020-12 schemas. Optional: pip install jsonschema."""
import json
import os
import sys
from pathlib import Path

try:
    import jsonschema
    from jsonschema import Draft202012Validator
except ImportError:
    msg = "install jsonschema (pip install jsonschema)"
    if os.environ.get("NUTRITION_SCHEMA_STRICT"):
        print(f"FAIL: {msg}", file=sys.stderr)
        sys.exit(1)
    print(f"SKIP: {msg}", file=sys.stderr)
    sys.exit(0)

ROOT = Path(__file__).resolve().parent


def load(p: Path):
    return json.loads(p.read_text())


def main() -> int:
    profile_schema = load(ROOT / "user_nutrition_profile.schema.json")
    c4_schema = load(ROOT / "nutrition_c4_filter_declaration.schema.json")
    monitoring_schema = load(ROOT / "nutrition_monitoring_config.schema.json")
    s4_schema = load(ROOT / "nutrition_s4_evidence.schema.json")
    pv = Draft202012Validator(profile_schema)
    cv = Draft202012Validator(c4_schema)
    mv = Draft202012Validator(monitoring_schema)
    sv = Draft202012Validator(s4_schema)

    fixtures = [
        ("fixtures/vegetarian_declaration.json", pv),
        ("fixtures/kosher_allergy_ramadan.json", pv),
        ("fixtures/composite_vegetarian_halal_treenut.json", pv),
        ("fixtures/c4_composite_declaration.json", cv),
        ("fixtures/minimal_monitoring_config.json", mv),
        ("fixtures/minimal_s4_evidence.json", sv),
    ]
    for rel, validator in fixtures:
        data = load(ROOT / rel)
        validator.validate(data)
        print(f"OK {rel}")
    print("validate_nutrition_schemas: all fixtures passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
