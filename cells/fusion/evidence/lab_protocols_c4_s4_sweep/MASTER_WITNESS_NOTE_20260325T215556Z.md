# MASTER_WITNESS_NOTE — LAB_PROTOCOLS S4 × C4 unified sweep

- **generated_utc:** 20260325T215556Z
- **gateway:** `http://77.42.85.60:8803`
- **gateway_ok:** true
- **lab_files:** 3

## Counts

| MATCH | MISMATCH | UNKNOWN | BLOCKED | NO_S4_STRUCTURE |
|-------|----------|---------|---------|-------------------|
| 1 | 0 | 6 | 7 | 0 |

## Terminal state (mission criterion)

Zero **MISMATCH** requires every entity with both S4 structure export and C4 canonical to agree. **UNKNOWN** means substrate row or field missing — ingest C4, then re-run. **BLOCKED** is per-entity or whole-gateway I/O failure.

- **mismatch_count:** 0
- **unknown_count:** 6
- **blocked_count:** 7
- **clean_projection_achieved:** false

## Entities

| entity | status | c4_collection | c4_key | detail |
|--------|--------|-----------------|--------|--------|
| ALZ-001 | BLOCKED | discovered_proteins | `` | BLOCKED: HTTP Error 500: Internal Server Error |
| ALZ-002 | BLOCKED | discovered_proteins | `` | BLOCKED: HTTP Error 500: Internal Server Error |
| ALZ-003 | BLOCKED | discovered_proteins | `` | BLOCKED: HTTP Error 500: Internal Server Error |
| ALZ-004 | BLOCKED | discovered_proteins | `` | BLOCKED: HTTP Error 500: Internal Server Error |
| ALZ-005 | BLOCKED | discovered_proteins | `` | BLOCKED: HTTP Error 500: Internal Server Error |
| ALZ-CHEM | UNKNOWN | discovered_molecules | `` | No C4 molecule/compound row; flag for ingest |
| AML-CHEM-001 | MATCH | discovered_molecules | `cancer_candidate_9084` |  |
| LEUK-005 | BLOCKED | discovered_proteins | `` | BLOCKED: HTTP Error 500: Internal Server Error |
| MEN-CHEM-001 | UNKNOWN | discovered_molecules | `` | No C4 molecule/compound row; flag for ingest |
| MEN-CHEM-002 | UNKNOWN | discovered_molecules | `` | No C4 molecule/compound row; flag for ingest |
| MEN-CHEM-003 | UNKNOWN | discovered_molecules | `` | No C4 molecule/compound row; flag for ingest |
| MEN-CHEM-004 | UNKNOWN | discovered_molecules | `` | No C4 molecule/compound row; flag for ingest |
| MEN-CHEM-005 | UNKNOWN | discovered_molecules | `` | No C4 molecule/compound row; flag for ingest |
| MENING-PROT-001 | BLOCKED | discovered_proteins | `` | BLOCKED: HTTP Error 500: Internal Server Error |