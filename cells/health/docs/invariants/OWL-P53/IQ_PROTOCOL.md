# IQ — Installation Qualification — OWL-P53-INV1 package

**Parent:** [GH-FS-001](../../FUNCTIONAL_SPECIFICATION.md) · [INVARIANT_SPEC.md](INVARIANT_SPEC.md)  
**Scope:** Documentation and tooling readiness for the OWL-P53 invariant **documentation package** on the operator workstation (not a separate binary from GaiaHealth IQ unless explicitly scoped).

## 1. Purpose

Verify that:

- Repository paths for [`INVARIANT_SPEC.md`](INVARIANT_SPEC.md) and protocols exist on the qualified branch.  
- Cross-links resolve to committed artifacts (relative links in this directory).  
- Evidence directories exist per [`evidence/README.md`](evidence/README.md).  
- Operators can locate **S4C4** hash utilities when wiring receipts — [`S4C4Hash.swift`](../../../../fusion/Sources/GaiaFTCLCore/Hashing/S4C4Hash.swift) (Fusion cell) is the canonical implementation reference until Health-local wrappers exist **[I]**.

## 2. 21 CFR Part 11 posture **[I]**

**Target:** Electronic records / audit trail / e-signature posture aligned with 21 CFR Part 11 where GaiaHealth operates as a GAMP 5 Cat 5 application.

**v1 statement:** Current GaiaHealth release state is **target Part 11 posture**; full Part 11 **Installation** evidence for OWL-P53-specific flows is **[I]** until change control records an explicit IQ run and signed receipts for this invariant package.

Do **not** represent Part 11 as fully satisfied in catalog matrices without footnoted evidence stage — see wiki **Qualification-Catalog** framework row.

## 3. Composite projection / quorum **[I]**

The reviewed plan referenced **5-of-9 quorum** in `projection_engine.swift`. **No** module by that name was found in the Health cell tree at documentation time.

**v1 rule:** Do **not** hard-code quorum numbers in [`INVARIANT_SPEC.md`](INVARIANT_SPEC.md). Treat quorum as **[I]** until implemented and named in code under change control.

## 4. IQ exit criteria (documentation package)

| Criterion | Evidence |
|-----------|----------|
| `INVARIANT_SPEC.md` present | Git blob on `main` |
| IQ/OQ/PQ protocol files present | This directory |
| Phase 0 table filled | [`PHASE0_VERIFICATION.md`](PHASE0_VERIFICATION.md) |
| Frequency policy chosen | [`FREQUENCY_BAND_POLICY.md`](FREQUENCY_BAND_POLICY.md) Option B |

Signed IQ receipt for OWL-P53-specific automation **[I]** — follow [`cells/health/wiki/IQ-Installation-Qualification.md`](../../../wiki/IQ-Installation-Qualification.md) when a unified script is extended.
