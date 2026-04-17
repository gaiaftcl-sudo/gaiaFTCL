# MASTER_WITNESS_NOTE — LAB_PROTOCOLS S4 × C4 unified sweep

- **generated_utc:** 20260325T215838Z
- **gateway:** `http://77.42.85.60:8803`
- **gateway_ok:** true
- **lab_files:** 3

## Counts

| MATCH | MISMATCH | UNKNOWN | BLOCKED | NO_S4_STRUCTURE |
|-------|----------|---------|---------|-------------------|
| 1 | 0 | 3 | 0 | 10 |

## Terminal state (mission criterion)

Zero **MISMATCH** requires every entity with both S4 structure export and C4 canonical to agree. **UNKNOWN** means substrate row or field missing — ingest C4, then re-run. **BLOCKED** is per-entity or whole-gateway I/O failure.

- **mismatch_count:** 0
- **unknown_count:** 3
- **blocked_count:** 0
- **clean_projection_achieved:** false (strict: no UNKNOWN)

## Entities

| entity | status | c4_collection | c4_key | detail |
|--------|--------|-----------------|--------|--------|
| ALZ-001 | UNKNOWN | discovered_proteins | `` | No C4 protein row; ingest or align protein_id before SETTLED projection |
| ALZ-002 | UNKNOWN | discovered_proteins | `` | No C4 protein row; ingest or align protein_id before SETTLED projection |
| ALZ-003 | NO_S4_STRUCTURE | discovered_proteins | `` | No lab sequence export (TBD/candidate); no C4 row |
| ALZ-004 | NO_S4_STRUCTURE | discovered_proteins | `` | No lab sequence export (TBD/candidate); no C4 row |
| ALZ-005 | NO_S4_STRUCTURE | discovered_proteins | `` | No lab sequence export (TBD/candidate); no C4 row |
| ALZ-CHEM | NO_S4_STRUCTURE | discovered_molecules | `` | No SMILES in lab (TBD); no C4 row |
| AML-CHEM-001 | MATCH | discovered_molecules | `cancer_candidate_9084` |  |
| LEUK-005 | UNKNOWN | discovered_proteins | `` | No C4 protein row; ingest or align protein_id before SETTLED projection |
| MEN-CHEM-001 | NO_S4_STRUCTURE | discovered_molecules | `` | No SMILES in lab (TBD); no C4 row |
| MEN-CHEM-002 | NO_S4_STRUCTURE | discovered_molecules | `` | No SMILES in lab (TBD); no C4 row |
| MEN-CHEM-003 | NO_S4_STRUCTURE | discovered_molecules | `` | No SMILES in lab (TBD); no C4 row |
| MEN-CHEM-004 | NO_S4_STRUCTURE | discovered_molecules | `` | No SMILES in lab (TBD); no C4 row |
| MEN-CHEM-005 | NO_S4_STRUCTURE | discovered_molecules | `` | No SMILES in lab (TBD); no C4 row |
| MENING-PROT-001 | NO_S4_STRUCTURE | discovered_proteins | `` | No lab sequence export (TBD/candidate); no C4 row |