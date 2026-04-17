# MASTER_WITNESS_NOTE — LAB_PROTOCOLS S4 × C4 unified sweep

- **generated_utc:** 20260325T215743Z
- **gateway:** `http://77.42.85.60:8803`
- **gateway_ok:** true
- **lab_files:** 3

## Counts

| MATCH | MISMATCH | UNKNOWN | BLOCKED | NO_S4_STRUCTURE |
|-------|----------|---------|---------|-------------------|
| 1 | 0 | 13 | 0 | 0 |

## Terminal state (mission criterion)

Zero **MISMATCH** requires every entity with both S4 structure export and C4 canonical to agree. **UNKNOWN** means substrate row or field missing — ingest C4, then re-run. **BLOCKED** is per-entity or whole-gateway I/O failure.

- **mismatch_count:** 0
- **unknown_count:** 13
- **blocked_count:** 0
- **clean_projection_achieved:** true

## Entities

| entity | status | c4_collection | c4_key | detail |
|--------|--------|-----------------|--------|--------|
| ALZ-001 | UNKNOWN | discovered_proteins | `` | No C4 protein row; ingest or align protein_id before SETTLED projection |
| ALZ-002 | UNKNOWN | discovered_proteins | `` | No C4 protein row; ingest or align protein_id before SETTLED projection |
| ALZ-003 | UNKNOWN | discovered_proteins | `` | No C4 protein row; ingest or align protein_id before SETTLED projection |
| ALZ-004 | UNKNOWN | discovered_proteins | `` | No C4 protein row; ingest or align protein_id before SETTLED projection |
| ALZ-005 | UNKNOWN | discovered_proteins | `` | No C4 protein row; ingest or align protein_id before SETTLED projection |
| ALZ-CHEM | UNKNOWN | discovered_molecules | `` | No C4 molecule/compound row; flag for ingest |
| AML-CHEM-001 | MATCH | discovered_molecules | `cancer_candidate_9084` |  |
| LEUK-005 | UNKNOWN | discovered_proteins | `` | No C4 protein row; ingest or align protein_id before SETTLED projection |
| MEN-CHEM-001 | UNKNOWN | discovered_molecules | `` | No C4 molecule/compound row; flag for ingest |
| MEN-CHEM-002 | UNKNOWN | discovered_molecules | `` | No C4 molecule/compound row; flag for ingest |
| MEN-CHEM-003 | UNKNOWN | discovered_molecules | `` | No C4 molecule/compound row; flag for ingest |
| MEN-CHEM-004 | UNKNOWN | discovered_molecules | `` | No C4 molecule/compound row; flag for ingest |
| MEN-CHEM-005 | UNKNOWN | discovered_molecules | `` | No C4 molecule/compound row; flag for ingest |
| MENING-PROT-001 | UNKNOWN | discovered_proteins | `` | No C4 protein row; ingest or align protein_id before SETTLED projection |