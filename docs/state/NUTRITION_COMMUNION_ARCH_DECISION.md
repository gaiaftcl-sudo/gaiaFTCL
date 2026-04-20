# NUTRITION_COMMUNION_ARCH_DECISION — Communion vs GaiaHealth-internal UI spec

**Status:** APPROVED (documentation phase)  
**Date:** 2026-04-20

## Decision

**Select (b): GaiaHealth-internal extension** for OWL-NUTRITION UI and nutrition configuration surfaces **in v1**.

**Rationale**

1. [`cells/health/docs/S4_C4_COMMUNION_UI_SPEC.md`](../../cells/health/docs/S4_C4_COMMUNION_UI_SPEC.md) does **not** contain numbered §5.3 / §5.8 / §5.9 / §5.10; absorbing nutrition tabs would require **new numbered sections** and cross-cell review.
2. [`COMMUNION_UI_ARCHITECTURE_EXTENDED.md`](../../cells/health/docs/COMMUNION_UI_ARCHITECTURE_EXTENDED.md) already carries long-form roadmap prose; nutrition can ship as a **focused annex** first.
3. **(a) CCR / full Communion merge** remains the **follow-on** when OWL-NUTRITION is stable: promote [`NUTRITION_UI_SPEC.md`](../../cells/health/docs/invariants/OWL-NUTRITION/NUTRITION_UI_SPEC.md) (Phase 1) into Communion under **architectural CCR** per [`GAMP5_LIFECYCLE`](../../cells/lithography/docs/GAMP5_LIFECYCLE.md) §4.2-style process.

## Gate for Phase 3

Swift UI work **must** implement against **GaiaHealth-internal** spec paths until **(a)** is executed.

## Cross-links

- Gap table: [`nutrition_reconciliation_gap_table.md`](nutrition_reconciliation_gap_table.md)
