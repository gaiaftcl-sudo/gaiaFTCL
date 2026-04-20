# Audit dry-run — self-administered (Phase 9)

**Operator:** Internal engineering / QMS prep — **not** a third-party regulatory audit.  
**Regulatory recognition:** **None** by default; outputs are **architectural validation** artifacts only.

## Distinction

| Mode | Purpose | Recognized receipt |
|------|---------|-------------------|
| **Self-administered** (this file) | Prove traceability, receipts, tombstone paths | Internal CALORIE gate |
| **Third-party / sponsor audit** | Submission to regulator or notified body | **Out of scope** for v1 academic release — **[I]** engagement |

## Six-framework synthetic scenarios (checklist)

| Framework | Scenario | Expected artifact |
|-----------|----------|-------------------|
| GAMP 5 | Inspector requests IQ evidence path | `evidence/iq/` index **[I]** |
| Annex 11 | E-record signature chain | Signed projection JSON **[I]** |
| Part 11 | Who signed audit digest | Wallet id in routing doc |
| HIPAA | PHI scrubber on narrative | `phi_boundary_check` path |
| GDPR | DSAR tombstone | Audit event + erasure log **[I]** |
| IEC 62304 | SaMD claim | **N/A** documented |

## Receipt

`CALORIE(nutrition-phase-9): self-admin dry-run checklist recorded; third-party audit **[I]** downstream.`
