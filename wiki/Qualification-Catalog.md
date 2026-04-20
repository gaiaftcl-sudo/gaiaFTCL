# Qualification Catalog — GaiaHealth & cross-cell invariants

**Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie**

This page lists **qualification documentation packages** that exist on `main` with verifiable **blob** links. It is the wiki counterpart to repository-resident IQ/OQ/PQ protocols.

**Related:** [[GaiaFTCL-Fusion-Mac-Cell-Wiki]] · [[Mac-Cell-Guide]] · GaiaHealth cell wiki Home (repository: `cells/health/wiki/Home.md` on `main`).

---

## §4 — Domain packages (GaiaHealth)

### Oncology — OWL-P53-INV1 (tumor suppression)

| Field | Value |
|-------|--------|
| **Invariant ID** | `OWL-P53-INV1-TUMOR-SUPPRESSION` |
| **v1 status** | **Ordinary** invariant; “mother invariant” projection topology **deferred to v2** (CCR). See `MOTHER_INVARIANT_CCR_DECISION.md` on `main`. |
| **Core spec** | [`INVARIANT_SPEC.md` (blob)](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/invariants/OWL-P53/INVARIANT_SPEC.md) |
| **Package index** | [`README.md` (blob)](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/invariants/OWL-P53/README.md) |
| **IQ / OQ / PQ** | [IQ](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/invariants/OWL-P53/IQ_PROTOCOL.md) · [OQ](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/invariants/OWL-P53/OQ_PROTOCOL.md) · [PQ](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/invariants/OWL-P53/PQ_PROTOCOL.md) |
| **PQ split** | **PQ-v1** = synthetic / dry-run. **PQ-v2** = IRB / human cohort — **separate** milestone (no near-term implication). |
| **Elephant TP53 (Abegglen 2015)** | Related biology / reference stub only — **not** a human PQ cohort requirement. |

**Cardilini et al.** (conservation / methodology cite as needed): DOI [10.1016/j.biocon.2025.111593](https://doi.org/10.1016/j.biocon.2025.111593) — re-verify before normative use in sprint math.

---

## §8 — Framework applicability matrix (v1 — targets + footnotes)

Use **footnotes** for every **✓ target** or **[I]** — no bare checkmarks on aspirational rows.

| Field | OWL-P53-INV1 v1 | Footnote |
|-------|-----------------|----------|
| **GAMP 5 Category** | 5 (Custom); epistemic floor **(T)** where applicable | **fn-a** |
| **GAMP 5** | ✓ **target** — pre-clinical documentation stage | **fn-a** |
| **EU Annex 11** | ✓ **target** — **[I]** until live computerized system validation evidence | **fn-b** |
| **21 CFR Part 11** | **[I] target** — audit trail / e-signature not asserted complete for OWL-P53 flows at v1 | **fn-c** |
| **HIPAA** | **N/A** for PQ-v1 synthetic; **when** PHI enters PQ-v2 | **fn-d** |
| **GDPR** | Same split as HIPAA for Art. 9 health data | **fn-d** |
| **DO-178C** | N/A | **fn-e** |
| **IEC 62304** | **[I] target** — clinical productization path | **fn-f** |
| **IATF 16949** | N/A | **fn-e** |
| **ISO 9001** | ✓ **baseline QMS target** — scope footnote | **fn-g** |

### Footnotes

- **fn-a:** GAMP 5 Category 5 applies to GaiaHealth as custom application software; OWL-P53 v1 is documentation + synthetic OQ/PQ-v1 path — not a finished validated medical device submission.
- **fn-b:** EU Annex 11 computerized system validation evidence **[I]** for OWL-P53-specific workflows until recorded under QMS.
- **fn-c:** Part 11 posture stated as **target** in [`IQ_PROTOCOL.md`](https://github.com/gaiaftcl-sudo/gaiaFTCL/blob/main/cells/health/docs/invariants/OWL-P53/IQ_PROTOCOL.md); no bare “Part 11 ✓”.
- **fn-d:** PQ-v1 excludes real patient data; PQ-v2 triggers HIPAA/GDPR program controls — separate protocol.
- **fn-e:** Not applicable to stated scope (avionics / automotive).
- **fn-f:** If GaiaHealth is productized as SaMD, IEC 62304 mapping is a **target** — **[I]** at v1 doc package.
- **fn-g:** ISO 9001-aligned QMS is the **baseline quality target** for FortressAI / GaiaFTCL program documentation; scope statement lives in program QMS, not in this wiki row alone.

---

## lint_wiki (manual checklist)

For this page and sibling wiki pages:

- [ ] Internal links use `[[Wiki-Page-Name]]` slugs — **not** `Page.md` in URLs.  
- [ ] Repository pointers use **`/blob/main/...`** for files on `main`.  
- [ ] No bare aspirational ✓ without footnote in §8-style matrices.
