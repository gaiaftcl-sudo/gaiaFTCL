# Functional Specification — GaiaHealth Biologit Cell
## Document ID: GH-FS-001
## Version: 1.0 | Date: 2026-04-16
## Status: APPROVED FOR VALIDATION
## Owner: Richard Gillespie — FortressAI Research Institute, Norwich CT
## Patents: USPTO 19/460,960 | USPTO 19/096,071
## Framework: GAMP 5 Cat 5 | FDA 21 CFR Part 11 | EU Annex 11 | HIPAA 45 CFR §164 | GDPR Art. 9

---

## 1. Purpose and Scope

This Functional Specification (FS) defines **what** the GaiaHealth Biologit Cell does, establishing the functional requirements that the Design Specification and test suites must satisfy. It is a required GAMP 5 Category 5 lifecycle input, positioned between the User Requirements Specification (URS) and the Design Specification (DS) in the V-model.

**In scope:**
- Molecular dynamics (MD) simulation substrate
- 11-state cell lifecycle machine
- M/I/A epistemic classification of all outputs
- WASM constitutional substrate (8 safety exports)
- Zero-PII sovereign wallet and Owl Protocol identity
- Metal GPU rendering pipeline
- Swift FFI bridge and GxP test harness

**Out of scope:**
- Clinical decision support (GaiaHealth is a research instrument, not a diagnostic device)
- Patient data storage (zero-PII by design — no patient data is ever received)
- Network connectivity (cell operates air-gapped; Owl identity is local secp256k1)

**Related architecture (communion & extended modalities):** **[GH-S4C4-COMM-001](S4_C4_COMMUNION_UI_SPEC.md)** defines the **S4↔C4 Communion UI** vision (multi-modal ingest, C4 invariant registry baselines, projection workbench, epistemic ledger, **vQbit** settlement). It does **not** by itself expand GH-FS-001 functional requirements until adopted by change control; it is the **authoritative design target** for how future instrumentation maps onto `BioligitPrimitive` / **vQbit** closure.

---

## 2. System Overview

GaiaHealth is a **GAMP 5 Category 5 macOS native application** for computational drug discovery. It accepts a molecular structure input (PDB format, PHI-scrubbed), runs a molecular dynamics simulation, and emits a CURE record when a validated binding event is detected. Every computational output carries a mandatory epistemic classification (Measured, Inferred, or Assumed) enforced at the GPU shader level.

**Foundational equation:**
```
small_molecule + protein + MD_substrate → CURE
```
A CURE is only emitted when: binding ΔG is favorable, ADMET criteria are met, epistemic chain contains at least one Measured or Inferred node, all eight WASM constitutional checks pass, and a valid Owl consent record is active.

---

## 3. Functional Requirements

### FR-001 — Cell Lifecycle States

**Requirement:** The system SHALL implement exactly 11 discrete cell states with no intermediate or undefined states permissible.

**States:**

| ID | State | Description |
|----|-------|-------------|
| S-00 | IDLE | Powered on, no target loaded. Entry point and reset state. |
| S-01 | MOORED | Valid Owl identity bound. Consent gate open. |
| S-02 | PREPARED | Force-field parameters validated within specification. |
| S-03 | RUNNING | MD simulation actively executing. |
| S-04 | ANALYSIS | Binding ΔG computation and ADMET evaluation. |
| S-05 | CURE | Terminal success: valid CURE emitted and logged. |
| S-06 | REFUSED | Computation rejected; fault code recorded. |
| S-07 | CONSTITUTIONAL_FLAG | WASM boundary violation; alarm overlay active. |
| S-08 | CONSENT_GATE | Consent required or expired; awaiting operator re-consent. |
| S-09 | TRAINING | Training mode active; no real data, no real CURE. |
| S-10 | AUDIT_HOLD | Regulatory hold; all writes suspended. |

**Acceptance criteria:** The state machine SHALL reject any transition not in the approved transition matrix (FR-002). An invalid transition attempt SHALL return an error and leave state unchanged.

---

### FR-002 — State Transition Enforcement

**Requirement:** The system SHALL enforce the following approved transition matrix. Any attempt to transition via an unapproved path SHALL be rejected with `OwlError::InvalidTransition`.

**Approved transitions (→ indicates valid):**

| From | Approved next states |
|------|---------------------|
| IDLE | MOORED, TRAINING |
| MOORED | IDLE, PREPARED, CONSENT_GATE, REFUSED, AUDIT_HOLD |
| PREPARED | RUNNING, REFUSED, CONSTITUTIONAL_FLAG, IDLE, AUDIT_HOLD |
| RUNNING | ANALYSIS, REFUSED, CONSTITUTIONAL_FLAG, AUDIT_HOLD |
| ANALYSIS | CURE, REFUSED, AUDIT_HOLD |
| CURE | IDLE |
| REFUSED | IDLE |
| CONSTITUTIONAL_FLAG | AUDIT_HOLD |
| CONSENT_GATE | MOORED, REFUSED |
| TRAINING | IDLE |
| AUDIT_HOLD | CONSTITUTIONAL_FLAG |

**Acceptance criteria:** Test series TN-003 (invalid transition IDLE→CURE rejected), StateMachine-TN-001 (IDLE→CURE rejected), StateMachine-TN-002 (REFUSED→RUNNING rejected).

---

### FR-003 — Epistemic Classification

**Requirement:** Every computational output SHALL carry one of three mandatory epistemic tags. No output SHALL be presented without its tag. The tag SHALL be enforced at the Metal GPU shader level, not only in application logic.

| Tag | Value | Meaning | Metal Pipeline | Alpha |
|-----|-------|---------|----------------|-------|
| Measured (M) | 0 | Directly measured (ITC, SPR, NMR, X-ray) | m_pipeline | 1.0 (opaque) |
| Inferred (I) | 1 | Computed from validated model (MD, AutoDock) | i_pipeline | 0.6 (translucent) |
| Assumed (A) | 2 | Literature value or unvalidated estimate | a_pipeline | 0.3 (stippled) |

**Acceptance criteria:**
- Epistemic-TP-003: Measured → alpha = 1.0
- Epistemic-TP-004: Inferred → alpha = 0.6
- Epistemic-TP-005: Assumed → alpha = 0.3
- Epistemic-TC-001: CURE unreachable from Assumed-only chain

---

### FR-004 — CURE Emission Conditions

**Requirement:** The system SHALL only emit a CURE when ALL of the following conditions are simultaneously satisfied:

| Condition | Specification |
|-----------|--------------|
| C-1 | `epistemic_tag` ∈ {Measured, Inferred} — Assumed-only SHALL block CURE |
| C-2 | `binding_dg` < 0.0 kcal/mol (favorable binding) |
| C-3 | `admet_score` ≥ 0.5 |
| C-4 | `sim_time_ns` ≥ 10.0 (minimum simulation duration) |
| C-5 | All 8 WASM constitutional exports return valid/pass |
| C-6 | `ConsentRecord.is_valid(now_ms)` = true (within 5-minute window) |
| C-7 | `selectivity_ratio` passes `selectivity_check()` |

**Acceptance criteria:** StateMachine-TP-002 (full CURE path), StateMachine-TC-001 (CURE requires M or I), Constitutional-TC-001 through TC-016.

---

### FR-005 — Zero-PII Wallet Mandate

**Requirement:** The sovereign wallet SHALL contain no personally identifiable information of any kind. The following are categorically prohibited from the wallet file:

- Names (any form)
- Email addresses
- Dates of birth
- Social Security Numbers or equivalent national identifiers
- Medical Record Numbers
- Patient identifiers
- Insurance identifiers
- Postal addresses
- Phone numbers
- IP addresses
- Device names linkable to persons
- Any string a human would recognize as belonging to a specific individual

**Wallet SHALL contain only:**
- `cell_id`: SHA-256(hw_uuid | entropy | timestamp)
- `wallet_address`: "gaiahealth1" + hex(SHA-256(entropy | cell_id))[0..38]
- `private_entropy`: 32 bytes cryptographic random
- `generated_at`: UTC ISO 8601 timestamp
- `pii_stored`: false (machine-readable assertion)
- Curve and derivation metadata

**Acceptance criteria:**
- Wallet-TN-001: 14 PHI patterns absent from wallet JSON
- Wallet-TP-003: `pii_stored` = false
- Wallet-TP-001: address starts with `gaiahealth1`
- Wallet-IQ-002: file mode = 0600

---

### FR-006 — Owl Protocol Identity

**Requirement:** The system SHALL require a valid Owl identity (secp256k1 compressed public key) to enter MOORED state. The identity SHALL be validated as follows:
- Exactly 66 hexadecimal characters
- Prefix: "02" or "03" (compressed point)
- Any non-hex string (including email addresses, names, national IDs) SHALL cause transition to REFUSED

**Consent window:** Consent records SHALL expire after exactly 300,000 milliseconds (5 minutes). Expired consent SHALL trigger transition to CONSENT_GATE.

**Acceptance criteria:**
- BioState-TP-006: valid pubkey accepted
- BioState-TN-001: email rejected → REFUSED
- BioState-TN-002: name rejected → REFUSED
- Constitutional-TC-010: consent valid within 5 min
- Constitutional-TC-011: consent expired after 5 min

---

### FR-007 — Force Field Parameter Validation

**Requirement:** The system SHALL validate all MD simulation parameters before permitting PREPARED→RUNNING transition. Out-of-range parameters SHALL prevent transition to RUNNING.

| Parameter | Valid Range | Unit |
|-----------|-------------|------|
| Temperature | 250.0 – 450.0 | Kelvin |
| Pressure | 0.5 – 500.0 | bar |
| Timestep | 0.5 – 4.0 | femtoseconds |
| Simulation time | ≥ 10.0 | nanoseconds |
| Water box padding | ≥ 10.0 | Ångstroms |
| Force field | AMBER, CHARMM, OPLS, GROMOS | — |

**Acceptance criteria:**
- Constitutional-TC-012: valid params pass
- Constitutional-TC-013: temperature > 450K rejected

---

### FR-008 — WASM Constitutional Substrate

**Requirement:** The system SHALL implement exactly 8 WASM exports that run inside a WKWebView sandbox. All 8 SHALL be callable before CURE emission. Absence of any export SHALL block OQ sign-off.

| Export | Function |
|--------|----------|
| `binding_constitutional_check` | Thermodynamic plausibility of binding ΔG |
| `admet_bounds_check` | Lipinski Rule of Five + ADMET thresholds |
| `phi_boundary_check` | PHI leakage detection in output strings |
| `epistemic_chain_validate` | M/I/A chain permits CURE |
| `consent_validity_check` | Owl consent within 5-minute window |
| `force_field_bounds_check` | MD parameters within physiological range |
| `selectivity_check` | Target vs. off-target selectivity ratio |
| `get_epistemic_tag` | Returns canonical M/I/A for a data source type |

**Acceptance criteria:** Constitutional-TC-001 through TC-016 (16 tests covering all 8 exports).

---

### FR-009 — PHI Scrubbing of Molecular Input

**Requirement:** The PDB parser SHALL strip all AUTHOR and REMARK records from input files before any field is parsed into a BioligitPrimitive. The parser SHALL additionally scan for and reject files containing recognizable PHI patterns:
- SSN: `\d{3}-\d{2}-\d{4}`
- Email: `@` with surrounding text
- MRN keywords: "MRN", "mrn", "patient"
- Date of birth patterns: MM/DD/YYYY, YYYY-MM-DD
- Phone: `\d{3}[.-]\d{3}[.-]\d{4}`

**Acceptance criteria:** `parse_pdb()` unit tests in `biologit_usd_parser`.

---

### FR-010 — Electronic Records Integrity (21 CFR Part 11)

**Requirement:** The system SHALL comply with FDA 21 CFR Part 11 for electronic records. Specifically:

- Metal renderer SHALL issue `MTLLoadActionClear` on every frame (no ghost artifacts)
- The application SHALL enforce single-window lock while in RUNNING, ANALYSIS, or CURE state (no split views)
- CURE audit log entries SHALL use Owl pubkey hash (SHA-256) only — never raw pubkey, never name
- All evidence receipts SHALL be written contemporaneously at the time of qualification execution
- AUDIT_HOLD state SHALL suspend all writes to the audit log

**Acceptance criteria:** Renderer RG-006 (vertex stride constant), WalletTests (14 PHI patterns absent from all log entries).

---

### FR-011 — Training Mode Isolation

**Requirement:** When `training_mode = true`, the system SHALL:
- Process no real biological data
- Emit no real CURE records
- Label all outputs with `training_mode: true`
- Allow all state transitions to function normally for test purposes
- Write training-mode receipts to `evidence/testrobit_receipt.json`

**Acceptance criteria:** TestRobit runs entirely in training_mode=true. Receipt contains `"training_mode": true`.

---

### FR-012 — Performance Qualification Target (PQ)

**Requirement:** In PQ mode (`training_mode = false`), the system SHALL compute binding ΔG for a novel molecular target within **±1 kcal/mol** of the experimentally measured value from peer-reviewed literature.

**PQ acceptance criteria:**
- Protein structure: validated PDB entry, resolution ≤ 2.5 Å
- Experimental reference: peer-reviewed ITC, SPR, or fluorescence polarisation measurement
- Simulation: ≥ 100 ns, force field from approved list
- Epistemic tag: Measured or Inferred
- Delta: |ΔG_computed − ΔG_literature| ≤ 1.0 kcal/mol

---

## 4. Non-Functional Requirements

### NFR-001 — Platform
- macOS ≥ 14.0 (Sonoma)
- Apple Silicon (M-chip, unified memory)
- Metal GPU present and accessible

### NFR-002 — Performance
- IQ script SHALL complete in < 5 minutes on a standard M2 Mac
- Rust GxP tests SHALL complete in < 60 seconds
- Swift TestRobit SHALL complete in < 120 seconds
- Single MD frame rendering SHALL complete in < 16 ms (≥ 60 fps)

### NFR-003 — Data Integrity
- All evidence receipts SHALL be JSON (UTF-8, ALCOA+ compliant)
- All wallet files SHALL be mode 0600 (owner read-only)
- No evidence file SHALL be overwritten without explicit operator confirmation

### NFR-004 — Regulatory
- Wallet SHALL include `"pii_stored": false`
- All audit entries SHALL reference `owl_pubkey_hash` (SHA-256), never raw pubkey
- CONSTITUTIONAL_FLAG state SHALL display alarm overlay within 1 render frame of transition

---

## 5. Functional Requirements → Test Mapping

| Requirement | Test Series | Test IDs |
|-------------|------------|----------|
| FR-001 (11 states) | StateMachine-TP | TP-001 through TP-008 |
| FR-002 (transitions) | StateMachine-TN, TC | TN-001, TN-002, TC-001 through TC-006 |
| FR-003 (epistemic tags) | Epistemic-TP, TC | TP-003, TP-004, TP-005, TC-001 |
| FR-004 (CURE conditions) | StateMachine-TP, TC | TP-002, TP-005, TP-006, TC-001 |
| FR-005 (zero-PII wallet) | Wallet-IQ, TP, TN, RG | IQ-001 through IQ-004, TP-001 through TP-003, TN-001, TN-002, RG-001 |
| FR-006 (Owl identity) | BioState-TP, TN | TP-005, TP-006, TN-001, TN-002 |
| FR-007 (force field) | Constitutional-TC | TC-012, TC-013 |
| FR-008 (WASM exports) | Constitutional-TC | TC-001 through TC-016 |
| FR-009 (PHI scrub) | biologit_usd_parser unit tests | parser.rs tests |
| FR-010 (21 CFR Pt 11) | Wallet-TN, Renderer-RG | TN-001, RG-006 |
| FR-011 (training mode) | All suites (training_mode=true) | All 58 TestRobit tests |
| FR-012 (PQ target) | PQ execution | pq_receipt.json |

---

## 6. Traceability to URS

| URS Requirement | FS Requirement(s) |
|----------------|-------------------|
| System shall simulate molecular dynamics | FR-001 (RUNNING state), FR-007 (force field) |
| System shall emit CURE for validated binding | FR-004 (CURE conditions) |
| System shall classify all outputs epistemically | FR-003 (M/I/A tags) |
| System shall store zero personal information | FR-005 (zero-PII wallet), FR-009 (PHI scrub) |
| System shall enforce constitutional safety boundaries | FR-008 (WASM substrate) |
| System shall comply with FDA 21 CFR Part 11 | FR-010 (electronic records) |
| System shall support training/testing mode | FR-011 (training mode) |
| System shall be qualifiable under GAMP 5 | FR-001 through FR-012 (full lifecycle) |

**URS reference:** `PatentInfo/GaiaHealth UI Requirements Review.docx` + `GaiaHealth_UI_Requirements_Review_ZeroPII.docx`

---

## 7. Document Control

| Version | Date | Author | Change |
|---------|------|--------|--------|
| 1.0 | 2026-04-16 | R. Gillespie | Initial release — covers all implemented requirements |

**Next review due:** Upon any change to FR-001 through FR-012, or prior to PQ execution.

**Sign-off required before OQ execution.** This document constitutes the functional baseline against which OQ test results are evaluated.
