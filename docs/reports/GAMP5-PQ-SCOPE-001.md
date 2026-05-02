# GaiaFTCL PQ Scope — Franklin Mac Cell
**Document ID:** GAMP5-PQ-SCOPE-001  
**Version:** 1.0  
**Status:** PENDING — OQ closed at ffd978f  
**Author:** Rick Gillespie, FortressAI Research Institute  
**Prerequisite:** GAMP5-OQ-EVIDENCE-001.md sealed at ffd978f

## PQ Tests — Self-Review (PQ-SR)

| Test ID | Description | Status |
|---------|-------------|--------|
| PQ-SR-001 | 10 consecutive self-review cycles across both domains with no manual intervention; health scores non-decreasing | PENDING |
| PQ-SR-002 | Franklin improves at least one domain standard within 5 cycles of deliberately injected S⁴ degradation — **injection:** publish to **`gaiaftcl.substrate.s4.delta`** using **`S4DeltaCodec.encode`** (e.g. degrade prim stress via **s1→0.0**, **s3→0.1**); operator signing with **`GAIAFTCL_OPERATOR_SIGNATURE`** test value where the harness requires it | PENDING |
| PQ-SR-003 | Review cycle timing within ±10% of **`review_interval_seconds`** under normal operating load | PENDING |

## PQ Tests (legacy scope — PQ-001…005)

| Test ID | Description | Status |
|---------|-------------|--------|
| PQ-001 | Constitutional consistency across Apple Silicon generations (OQ-CONST-002 cross-gen run) | DEFERRED |
| PQ-002 | Sustained constitutional measurement under plasma telemetry load (N active prims, continuous S⁴ delta stream, 24h observation) | DEFERRED |
| PQ-003 | ManifoldTensor row allocation under domain expansion — all N rows consumed, tensorFull behavior verified | DEFERRED |
| PQ-004 | NATS fabric failure and recovery — broker restart during active constitutional measurement | DEFERRED |
| PQ-005 | Franklin self-healing loop under concurrent constitutional events from multiple domains | DEFERRED |

## Entry Criteria
- OQ-SIGNOFF committed on main ✅ (ffd978f)
- All OQ-FW-001 through OQ-FW-004 counts ≥ 1 ✅
- GaiaRTMGate CALORIE ✅
- OQ-FW-005 DEFERRED documented (nats CLI PATH) ✅
- OQ-CONST-002 DEFERRED documented (single Apple Silicon generation) ✅

## Exit Criteria (required before PQ can close)
- All DEFERRED tests resolved or formally waived with documented rationale
- 24h sustained observation report committed to docs/reports/
- Signatory: Rick Gillespie, FortressAI Research Institute
- Git commit on main with message: "PQ-SIGNOFF: GAMP5-PQ-SCOPE-001 v1.0"
