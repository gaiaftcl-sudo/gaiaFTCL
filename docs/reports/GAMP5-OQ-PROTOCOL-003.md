# GAMP5-OQ-PROTOCOL-003: Quantum vQbit OQ Protocol
## Version 1.0

**Instrument:** vQbit VM — UUM-8D M⁸ = S⁴ × C⁴ measurement substrate
**Protocol ID:** GAMP5-OQ-PROTOCOL-003
**Prerequisite:** GAMP5-VQBIT-QUANTUM-IQ-OQ-PQ-001.md committed at e84f43f7

## OQ Tests — Pass/Fail Criteria

**OQ-QM-001:** Inject 4 canonical M⁸ states into /World/Quantum/ProjectionProbe.
Pass: terminal byte matches {0x01, 0x02, 0x03, 0x04} per state × 3 runs.

**OQ-QM-002:** Inject s_mean degrading 0.9→0.1 in 9 steps.
Pass: c3_closure[i+1] ≤ c3_closure[i] for all i. Sequence CALORIE→CURE→REFUSED→BLOCKED.

**OQ-QM-003:** Inject CURE state (s1=0.65, s2=0.70, s3=0.60, s4=0.72).
Pass: |S₈_final - S₈_initial| / S₈_initial < 0.05 after one Franklin cycle.

**OQ-QM-004:** Inject s_mean=0.15 into CircuitFamily and Tokamak prims.
Pass: both produce identical terminal byte. violation_code MAY differ.

**OQ-QM-005:** Inject s_mean=0.3 for QC-CIRCUIT-001 prim.
Pass: post_c3_closure > prior_c3_closure. GRDB domain_improvement receipt written.

**OQ-QM-006:** Inject s_mean ascending 0.1→0.9 in 9 steps.
Pass: c3_closure[i+1] ≥ c3_closure[i] for all i.

**OQ-QM-007:** Start all three services. Franklin wakes and authors all prims.
Pass: SUM(algorithm_count) over 6 quantum family rows = 19. N_residual = 0.
      closureResidual < 0.05. ProjectionProbe excluded from N_catalog count.

## Deviation procedure
Per GAMP5-DEVIATION-PROCEDURE-001.md. Stop at first failure.
DEV-QM-001 through DEV-QM-N for any failure.

## Signing definition
Signatory: Rick Gillespie, Founder and CEO, FortressAI Research Institute
Act: Git commit of GAMP5-OQ-EVIDENCE-003.md on main branch
Commit 2 message must contain: "OQ-SIGNOFF: GAMP5-OQ-PROTOCOL-003 v1.0"
Timestamp: git commit timestamp UTC
Hash: git commit SHA embedded in evidence document
No amend. No feature branch. Two commits exactly.
