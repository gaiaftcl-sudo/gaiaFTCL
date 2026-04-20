# PQ — Performance Qualification — OWL-P53-INV1

**Parent:** [INVARIANT_SPEC.md](INVARIANT_SPEC.md)  
**Splits:** **PQ-v1** (synthetic / dry-run / DUA-safe) vs **PQ-v2** (IRB / **human** cohort)

## 1. PQ-v1 — Synthetic performance (shippable near term)

**Intent:** Demonstrate end-to-end **performance** of the composite invariant logic against **pre-registered** synthetic or open **non-PHI** datasets and fixed scenarios.

**Includes:**

- Correlation / coherence checks between **frequency-domain features** (from [`FREQUENCY_ADDENDUM.md`](FREQUENCY_ADDENDUM.md)) and the other four channels, under a written analysis plan.  
- Explicit **limitations** paragraph for wiki and outreach: PQ-v1 does **not** establish clinical safety or efficacy.

**Excludes:**

- Claims that PQ-v1 substitutes for regulated clinical validation.

## 2. PQ-v2 — IRB / biobank — **humans only** (separate track)

**Intent:** Pre-registered **human-subjects** or authenticated **human** biobank pathway with **IRB**, **DUA**, and **12–24 month** class runway (order-of-magnitude planning; exact N and power in a separate protocol, not here).

**Substrate:** GaiaHealth OWL-P53 is declared over **human** cellular/clinical context; Φ_master and the five channels are **human** research/clinical frames. **No non-human biological material** qualifies this invariant’s PQ-v2. Cross-species comparative biology is **out of scope** for PQ-v2 **cohort design** (evolutionary literature may appear in [`INVARIANT_SPEC.md`](INVARIANT_SPEC.md) §1 only as background — not as experimental arms).

**Target cohort arms (all human — illustrative; arms locked in pre-registered protocol):**

| Arm | Role |
|-----|------|
| **A — LFS-class germline** | Carriers of **pathogenic germline *TP53*** variants (Li–Fraumeni / LFS-class), ascertained per clinical genetics criteria. |
| **B — Controls** | **Age-matched** (and protocol-defined matched) participants **without** pathogenic germline *TP53* per IRB-approved criteria. |
| **C — Oncology (somatic)** | Patients with **somatic** p53-pathway–relevant malignancy (tumor/panel-defined), per pre-registered inclusion/exclusion. |

**Sourcing posture:** Materials accessed through networks that routinely operate under **IRB + DUA** (e.g. dbGaP-accessible studies, NCI / European Li–Fraumeni consortia-class registries — **generic examples**, not guarantees of access or site approval).

**Rules:**

- **Separate** milestone from PQ-v1 — different **CALORIE** / success criteria document.  
- **No** wiki text or catalog row implies PQ-v2 delivery is imminent.  
- **HIPAA / GDPR** applicability follows real PHI entry — footnote in Qualification-Catalog matrix (PQ-v1 **N/A** for PHI).

## 3. PQ exit — PQ-v1

| ID | Criterion |
|----|-----------|
| PQ1-1 | Pre-registered analysis plan archived under `evidence/pq/`. |
| PQ1-2 | Reported coherence metrics with **(T)/(A)** discipline on frequency features. |
| PQ1-3 | Limitations section signed by qualified author role (per QMS). |

## 4. PQ exit — PQ-v2 **[deferred]**

Full statistical and clinical endpoints belong in a **separate** IRB-aligned protocol. **Normative rule:** PQ-v2 success is defined only on **human** primary and secondary endpoints agreed pre-registration — not on comparative non-human biology.
