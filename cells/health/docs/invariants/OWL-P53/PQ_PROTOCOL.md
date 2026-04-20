# PQ — Performance Qualification — OWL-P53-INV1

**Parent:** [INVARIANT_SPEC.md](INVARIANT_SPEC.md)  
**Splits:** **PQ-v1** (synthetic / dry-run / DUA-safe) vs **PQ-v2** (IRB / human cohort)

## 1. PQ-v1 — Synthetic performance (shippable near term)

**Intent:** Demonstrate end-to-end **performance** of the composite invariant logic against **pre-registered** synthetic or open **non-PHI** datasets and fixed scenarios.

**Includes:**

- Correlation / coherence checks between **frequency-domain features** (from [`FREQUENCY_ADDENDUM.md`](FREQUENCY_ADDENDUM.md)) and the other four channels, under a written analysis plan.  
- Explicit **limitations** paragraph for wiki and outreach: PQ-v1 does **not** establish clinical safety or efficacy.

**Excludes:**

- **Elephant TP53 copy-number biology** (Abegglen et al., JAMA 2015) as a **human oncology cohort** requirement — that work belongs in [`evidence/references/abegglen-2015-jama-elephant-tp53.md`](evidence/references/abegglen-2015-jama-elephant-tp53.md) and [`SMALL_MOLECULE_INTEGRATION.md`](SMALL_MOLECULE_INTEGRATION.md) as **related biology only**.  
- Claims that PQ-v1 substitutes for regulated clinical validation.

## 2. PQ-v2 — IRB / biobank / Li-Fraumeni–class cohort (separate track)

**Intent:** Pre-registered human-subjects or authenticated biobank pathway with **IRB**, **DUA**, and **12–24 month** class runway (order-of-magnitude planning; exact N and power in protocol, not here).

**Rules:**

- **Separate** milestone from PQ-v1 — different **CALORIE** / success criteria document.  
- **No** wiki text or catalog row implies PQ-v2 delivery is imminent.  
- **HIPAA / GDPR** applicability follows real PHI entry — footnote in Qualification-Catalog matrix (PQ-v1 **N/A** for PHI).

## 3. Elephant reference (normative exclusion)

Abegglen LM, et al. Potential Mechanisms for Cancer Resistance in Elephants and Comparative Cellular Response to DNA Damage in African and Asian Elephant Cells. *JAMA.* 2015. DOI [10.1001/jama.2015.13134](https://doi.org/10.1001/jama.2015.13134).

**Use:** Related species biology and **hypothesis context** only. **Do not** list under PQ-v2 human oncology cohort tables.

## 4. PQ exit (PQ-v1)

| ID | Criterion |
|----|-----------|
| PQ1-1 | Pre-registered analysis plan archived under `evidence/pq/`. |
| PQ1-2 | Reported coherence metrics with **(T)/(A)** discipline on frequency features. |
| PQ1-3 | Limitations section signed by qualified author role (per QMS). |

PQ-v2 exit criteria **[deferred]** — separate protocol revision.
