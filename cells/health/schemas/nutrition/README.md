# Nutrition JSON Schemas (Draft 2020-12)

| Schema | File |
|--------|------|
| User profile | `user_nutrition_profile.schema.json` |
| Monitoring | `nutrition_monitoring_config.schema.json` |
| S4 evidence envelope | `nutrition_s4_evidence.schema.json` |
| C4 filter declaration | `nutrition_c4_filter_declaration.schema.json` |

## Validation **[I]**

- **Schemas only:** `python3 validate_nutrition_schemas.py` from this directory (requires `pip install jsonschema`, or set `NUTRITION_SCHEMA_STRICT=1` to fail if missing).
- **Full IQ + OQ + PQ (OWL-NUTRITION):** `bash ../../scripts/owl_nutrition_iqoqpq_validate.sh` from repo root — fresh `cargo clean`, all fixtures, WASM tests, receipt under `docs/invariants/OWL-NUTRITION/evidence/`.

## Fixtures

`fixtures/` — vegetarian, kosher+allergy+ramadan cultural flag, **composite** vegetarian+halal+tree-nut (profile + `c4_composite_declaration.json`).
