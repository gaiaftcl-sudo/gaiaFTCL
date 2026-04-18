# PQ — Performance Qualification — GaiaHealth Biologit Cell

> **GAMP Phase:** PQ (Phase 4 of 4)  
> **Prerequisite:** OQ PASS (`evidence/testrobit_receipt.json` with `"status": "PASS"`)  
> **Receipt:** `evidence/pq_receipt.json`  
> **Tolerance:** ΔG ±1 kcal/mol vs. peer-reviewed literature

---

## Purpose

Performance Qualification (PQ) is the final phase of the GAMP 5 lifecycle. It demonstrates that GaiaHealth performs correctly under **real production conditions** with real biological data. A CURE must be emitted for a novel molecular target, with the computed binding free energy within ±1 kcal/mol of peer-reviewed literature values.

PQ is executed by a qualified operator, not by the Swift TestRobit. The TestRobit is an OQ tool only (`training_mode = true`). PQ uses `training_mode = false` and real biological inputs.

---

## PQ Protocol

### Step 1 — Select Target

Choose a protein structure and ligand pair with a **known experimental binding affinity** from peer-reviewed literature. The PDB entry must be PHI-free (no patient data — standard PDB archives are already de-identified).

Requirements:
- Experimental binding ΔG measured by ITC, SPR, or fluorescence polarisation
- Published in a peer-reviewed journal (record DOI in PQ receipt)
- PDB resolution ≤ 2.5 Å preferred
- No AUTHOR or REMARK fields containing personal data (verified by PHI scrubber)

---

### Step 2 — PHI Scrub the PDB Input

Before loading any PDB file, run it through the `parse_pdb()` PHI scrubber:

```rust
// biologit_usd_parser::parser::parse_pdb()
// Automatically strips:
//   - AUTHOR records
//   - REMARK fields
//   - Any line containing SSN, MRN, DOB, email, or name patterns
// Passes HETAM, ATOM, SEQRES, and CRYST1 through unchanged
```

The operator confirms PHI scrub is clean before proceeding.

---

### Step 3 — Provision Owl Identity + Consent

1. The operator provides their Owl pubkey (`moor_owl()`) — transitions to MOORED
2. The operator signs consent for scope `ADMET_PERSONALIZATION` and `BIOMARKER_READ`
3. `consent_validity_check()` must return `valid: true` before advancing
4. Transition to PREPARED

---

### Step 4 — Validate Force-Field Parameters

Configure MD simulation parameters within constitutional bounds:

| Parameter | Required Range | PQ Recommended |
|-----------|---------------|----------------|
| Force field | AMBER, CHARMM, OPLS, or GROMOS | AMBER ff14SB or CHARMM36m |
| Temperature | 250–450 K | 300 K (physiological) |
| Pressure | 0.5–500 bar | 1.0 bar |
| Timestep | 0.5–4.0 fs | 2.0 fs |
| Simulation time | ≥ 10 ns | ≥ 100 ns for PQ |
| Water box padding | ≥ 10 Å | 12 Å |

`validate_ff_parameters()` → `FFValidationResult::Valid` required → transition to RUNNING.

---

### Step 5 — Run MD Simulation

The cell transitions to RUNNING. The Metal renderer displays the live MD trajectory. The WASM constitutional substrate is polled every 1,000 frames to verify that `force_field_bounds_check()` remains valid throughout the simulation.

**Epistemic tag during RUNNING:** `Measured` (0) if trajectory coordinates are from direct simulation; `Inferred` (1) if enhanced sampling methods are used.

---

### Step 6 — Analysis and CURE Emission

On simulation completion, the cell transitions to ANALYSIS:

1. **Binding ΔG computation** — using MM-PBSA, MM-GBSA, or FEP
2. **ADMET evaluation** — `admet_bounds_check()` on all five Lipinski parameters
3. **Epistemic chain validation** — `epistemic_chain_validate()` confirms M or I
4. **Selectivity check** — `selectivity_check()` on target vs. off-target IC50
5. **PHI check** — `phi_boundary_check()` on any output strings
6. **Consent validity** — `consent_validity_check()` still within 5-minute window

If all 8 WASM exports return `valid: true` or `Valid`, and epistemic tag is M or I → **CURE state entered**.

---

### Step 7 — Validate ΔG Against Literature

Compare the computed binding ΔG with the experimental reference:

```
|ΔG_computed - ΔG_literature| ≤ 1.0 kcal/mol
```

**This is the PQ pass/fail criterion.** If the delta exceeds 1 kcal/mol, document the discrepancy, investigate the force-field choice, and re-run with corrected parameters. PQ cannot be declared PASS until tolerance is met.

**Example:**
- Literature ΔG: -8.1 kcal/mol (from ITC measurement, DOI: 10.xxxx/xxxxx)
- Computed ΔG: -8.4 kcal/mol
- Delta: 0.3 kcal/mol → **PASS** (within 1 kcal/mol)

---

### Step 8 — Write PQ Receipt

```json
{
  "phase": "PQ",
  "cell": "GaiaHealth-Biologit",
  "gamp_category": 5,
  "timestamp": "<ISO8601 UTC>",
  "training_mode": false,
  "target_pdb": "<PDB accession — e.g. 4EY7>",
  "ligand_id": "<PDB ligand code — e.g. ATP>",
  "literature_reference_doi": "10.xxxx/xxxxx",
  "force_field": "AMBER ff14SB",
  "simulation_time_ns": 100.0,
  "binding_dg_kcal_mol": -8.4,
  "literature_dg_kcal_mol": -8.1,
  "delta_kcal_mol": 0.3,
  "within_tolerance": true,
  "epistemic_tag": "Measured",
  "cure_state_reached": true,
  "admet_score": 0.82,
  "selectivity_ratio": 145.0,
  "owl_pubkey_hash": "<sha256 of owl pubkey — never the raw pubkey>",
  "pii_stored": false,
  "status": "PASS"
}
```

**Receipt location:** `cells/health/evidence/pq_receipt.json`

---

## PQ Exit Criteria

All of the following must be true:

- [ ] OQ receipt exists and is `"status": "PASS"`
- [ ] Real (non-training) biological data used
- [ ] PDB input PHI-scrubbed and verified clean
- [ ] Valid Owl identity bound and consent obtained
- [ ] Force-field parameters within constitutional bounds
- [ ] `BiologicalCellState::Cure` reached
- [ ] Epistemic tag = Measured (0) or Inferred (1)
- [ ] All 8 WASM constitutional exports returned valid
- [ ] `|binding_dg - literature_dg| ≤ 1.0 kcal/mol`
- [ ] `pii_stored: false` in receipt
- [ ] `owl_pubkey_hash` = SHA-256 of pubkey (never raw pubkey or name)
- [ ] `evidence/pq_receipt.json` written with `"status": "PASS"`

---

## PQ Failure Handling

| Failure | Cause | Resolution |
|---------|-------|-----------|
| ΔG delta > 1 kcal/mol | Force field mismatch, water model, sampling | Review force-field choice; extend simulation; try FEP if available |
| CURE not reached | ADMET failure or constitutional check | Review ADMET parameters; check selectivity ratio |
| Epistemic = Assumed | Enhanced sampling not properly classified | Re-classify method; use Inferred tag if model-based |
| WASM check fails | Input out of constitutional bounds | Fix the out-of-range parameter; do not bypass |
| PHI detected | PDB REMARK or AUTHOR field slipped through | Run PHI scrubber manually; verify `parse_pdb()` output |
| Consent expired | PQ took > 5 minutes at MOORED | Re-obtain consent; restart from PREPARED |

---

## Audit Trail

The PQ CURE record is appended to the **immutable audit log** using only the Owl pubkey hash:

```
[CURE] target=4EY7 ligand=ATP dg=-8.4 tag=Measured pubkey_hash=a3f2...1e9c
```

No personal information appears in the audit log. The Owl pubkey hash is the only identity reference. The hash is not reversible to the raw pubkey without the private key.

---

## Post-PQ: System Release

After PQ PASS, the GaiaHealth Biologit Cell is **validated and released for regulated use**. The three qualification receipts form the complete GAMP 5 validation package:

```
evidence/
├── iq_receipt.json          # IQ — installation evidence
├── testrobit_receipt.json   # OQ — operational evidence  
└── pq_receipt.json          # PQ — performance evidence
```

This package satisfies:
- FDA 21 CFR Part 11 §11.10(a) — system validation
- EU Annex 11 §4.3 — computerised system validation
- GAMP 5 Category 5 — custom application validation

---

## Revalidation Triggers

PQ must be **re-run** after any of the following:

| Change | Revalidation Required |
|--------|----------------------|
| Force field version upgrade | Full IQ → OQ → PQ |
| WASM constitutional substrate change | OQ → PQ |
| `BioligitPrimitive` ABI change (fails RG tests) | IQ → OQ → PQ |
| macOS major version upgrade | IQ → OQ → PQ |
| Metal framework major version change | IQ → OQ → PQ |
| Owl Protocol key rotation | IQ Phase 6 + PQ Step 3 |
| Operating environment change (new hardware) | Full IQ → OQ → PQ |
