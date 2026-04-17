# Runtime Verification Test Protocol (Wallet-Moored)

**Protocol ID**: GF-OQ-RT-001  
**Version**: 1.0  
**Effective Date**: 2026-04-15  
**System**: GaiaFusion v1.0.0-beta.1  
**Regulatory Basis**: GAMP 5, FDA 21 CFR Part 11 §11.200(b), EU Annex 11

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 1. Constitutional Foundation

This system uses **wallet-based cryptographic signatures** for operator authorization and validation attestation.

**21 CFR Part 11 §11.200(b)**: Biometric/token alternatives to username+password are permitted when they provide equivalent security.

**Implementation**:
- **Identity**: Proven by possession of P256 private key
- **Authorization**: Wallet public key mapped to L1/L2/L3 role via `authorized_wallets` collection
- **Non-repudiation**: ECDSA signatures cannot be forged without private key
- **Audit Trail**: Public key + signature + timestamp = cryptographic proof of attestation

**No PII**: Zero usernames, passwords, email addresses, or personal identifiers.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 2. Wallet Authorization Model

| Role | Authorization | Signature Requirement |
|------|---------------|----------------------|
| **L1 Operator** | Monitoring, emergency stop | Single wallet signature |
| **L2 Senior Operator** | L1 + parameter changes, shot initiation | Single wallet signature |
| **L3 Supervisor** | L2 + maintenance, dual-auth approval | Single or dual wallet signature |
| **Founder Wallet** | Perpetual L3 + all permissions | Exempt from licensing, full authority |

**Dual-Auth Actions** (Arm Ignition, Reset Trip):
- Require **two different L3 wallets** (not L2 + L3, not same wallet twice)
- Both signatures recorded in audit trail
- Constitutional firewall enforces wallet distinctness

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 3. Test Cases

### RT-001: Application Launch Stability

**Requirement**: OPER-REQ-001  
**Risk**: HIGH  
**Pass Criteria**: 
- App launches without crash
- Zero `dispatch_assert_queue` console errors
- Process stable for 10+ seconds

**Evidence**: Process ID, console log excerpt, timestamp  
**Wallet Signature**: Test Executor (L2 minimum) signs execution ID + timestamp + "RT-001 PASS"

---

### RT-002: Metal Wireframe Centering

**Requirement**: OPER-REQ-002  
**Risk**: MEDIUM  
**Pass Criteria**: 
- Torus bounding box center within ±5% of viewport center
- No clipping on left/right edges

**Test Mode**: `GAIAFUSION_TEST_MODE=CHECK_2_METAL_CENTER`  
**Evidence**: Screenshot with geometric analysis  
**Wallet Signature**: Test Executor signs SHA-256(screenshot + geometric measurements)

---

### RT-003: Next.js Dashboard Visibility

**Requirement**: OPER-REQ-003  
**Risk**: MEDIUM  
**Pass Criteria**: 
- Right panel visible (width > 400px)
- Cell grid renders (≥ 1 cell visible)
- Plant controls visible

**Test Mode**: `GAIAFUSION_TEST_MODE=CHECK_3_NEXTJS_PANEL`  
**Evidence**: Screenshot, accessibility tree dump  
**Wallet Signature**: Test Executor signs SHA-256(screenshot + accessibility data)

---

### RT-004: Keyboard Shortcut Functionality

**Requirement**: OPER-REQ-004  
**Risk**: LOW  
**Pass Criteria**: 
- Cmd+1: Metal opacity → 10% ±2%
- Cmd+2: Metal opacity → 100% ±2%
- Transition time < 200ms

**Test Mode**: `GAIAFUSION_TEST_MODE=CHECK_4_KEYBOARD_SHORTCUTS`  
**Evidence**: Screenshot before/after, opacity measurements  
**Wallet Signature**: Test Executor signs SHA-256(before/after screenshots + measurements)

---

### RT-005: Tripped State Keyboard Lock

**Requirement**: SAFE-REQ-001  
**Risk**: HIGH (Safety interlock bypass)  
**Pass Criteria**: 
- In `.tripped` state, Cmd+1/Cmd+2 have NO EFFECT
- Mode unchanged for 5+ seconds post-keypress
- Console log confirms "keyboard shortcuts disabled: tripped state"

**Test Mode**: `GAIAFUSION_TEST_MODE=CHECK_5_TRIPPED_LOCK` (auto-forces .tripped after 2s)  
**Evidence**: Screenshot, console log, state machine trace  
**Wallet Signature**: Test Executor signs SHA-256(screenshot + console log + state trace)

---

### RT-006: Constitutional Alarm Response

**Requirement**: SAFE-REQ-002  
**Risk**: HIGH (Regulatory)  
**Pass Criteria**: 
- ConstitutionalHUD visible within 1 second
- Metal opacity locked to 100%
- WKWebView opacity locked to 85%
- Cmd+1/Cmd+2 disabled (no mode change)

**Test Mode**: `GAIAFUSION_TEST_MODE=CHECK_6_CONSTITUTIONAL_ALARM` (auto-forces .constitutionalAlarm after 2s)  
**Evidence**: Screenshot, HUD visibility flag, opacity locks  
**Wallet Signature**: Test Executor signs SHA-256(screenshot + HUD state + opacity locks)

---

### RT-007: Plasma Particle State Dependency

**Requirement**: PHYS-REQ-001  
**Risk**: MEDIUM  
**Pass Criteria**: 
- IDLE state: Particle count = 0
- RUNNING state: Particle count = 500 ±10
- IDLE→RUNNING→IDLE: Buffer cleared and regenerated (not just hidden)

**Test Mode**: `GAIAFUSION_TEST_MODE=CHECK_7_PLASMA_PARTICLES` (auto-transitions IDLE → RUNNING after 3s)  
**Evidence**: Screenshot, particle count, state transition log  
**Wallet Signature**: Test Executor signs SHA-256(screenshot + particle count + state log)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 4. Signature Requirements

### Test Executor Signature (Pre-Execution)

**Meaning**: "I attest that the test environment is prepared per GF-OQ-RT-001 v1.0 and I will execute all 7 test cases."

**Content**: SHA-256(execution_id + protocol_id + system_version + timestamp)

**Requirement**: L2 or L3 wallet

---

### Test Executor Signature (Per Test Case)

**Meaning**: "I attest that test case RT-XXX was executed per protocol and the result is accurate."

**Content**: SHA-256(test_id + result + evidence_hashes)

**Requirement**: Same wallet as pre-execution

---

### Test Executor Signature (Post-Execution)

**Meaning**: "I attest that all tests were executed per protocol GF-OQ-RT-001 v1.0 and results are accurate."

**Content**: SHA-256(test_report + all_screenshots + audit_trail)

**Requirement**: Same wallet as pre-execution

---

### QA Reviewer Signature (Review)

**Meaning**: "I have reviewed all evidence and confirm results meet acceptance criteria."

**Content**: SHA-256(test_report + traceability_matrix + evidence_package)

**Requirement**: L2 or L3 wallet (must be different from Test Executor)

---

### System Owner Signature (Approval)

**Meaning**: "I approve this validation and authorize release per GAMP 5."

**Content**: SHA-256(complete_validation_package)

**Requirement**: L3 wallet or Founder wallet

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 5. Audit Trail Structure

Every validation event recorded with:
- `timestamp`: ISO8601 UTC
- `action`: Event type (TEST_START, SCREENSHOT_CAPTURED, WALLET_SIGNATURE, etc.)
- `wallet_pubkey`: Operator's P256 public key (hex, not username)
- `role`: L1/L2/L3 from `authorized_wallets` collection
- `signature`: ECDSA signature over event digest (hex)
- `founding_wallet`: Boolean (true if Founder wallet)

**No username, no password, no PII** - only cryptographic proof of authority.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 6. Constitutional Firewall Integration

Test execution must respect constitutional boundaries:
- **Dual-auth enforcement**: Two distinct L3 wallets for critical actions
- **Wallet role lookup**: Real-time query to `authorized_wallets` collection
- **Founder bypass**: Founder wallet automatically L3 + exempt from licensing
- **State-driven authorization**: Some actions only allowed in specific plant states

Per `OPERATOR_AUTHORIZATION_MATRIX.md`:
- L1: Monitoring, emergency stop, basic actions
- L2: L1 + parameter changes, shot initiation, plant swap
- L3: L2 + maintenance mode, authorization settings, dual-auth approval

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 7. Evidence Integrity

All evidence files have SHA-256 hashes recorded in audit trail:
- **Screenshots**: Hash captured at creation time
- **Test reports**: Hash signed by Test Executor wallet
- **Audit trail**: Entire JSON signed by Test Executor wallet
- **Traceability matrix**: Hash signed by QA Reviewer wallet

**Chain of custody**: Every signature includes previous evidence hashes, creating immutable chain.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 8. Test Environment

- **Hardware**: Mac (Apple Silicon or Intel)
- **OS**: macOS 13.0+ (Ventura or later)
- **Software**: GaiaFusion v1.0.0-beta.1 (commit ae51b39)
- **Test Mode**: GAIAFUSION_TEST_MODE environment variable
- **Wallet**: P256 private key (Secure Enclave, file, or ephemeral for validation)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 9. Roles and Responsibilities

| Role | Wallet Requirement | Responsibilities |
|------|-------------------|------------------|
| **Test Executor** | L2 or L3 | Execute all test cases, sign results, collect evidence |
| **QA Reviewer** | L2 or L3 (different from Executor) | Review evidence, verify signatures, sign review |
| **System Owner** | L3 or Founder | Final approval, authorize release |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 10. Acceptance Criteria

- All 7 test cases: PASS
- Zero critical deviations
- All evidence collected with SHA-256 hashes
- Test Executor wallet signatures: 9 total (1 pre-exec + 7 test results + 1 post-exec)
- QA Reviewer wallet signature: 1 (different wallet from Executor)
- System Owner wallet signature: 1 (L3 or Founder)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 11. Deviation Handling

- **Minor Deviation** (e.g., screenshot quality): Retest same case, document reason, wallet sign deviation
- **Major Deviation** (e.g., test case failure): Stop execution, root cause analysis, retest all, wallet sign investigation
- **Major Deviation with Safety Impact** (e.g., safety interlock failure): Immediate stop, escalate to System Owner, formal investigation, L3 or Founder wallet required for continuation

All deviations recorded in audit trail with wallet signatures.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 12. Traceability Matrix

| Req ID | Requirement | Risk ID | Risk Level | Test ID | Evidence |
|--------|-------------|---------|------------|---------|----------|
| OPER-REQ-001 | Application launch stability | RISK-001 | HIGH | RT-001 | Console log, Process ID |
| OPER-REQ-002 | 3D viewport centering | RISK-001 | MEDIUM | RT-002 | Screenshot, Geometric analysis |
| OPER-REQ-003 | Dashboard visibility | RISK-002 | MEDIUM | RT-003 | Screenshot, Accessibility tree |
| OPER-REQ-004 | Keyboard shortcut functionality | RISK-003 | LOW | RT-004 | Screenshot, Opacity measurements |
| SAFE-REQ-001 | Safety interlock enforcement | RISK-003 | HIGH | RT-005 | Screenshot, Console log, State trace |
| SAFE-REQ-002 | Constitutional alarm response | RISK-003 | HIGH | RT-006 | Screenshot, HUD visibility, Opacity locks |
| PHYS-REQ-001 | Plasma state dependency | RISK-004 | MEDIUM | RT-007 | Screenshot, Particle count, State log |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 13. Approvals

| Role | Wallet Type | Signature | Date |
|------|-------------|-----------|------|
| **Protocol Author** | IDE Agent | [Electronic] | 2026-04-15 |
| **Test Executor** | L2/L3 Wallet | [Pending Execution] | [Pending] |
| **QA Reviewer** | L2/L3 Wallet (different) | [Pending Review] | [Pending] |
| **System Owner** | L3 or Founder Wallet | [Pending Approval] | [Pending] |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

**Norwich. S⁴ serves C⁴.**
