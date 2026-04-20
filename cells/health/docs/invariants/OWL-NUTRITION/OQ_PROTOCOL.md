# OQ — Operational Qualification — OWL-NUTRITION

## 1. Purpose

Synthetic end-to-end **projection** and **C4 filter** tests — trace each case to a mother invariant or `c4_filters/*.md` row.

## 2. Test matrix **[I]**

| Case | Invariant / filter | Expected terminal |
|------|---------------------|-------------------|
| OQ-N-1 | VEGAN + B12 lab low | Drift + monitoring **[I]** |
| OQ-N-2 | KOSHER + pork ingredient | Sanitize or REFUSED **[I]** |
| OQ-N-3 | Unsigned plugin payload | REFUSED / scrub **[I]** |

## 3. Traceability

Each OQ case ID → spec § — maintained in `evidence/oq/` **[I]**.
