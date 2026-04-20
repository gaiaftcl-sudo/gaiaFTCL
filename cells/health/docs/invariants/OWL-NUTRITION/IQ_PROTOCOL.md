# IQ — Installation Qualification — OWL-NUTRITION

**Parent:** [`INVARIANT_FAMILY_SPEC.md`](INVARIANT_FAMILY_SPEC.md) · [GH-FS-001](../../FUNCTIONAL_SPECIFICATION.md)

## 1. Purpose

Verify OWL-NUTRITION **documentation**, **JSON schemas**, **WASM exports** (when present), and **UI bundles** (when present) are installed and version-hashed consistently.

## 2. IQ checks

| ID | Criterion | Evidence |
|----|-----------|----------|
| IQ-N-1 | `cells/health/docs/invariants/OWL-NUTRITION/` complete per README | Git tree |
| IQ-N-2 | Schemas present under `cells/health/schemas/nutrition/` | File existence |
| IQ-N-3 | WASM nutrition exports registered **[I]** | `wasm_constitutional` manifest |
| IQ-N-4 | Identity mooring (Owl) active per Health IQ | [`OWL-P53/IQ_PROTOCOL.md`](../OWL-P53/IQ_PROTOCOL.md) cross-link |
| IQ-N-5 | 21 CFR Part 11 **target [I]** | Same posture as OWL-P53 |

## 3. Exit

Signed receipt **[I]** — `evidence/iq/` when automation exists.

## 4. Automation (local)

Run from repository root:

```bash
bash cells/health/scripts/owl_nutrition_iqoqpq_validate.sh
```

Performs IQ (tree + schemas + WASM exports + `jsonschema` in a venv), then `cargo clean -p gaia-health-substrate` and `cargo test -p gaia-health-substrate` (OQ + synthetic PQ). Writes `evidence/owl_nutrition_iqoqpq_receipt.json` (gitignored — archive in your QMS if needed).
