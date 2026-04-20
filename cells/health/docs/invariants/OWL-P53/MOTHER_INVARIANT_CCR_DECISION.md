# Decision — mother invariant vs ordinary invariant (v1)

**Date:** 2026-04-18  
**Related:** [GAMP5_LIFECYCLE §4.2 Architectural CCR](../../../lithography/docs/GAMP5_LIFECYCLE.md#42-architectural-ccr)

## Decision

**Option (b)** — Register **`OWL-P53-INV1-TUMOR-SUPPRESSION`** at **v1** as an **ordinary** C4-aligned invariant specification (documentation + closure conditions + PQ-v1 synthetic path). **Defer “mother invariant” status** (other invariants declaring projection against OWL-P53) to **v2**, to be gated by a **three-cell architectural CCR** once registry topology and implementation are ready.

## Rationale

- [GAMP5_LIFECYCLE.md](../../../lithography/docs/GAMP5_LIFECYCLE.md) §4.2 requires **three cell-owner signatures** (Lithography + Fusion + Health) and re-qualification for changes that alter **ABI / cross-cell dependency topology**. Declaring a **mother invariant** that other registered invariants must project against is a **registry topology** change, not an editorial edit.
- Shipping **v1** documentation without signed multi-cell CCR avoids a **false** claim that the live registry already implements mother topology.
- **v2** promotion path: after CCR approval, update `INVARIANT_SPEC.md`, Communion/UI specs, and CLI invariant census accordingly.

## v1 language

In all v1 artifacts, describe OWL-P53 as a **composite tumor-suppression invariant** with five S4 channels. **Do not** state that other invariants “declare against” OWL-P53 until v2.
