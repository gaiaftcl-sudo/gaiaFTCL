# Requirements Traceability Matrix

**Document**: RTM-GAMP5-001  
**Version**: 1.0.0  
**Date**: 2026-04-15  
**Author**: FortressAI Research Institute  
**Patent**: USPTO 19/460,960 | USPTO 19/096,071

## Purpose

This Requirements Traceability Matrix (RTM) provides bidirectional traceability between:
- System Requirements (what the system must do)
- Test Cases (how requirements are verified)
- Evidence Artifacts (proof of verification)

Required for GAMP 5 Category 5 validation (custom-developed software).

## Traceability Structure

```
Requirement → Test(s) → Evidence
```

All requirements must be:
- **Tested**: Covered by at least one test case
- **Verified**: Evidence of test execution documented
- **Traceable**: Clear path from requirement to evidence

## System Requirements

### Functional Requirements

| Req ID | Description | Priority | Test Case(s) | Evidence |
|--------|-------------|----------|--------------|----------|
| FR-001 | System shall support IDLE, MOORED, RUNNING, TRIPPED, CONSTITUTIONAL_ALARM, MAINTENANCE, TRAINING operational states | HIGH | RT-002, SP-004, SafetyProtocolTests.testValidStateTransitions | RT visual checks, SP-004 log, SafetyProtocolTests results |
| FR-002 | System shall enforce valid state transitions per state machine | HIGH | SafetyProtocolTests.testValidStateTransitions, SafetyProtocolTests.testInvalidStateTransitions | SafetyProtocolTests results |
| FR-003 | System shall display Metal-rendered fusion plant geometry | HIGH | RT-002 | RT-002 screenshot |
| FR-004 | System shall display Next.js dashboard with telemetry | HIGH | RT-003 | RT-003 screenshot |
| FR-005 | System shall support Cmd+1 (dashboard mode) and Cmd+2 (geometry mode) keyboard shortcuts | MEDIUM | RT-004 | RT-004 visual confirmation |
| FR-006 | System shall disable keyboard shortcuts in RUNNING, TRIPPED, CONSTITUTIONAL_ALARM states | HIGH | RT-005, SafetyProtocolTests.testAbnormalStateLockdown | RT-005 visual confirmation, SafetyProtocolTests results |
| FR-007 | System shall display ConstitutionalHUD in CONSTITUTIONAL_ALARM state | HIGH | RT-006 | RT-006 screenshot |
| FR-008 | System shall clear plasma particles when not in RUNNING state | MEDIUM | RT-007 | RT-007 visual confirmation |

### Safety Requirements (Constitutional)

| Req ID | Description | Priority | Test Case(s) | Evidence |
|--------|-------------|----------|--------------|----------|
| SAFETY-001 | System shall maintain RUNNING state continuously (operational baseline) | CRITICAL | SP-001 | SP-001 continuous baseline log (4+ hours) |
| SAFETY-002 | System shall transition to TRIPPED/CONSTITUTIONAL_ALARM after 1 hour without mesh connectivity (designed death) | CRITICAL | SP-002, SafetyProtocolTests.testMooringDegradationRealInfrastructure | SP-002 log, state.json, SafetyProtocolTests results |
| SAFETY-003 | System shall disable UI actions in abnormal states (TRIPPED, CONSTITUTIONAL_ALARM) | HIGH | SP-003, SafetyProtocolTests.testAbnormalStateLockdown | SP-003 log, SafetyProtocolTests results |
| SAFETY-004 | System shall start in IDLE state on clean launch | HIGH | SP-004, SafetyProtocolTests.testDefaultStateVerification | SP-004 log, SafetyProtocolTests results |
| SAFETY-005 | System shall detect SubGame Z quorum loss (5 of 9 cells) and trigger diagnostic eviction | MEDIUM | SP-005 (manual) | SP-005 log (manual execution before CERN handoff) |

### Mesh Requirements

| Req ID | Description | Priority | Test Case(s) | Evidence |
|--------|-------------|----------|--------------|----------|
| MESH-REQ-001 | System shall monitor NATS connectivity for mesh liveness | HIGH | SafetyProtocolTests.testMooringDegradationRealInfrastructure | SafetyProtocolTests results, state.json |
| MESH-REQ-002 | Cell dies when mesh connectivity lost (designed death, not resilience) — survival is a bug | CRITICAL | SP-002, SafetyProtocolTests.testMooringDegradationRealInfrastructure | SP-002 log, state.json with `mooringDegradationOccurred=true`, SafetyProtocolTests results |
| MESH-REQ-003 | System shall write machine-readable state.json on every state transition | HIGH | SafetyProtocolTests.testStateFileWriting | SafetyProtocolTests results, state.json file |

### Authorization Requirements

| Req ID | Description | Priority | Test Case(s) | Evidence |
|--------|-------------|----------|--------------|----------|
| AUTH-001 | System shall support L1, L2, L3 operator authorization levels | HIGH | (Future: AuthorizationTests) | Pending implementation |
| AUTH-002 | Critical actions (Arm Ignition, Reset Trip) shall require dual authorization | HIGH | (Future: AuthorizationTests) | Pending implementation |
| AUTH-003 | System shall use wallet-based cryptographic signatures (not username/password) | MEDIUM | (Implemented, tests pending) | Wallet signature CLI output schema |

### Performance Requirements

| Req ID | Description | Priority | Test Case(s) | Evidence |
|--------|-------------|----------|--------------|----------|
| PERF-001 | System startup time shall be < 2 seconds | MEDIUM | PQ startup profiler | PQ performance log |
| PERF-002 | Frame time shall remain stable over extended operation | MEDIUM | SP-001 continuous baseline | SP-001 frame time log |
| PERF-003 | Memory usage shall not leak > 50 MB/hour | MEDIUM | SP-001 continuous baseline | SP-001 memory usage log |

## Non-Functional Requirements

### Validation Requirements (GAMP 5)

| Req ID | Description | Priority | Test Case(s) | Evidence |
|--------|-------------|----------|--------------|----------|
| VAL-001 | System shall generate cryptographically chained phase receipts | HIGH | Master orchestrator receipt generation | Receipt JSON files with SHA-256 chaining |
| VAL-002 | System shall generate self-contained HTML evidence report | MEDIUM | generate_html_evidence_report.py | HTML report file |
| VAL-003 | System shall provide wallet-based electronic signatures for all validation phases | HIGH | (Pending: gaiafusion-sign-cli integration) | Wallet signature JSON envelopes |

## Test Coverage Summary

| Category | Total Requirements | Tested | Coverage |
|----------|-------------------|--------|----------|
| Functional | 8 | 8 | 100% |
| Safety (Constitutional) | 5 | 5 | 100% |
| Mesh | 3 | 3 | 100% |
| Authorization | 3 | 0 | 0% (future) |
| Performance | 3 | 3 | 100% |
| Validation | 3 | 2 | 67% (sign-CLI pending) |
| **TOTAL** | **25** | **21** | **84%** |

## Evidence Artifacts Index

### Phase Evidence

| Phase | Evidence Files | Location |
|-------|----------------|----------|
| IQ | iq_install_log.txt, iq_verification.json | evidence/ |
| OQ | oq_build_log.txt, oq_functional_tests.json | evidence/ |
| RT | rt_visual_checks.log, screenshots/rt_*.png | evidence/, evidence/screenshots/ |
| SP-001 | sp-001_continuous_baseline.log, sp-001_frame_times.log, sp-001_memory_usage.log | evidence/ |
| SP-002 | sp-002_log.txt, state.json | evidence/, ~/Library/Application Support/GaiaFusion/ |
| SP-003 | sp-003_log.txt | evidence/ |
| SP-004 | sp-004_log.txt | evidence/ |
| SP-005 | sp-005_log.txt (manual) | evidence/ |
| PQ | pq_performance_log.txt, pq_test_results.json | evidence/ |

### Test Results

| Test Suite | Results File | Location |
|------------|--------------|----------|
| SafetyProtocolTests | XCTest results | Xcode test navigator / CI logs |

### Configuration

| File | Purpose | Location |
|------|---------|----------|
| testrobot.toml | Master configuration | config/ |
| mesh.toml | Mesh liveness configuration | config/ |

## Requirement Status Legend

- ✅ **COMPLETE**: Requirement tested, evidence documented
- ⏳ **PENDING**: Requirement specified, implementation/test in progress
- ❌ **NOT STARTED**: Requirement identified, no implementation

## Change Control

All changes to requirements or test cases must:
1. Update this RTM document
2. Document rationale in change log
3. Re-execute affected tests
4. Update evidence artifacts

## Approval

| Role | Name | Signature | Date |
|------|------|-----------|------|
| QA Lead | (Pending) | (Pending wallet signature) | 2026-04-XX |
| Technical Lead | (Pending) | (Pending wallet signature) | 2026-04-XX |
| Project Owner | Richard Gillespie | (Pending wallet signature) | 2026-04-XX |

---

**FortressAI Research Institute**  
Norwich, Connecticut  
USPTO 19/460,960 | USPTO 19/096,071  
© 2026 All Rights Reserved
