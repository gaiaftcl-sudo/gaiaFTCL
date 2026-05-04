# GAMP5-OQ-EVIDENCE-003: Quantum vQbit OQ Evidence
## Version 1.0

**Instrument:** vQbit VM — UUM-8D M⁸ = S⁴ × C⁴ measurement substrate
**Protocol Reference:** GAMP5-OQ-PROTOCOL-003 v1.0
**Protocol Seal SHA:** `eb13e914` (OQ-SIGNOFF: GAMP5-OQ-PROTOCOL-003 v1.0)

---

## Evidence Status

**Status: PENDING LIVE EXECUTION**

The OQ-QM-001 through OQ-QM-007 tests require the following three-service stack
running concurrently on a Mac cell (macOS 26+):

1. `nats-server -p 4222` — vQbit NATS broker
2. `nats-server -p 4223` — Franklin NATS broker
3. `swift run VQbitVM` — sovereign VM (wait for `vm.ready` log line)
4. `swift run FranklinConsciousnessService` — wait for `gaiaftcl.franklin.stage.moored`

Then execute each test in order (stop on first failure):

```bash
cd cells/xcode
swift run QuantumOQInjector --ping
swift run QuantumOQInjector --mooring-status
swift run QuantumOQInjector --test OQ-QM-001
swift run QuantumOQInjector --test OQ-QM-002
swift run QuantumOQInjector --test OQ-QM-003
swift run QuantumOQInjector --test OQ-QM-004
swift run QuantumOQInjector --test OQ-QM-005
swift run QuantumOQInjector --test OQ-QM-006
swift run QuantumOQInjector --test OQ-QM-007
```

Paste each test's console output into this document below the corresponding test
heading. On any FAIL, stop and create `GAMP5-DEVIATION-DEV-QM-00N.md`.

---

## Test Results (to be populated during live execution)

### OQ-QM-001 — Canonical M⁸ State Injection
**Pass criterion:** terminal byte ∈ {0x01, 0x02, 0x03, 0x04} per state × 3 runs

```
[PENDING — paste console output here]
```
**Adjudication:** PENDING

### OQ-QM-002 — S_mean Degradation Sequence
**Pass criterion:** c3_closure[i+1] ≤ c3_closure[i] ∀ i; sequence CALORIE→CURE→REFUSED→BLOCKED

```
[PENDING — paste console output here]
```
**Adjudication:** PENDING

### OQ-QM-003 — CURE State Stability
**Pass criterion:** |S₈_final − S₈_initial| / S₈_initial < 0.05 after one Franklin cycle

```
[PENDING — paste console output here]
```
**Adjudication:** PENDING

### OQ-QM-004 — Identical Terminal Byte for Low S_mean
**Pass criterion:** CircuitFamily and Tokamak prims produce identical terminal byte

```
[PENDING — paste console output here]
```
**Adjudication:** PENDING

### OQ-QM-005 — Post-Improvement c3_closure Increase
**Pass criterion:** post_c3_closure > prior_c3_closure; domain_improvement receipt written

```
[PENDING — paste console output here]
```
**Adjudication:** PENDING

### OQ-QM-006 — S_mean Ascending Sequence
**Pass criterion:** c3_closure[i+1] ≥ c3_closure[i] ∀ i

```
[PENDING — paste console output here]
```
**Adjudication:** PENDING

### OQ-QM-007 — Full Stack Sovereignty Check
**Pass criterion:** SUM(algorithm_count) = 19; closureResidual < 0.05; N_residual = 0

```
[PENDING — paste console output here]
```
**Adjudication:** PENDING

---

## Evidence Seal

*To be completed after all 7 tests PASS with no deviations.*

```
Statement: All OQ-QM-001 through OQ-QM-007 PASS under GAMP5-OQ-PROTOCOL-003 v1.0.
           No deviations recorded.

Signatory: Rick Gillespie, Founder and CEO, FortressAI Research Institute
Date: [ISO date of seal commit, UTC]
Evidence Seal SHA: [SHA of OQ-SIGNOFF: GAMP5-OQ-EVIDENCE-003 v1.0 commit]
```

*Two-commit seal required per GAMP5 protocol: (1) evidence document commit,
(2) `OQ-SIGNOFF: GAMP5-OQ-EVIDENCE-003 v1.0` commit — no amend.*
