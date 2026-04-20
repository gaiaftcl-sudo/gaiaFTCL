# Phase 1 read reconcile — OWL-P53 package ↔ GH-FS-001 & Communion

**Date:** 2026-04-18  
**Inputs:** [GH-FS-001](../../FUNCTIONAL_SPECIFICATION.md), [S4_C4_COMMUNION_UI_SPEC.md](../../S4_C4_COMMUNION_UI_SPEC.md), [GaiaHealth/docs/UI_SPEC_S4C4_COMMUNION_V1.md](../../../../../GaiaHealth/docs/UI_SPEC_S4C4_COMMUNION_V1.md)

## 1. GH-FS-001 alignment

| GH-FS-001 theme | OWL-P53 mapping |
|-----------------|-----------------|
| Research instrument; not diagnostic | Restated in [`INVARIANT_SPEC.md`](INVARIANT_SPEC.md) header and [`OWL_P53_DESIGN_GATE_MEMO.md`](../../OWL_P53_DESIGN_GATE_MEMO.md). |
| M/I/A epistemic chain | Five channels default to **M/T/I/A** per channel table; frequency uses **(T)/(A)** until PQ promotion. |
| Communion as design target | Cross-linked; registry/projection UI language marked **[I]** where [`PHASE1_GAP_LIST.md`](PHASE1_GAP_LIST.md) applies. |
| CURE equation for small-molecule MD | OWL-P53 adds **pathway-level** C4 constraint narrative; does not change FR-001…FR-NN until CCR adopts. |

## 2. Communion UI spec numbering

`S4_C4_COMMUNION_UI_SPEC.md` uses **§5.1–5.2** today; plan-legacy **§5.3 / §5.5 / §8 plugin ABI** do **not** match current headings (§8 is document control).  

**Reconcile rule:** OWL-P53 docs cite **actual** sections or **`UI_SPEC_S4C4_COMMUNION_V1.md`** for extended narrative — see [`PHASE0_VERIFICATION.md`](PHASE0_VERIFICATION.md).

## 3. Filename map (plan → actual)

| Plan placeholder | Actual (Phase 0) |
|------------------|------------------|
| `projection_engine.swift` | Not found — **[I]** |
| `s4_ingestor.swift` | Not found — **[I]** |
| `GH-OWL-UNIFIED-FREQ-001.md` | Not found — CLI arch + UI refs — **[I]** |
| `S4C4Hash.swift` | [`cells/fusion/.../S4C4Hash.swift`](../../../../fusion/Sources/GaiaFTCLCore/Hashing/S4C4Hash.swift) |

## 4. Phase 2 exit (documentation)

- [`INVARIANT_SPEC.md`](INVARIANT_SPEC.md) on `main` **before** Qualification-Catalog wiki row.  
- [`PQ_PROTOCOL.md`](PQ_PROTOCOL.md) PQ-v1 / PQ-v2 split explicit.  
- Part 11 and quorum **[I]** where required.
