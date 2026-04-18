# MASTER_WITNESS_NOTE — INV3 recursive invariant repair

- **generated_utc:** `20260326T200438Z`
- **gateway:** `http://127.0.0.1:18803`
- **total_discoveries_in_lab_docs:** 14
- **counts_by_type (manifest):** `{"protein": 7, "small_molecule": 7}`

## Phase 2 — substrate classification

- **before repair:** ANCHORED=1, MISSING=3, MISMATCH=0, PENDING=10, BLOCKED=0
- **after repair:** ANCHORED=4, MISSING=0, MISMATCH=0, PENDING=10, BLOCKED=0

## Phase 3 — universal_ingest claim_key values

- `claim_1774555518.408084`
- `claim_1774555519.341749`
- `claim_1774555520.221805`

## C4 UPSERT (discovered_proteins) via gateway /query

- ALZ-001 discovered_proteins UPSERT ok=True {"_key": "alz_001_canonical_anchor", "_id": "discovered_proteins/alz_001_canonical_anchor", "_rev": "_lQt-T6a---", "protein_id": "ALZ-001", "name": "ALZ-001 (lab protocol anchor)", "sequence": "PWKSDAIGAVFLRLAYE", "source": "inv3_recursive_
- ALZ-002 discovered_proteins UPSERT ok=True {"_key": "alz_002_canonical_anchor", "_id": "discovered_proteins/alz_002_canonical_anchor", "_rev": "_lQt-Uv6---", "protein_id": "ALZ-002", "name": "ALZ-002 (lab protocol anchor)", "sequence": "GPGAAVEDAIYSWRFKL", "source": "inv3_recursive_
- LEUK-005 discovered_proteins UPSERT ok=True {"_key": "leuk_005_canonical_anchor", "_id": "discovered_proteins/leuk_005_canonical_anchor", "_rev": "_lQt-Vsu---", "protein_id": "LEUK-005", "name": "LEUK-005 (lab protocol anchor)", "sequence": "FYNCGLKIKYKPAVWAPAGKPFFPGFWYEKPKRPLCSATLIP

## PROJECTION_ERROR_CORRECTED (lab doc patches)

- _(none)_

## Phase 4 — inv3_s4_projection_verify.py

- **final_exit_code:** `0`

## Terminal statement

**ALL_INVARIANTS_CLOSED**
