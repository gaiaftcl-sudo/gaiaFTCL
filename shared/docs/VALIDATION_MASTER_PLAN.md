# Validation Master Plan — FoT8D Cell Framework
## Document ID: FoT8D-VMP-001
## Version: 1.0 | Date: 2026-04-16
## Status: APPROVED
## Owner: Richard Gillespie — FortressAI Research Institute, Norwich CT
## Patents: USPTO 19/460,960 | USPTO 19/096,071
## Framework: GAMP 5 Cat 5 | FDA 21 CFR Part 11 | EU Annex 11 | ICH E6

---

## 1. Purpose

This Validation Master Plan (VMP) defines the overall validation strategy, scope, responsibilities, and lifecycle for all computerized systems developed under the FoT8D Cell Framework. It is the governing document for GAMP 5 Category 5 validation activities across all cells.

Systems covered by this VMP:
- **GaiaFTCL** — Fusion Cell (plasma physics, `vQbitPrimitive`, `gaia1` wallet)
- **GaiaHealth** — Biologit Cell (molecular dynamics, `BioligitPrimitive`, `gaiahealth1` wallet)

Future cells developed under `FoT8D/` SHALL reference this VMP.

---

## 2. Regulatory Framework

| Standard | Applicability |
|----------|--------------|
| GAMP 5 (2nd Ed., 2022) | Primary validation framework — Category 5 custom software |
| FDA 21 CFR Part 11 | Electronic records and electronic signatures |
| EU Annex 11 | Computerised systems in GMP environments (CERN) |
| ICH E6 (R2) | Good Clinical Practice — applicable to research outputs used in clinical context |
| HIPAA 45 CFR §164 | Protected Health Information — zero-PII architecture is the compliance mechanism |
| GDPR Article 9 | Special category health data — zero-collection architecture |
| ISO 27001 | Information security management — wallet and audit trail security |
| ALCOA+ | Data integrity principles governing all evidence: Attributable, Legible, Contemporaneous, Original, Accurate + Complete, Consistent, Enduring, Available |

---

## 3. GAMP 5 Category Determination

Both GaiaFTCL and GaiaHealth are **GAMP 5 Category 5 — Custom Software**:

- They are fully custom-developed (not COTS, not configured products)
- They generate electronic records used in regulated research contexts
- They implement complex algorithms (plasma physics / molecular dynamics) that directly produce scientific outputs
- They require full V-model lifecycle validation: URS → FS → DS → IQ → OQ → PQ

Category determination is documented separately for each cell (see cell-specific FS documents).

---

## 4. Validation V-Model

```
    URS                                          PQ
   (User Req.)                              (Performance)
      │                                          │
      ▼                                          ▲
      FS                                        OQ
  (Functional Spec)                     (Operational Qual.)
      │                                          │
      ▼                                          ▲
      DS                                        IQ
  (Design Spec)                         (Installation Qual.)
      │                                          │
      └──────────── Code & Build ────────────────┘
```

**Left side** (specifications) must be authored and approved before executing corresponding **right side** (qualification). Code changes after IQ require re-execution of affected qualification phases.

---

## 5. Document Hierarchy

| Document | ID | Owner | Required Before |
|----------|----|-------|----------------|
| Validation Master Plan | FoT8D-VMP-001 | R. Gillespie | All validation activity |
| User Requirements Specification | GH-URS-001 (GaiaHealth) | R. Gillespie | FS authoring |
| Functional Specification | GH-FS-001 (GaiaHealth) | R. Gillespie | DS authoring, OQ sign-off |
| Design Specification | GH-DS-001 (GaiaHealth) | R. Gillespie | Code review, IQ |
| Requirements Traceability Matrix | GH-RTM-001 (GaiaHealth) | R. Gillespie | OQ sign-off |
| Code Review Records | GH-CRR-001 (GaiaHealth) | L3 Reviewer | IQ sign-off |
| IQ Protocol & Receipt | GH-IQ-001 | R. Gillespie | OQ execution |
| OQ Protocol & Receipt | GH-OQ-001 | R. Gillespie | PQ execution |
| PQ Protocol & Receipt | GH-PQ-001 | R. Gillespie | System release |

Same hierarchy applies to GaiaFTCL (replace GH- prefix with GFTCL-).

---

## 6. Shared Infrastructure

The following components are shared between all cells and validated once:

| Component | Location | Validation Status |
|-----------|----------|------------------|
| `SovereignWallet` | `shared/wallet_core/` | Validated via each cell's IQ + WalletTests |
| `OwlPubkey` / `ConsentRecord` | `shared/owl_protocol/` | Validated via each cell's IQ + Constitutional tests |
| `GxpTestSuite` trait | `shared/gxp_harness/` | Validated as part of each cell's OQ harness |

Shared components do not require separate validation — they are validated in the context of each consuming cell. Changes to shared components trigger re-validation of all cells that consume them.

---

## 7. Test Series Naming Convention

All cells under this VMP SHALL use the following canonical test series identifiers:

| Series | Name | Scope |
|--------|------|-------|
| IQ | Installation Qualification Guards | Compilation, environment, identity |
| TP | True Positive / Positive Path | Valid inputs → correct outputs |
| TN | True Negative / Rejection | Invalid inputs → correct rejection |
| TR | Type/Layout Regression | ABI struct layout, stride constants |
| TC | Constitutional/Compliance | Safety boundaries, consent, PHI |
| TI | Integration | End-to-end FFI bridge |
| RG | Regression Guards | Permanent ABI and behavior locks |

Test IDs follow format: `{SERIES}-{NNN}` (e.g., `TP-001`, `TC-012`).
Suite-level IDs for Swift harness: `{SuiteName}-{SERIES}-{NNN}` (e.g., `BioState-TP-001`).

This convention is binding for all cells. Introducing new test series requires VMP amendment.

---

## 8. Evidence Package Standard

All qualification phases SHALL produce evidence in the following format:

### 8.1 JSON Receipt (machine-readable, primary record)

Required fields for all receipts:
```json
{
  "phase": "<IQ|OQ|PQ>",
  "cell": "<cell name>",
  "gamp_category": 5,
  "timestamp": "<ISO 8601 UTC>",
  "operator_pubkey_hash": "<SHA-256 of Owl pubkey — not raw pubkey>",
  "pii_stored": false,
  "status": "<PASS|FAIL>"
}
```

Phase-specific additional fields are defined in each cell's IQ/OQ/PQ wiki pages.

### 8.2 ALCOA+ Compliance Attestation

Every receipt SHALL be:
- **Attributable**: `operator_pubkey_hash` field links to Owl identity
- **Legible**: Human-readable JSON with descriptive field names
- **Contemporaneous**: `timestamp` written at execution time, not retroactively
- **Original**: First write only; receipts are never overwritten (append-only evidence folder)
- **Accurate**: Automated extraction from test runner output — no manual transcription

### 8.3 Evidence Folder Structure

```
{cell}/evidence/
├── iq_receipt.json          # Written by iq_install.sh
├── testrobit_receipt.json   # Written by Swift TestRobit (OQ)
└── pq_receipt.json          # Written by operator during PQ
```

Evidence folders are excluded from `.gitignore` by design — receipts are committed as part of the validation record.

---

## 9. Zero-PII Principle

**This VMP mandates zero-PII architecture for all cells.** No cell under this VMP SHALL collect, store, transmit, or process personally identifiable information of any kind.

Compliance mechanism:
1. Wallet provisioning via entropy only (no personal prompts)
2. Owl identity as secp256k1 pubkey (no name or email)
3. Audit trail uses pubkey hashes (SHA-256), never raw pubkeys or names
4. PDB input PHI-scrubbed before parsing
5. WASM `phi_boundary_check()` scans all output strings
6. WalletTests suite asserts 14 PHI patterns absent from all wallet content

Any future cell proposing to handle personal data requires a separate Privacy Impact Assessment and VMP amendment before development begins.

---

## 10. Change Control

### 10.1 What Constitutes a Change

Any modification to validated code, configuration, or infrastructure is a change requiring assessment:
- Source code changes in any validated crate
- Dependency version upgrades (Cargo.lock changes)
- MSL shader changes
- WASM export behavior changes
- Operating system major version upgrade
- Hardware replacement
- Owl key rotation

### 10.2 Change Classification

| Class | Description | Re-validation Required |
|-------|-------------|----------------------|
| Major | ABI change, new state, new WASM export | Full IQ → OQ → PQ |
| Minor | Bug fix, performance optimization, documentation | OQ → PQ |
| Administrative | Comment, formatting, non-functional change | Documented only, no re-validation |

### 10.3 Change Process

1. Author documents proposed change with rationale
2. Change classified by owner (R. Gillespie)
3. Affected qualification phases re-executed
4. New receipts written and committed
5. VMP amendment if required

---

## 11. Periodic Review

Validated systems SHALL be reviewed annually or upon any of the following triggers:

- macOS major version release
- Rust edition change
- objc2-metal major version change
- wasm-bindgen major version change
- New CERN or FDA guidance materially affecting the regulatory basis
- Any production incident affecting data integrity

**Periodic review record:** Written to `evidence/periodic_review_{YYYY}.json` following the same ALCOA+ receipt format.

---

## 12. Roles and Responsibilities

| Role | Person | Responsibility |
|------|--------|---------------|
| System Owner | Richard Gillespie | Approves all validation documents; signs IQ/OQ/PQ receipts via Owl pubkey |
| Development Lead | Richard Gillespie | Authors code, DS, and FS; executes IQ/OQ |
| L3 Reviewer | TBD — independent qualified person | Reviews DS and CRR; counter-signs before IQ |
| Regulatory Lead | Richard Gillespie | Maintains VMP; manages change control |
| PQ Operator | Richard Gillespie + Physics/Biology SME | Executes PQ with real data |

**Note:** The L3 Reviewer role requires a person independent of the development lead. This position is currently open. No OQ sign-off is valid without an L3 Code Review Record.

---

## 13. Validation Completion Criteria

A cell is considered **validated** when:

- [ ] URS documented and approved
- [ ] FS authored, reviewed, and approved (this document for GaiaHealth)
- [ ] DS authored, reviewed, and L3-counter-signed
- [ ] Code Review Records completed by L3 Reviewer
- [ ] RTM complete with ≥ 100% requirement coverage
- [ ] IQ executed with PASS receipt (`iq_receipt.json`)
- [ ] OQ executed with PASS receipt (`testrobit_receipt.json`), all tests passing, no SKIPs
- [ ] PQ executed with PASS receipt (`pq_receipt.json`), ΔG within tolerance
- [ ] Change Control procedure documented and acknowledged by owner
- [ ] Periodic Review schedule established

**Current status as of 2026-04-16:**

| Cell | URS | FS | DS | CRR | RTM | IQ | OQ | PQ |
|------|-----|----|----|-----|-----|----|----|-----|
| GaiaHealth | ✅ | ✅ | ❌ | ❌ | ✅ | Pending Cursor | Pending Cursor | Pending |
| GaiaFTCL | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ (scripts exist) | ✅ (32/32) | Pending |

---

## 14. Document Control

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0 | 2026-04-16 | R. Gillespie | Initial VMP covering GaiaHealth and GaiaFTCL |

**Amendment procedure:** Amendments require owner sign-off and version increment. All cells referencing this VMP must be reviewed for impact.

---

*FortressAI Research Institute | Norwich, Connecticut*
*USPTO 19/460,960 | USPTO 19/096,071 | © 2026 All Rights Reserved*
