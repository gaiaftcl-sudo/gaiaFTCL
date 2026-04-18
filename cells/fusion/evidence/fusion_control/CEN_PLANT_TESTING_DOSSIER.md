# CEN Fusion Plant Testing Dossier (Mac App First)

## 1) Purpose and CEN Scope

This dossier documents the current GAIAFTCL fusion testing and control surface for all plant concepts currently represented in-repo:

- Tokamak (MCF)
- Stellarator (MCF)
- FRC (MIF)
- Pulsed-compression MIF
- Laser ICF
- Other-driver ICF

This is a C4-anchored document. Any statement here is bounded by repository artifacts and receipts. Where direct evidence is missing, the row is marked as `gap` and not promoted as complete.

## 2) Evidence Baseline (C4 Anchors)

Primary anchors used in this dossier:

- `evidence/fusion_control/FUSION_UNIVERSAL_PLANT_CONTROL_ASSESSMENT.md`
- `deploy/fusion_mesh/FUSION_PLANT_MOORING_AND_MESH_PAYMENT.md`
- `deploy/mac_cell_mount/MAC_FUSION_MESH_CELL_PORTS.md`
- `services/gaiaos_ui_web/app/lib/macFusionCellPorts.ts`
- `deploy/fusion_mesh/fusion_projection.json`
- `deploy/fusion_mesh/fusion_virtual_systems_catalog_s4.json`
- `deploy/fusion_cell/config.json`
- `scripts/fusion_playwright_watch.sh`
- `evidence/fusion_control/playwright_watch/playwright_watch_last_witness.json`
- `evidence/fusion_control/playwright_watch/watch_state.json`
- `evidence/fusion_control/playwright_watch/playwright_watch.pid`
- `scripts/fusion_cell_long_run_runner.sh`
- `scripts/test_fusion_mesh_mooring_stack.sh`
- `scripts/test_fusion_plant_stack_all.sh`
- `scripts/test_fusion_all_with_sidecar.sh`

## 3) Mac App First Acceptance Block

### 3.1 Control loop implemented

`fusion_playwright_watch.sh` enforces this autonomous cycle:

1. Run self-heal Playwright test first.
2. Run full Fusion Playwright suite second.
3. Retry failed test track immediately once (default `FUSION_PLAYWRIGHT_TEST_RETRIES=2`).
4. Emit witness plus state JSON.
5. Sleep for configured interval (`FUSION_PLAYWRIGHT_INTERVAL_SEC`, default `900`).

### 3.2 Timings and runtime parameters

From script and receipts:

- Interval: `900s` default.
- Immediate retry backoff: `10s`.
- One-time precompile before first cycle: `build_metal_lib.sh`.
- Last witness cycle elapsed: `38.0s`.
- Watch state: `next_cycle=4`, `terminal=CURE`.
- PID witness file present with value `38506`.

### 3.3 Mac app test acceptance condition

Mac app-first acceptance for this loop is:

- `self_heal_rc == 0`
- `full_suite_rc == 0`
- witness `terminal == CURE`

Current latest witness meets all three conditions.

## 4) Global Input / Control / Output Contract (Applies To All Plant Concepts)

### 4.1 Input contract

Inputs currently enforced by scripts/config:

- Plant config file: `deploy/fusion_cell/config.json`
- Projection file: `deploy/fusion_mesh/fusion_projection.json`
- Optional env overrides:
  - `FUSION_CELL_CONFIG`
  - `FUSION_PROJECTION_JSON`
  - `FUSION_VALIDATION_CYCLES`
  - `FUSION_DECLARED_KW`
  - `FUSION_MESH_MOORING_REQUIRED`
  - `FUSION_MESH_HEARTBEAT_MAX_SEC`
  - `FUSION_UI_PORT`

### 4.2 Plasma/control loop timing requirements

Measured/configured timing controls:

- Watchdog cycle cadence: `900s` default (`fusion_playwright_watch.sh`).
- Retry wait after failed Playwright track: `10s`.
- Long-run mooring degraded wait: `60s` (`fusion_cell_long_run_runner.sh`).
- Real mode timeout: `3600s` default (`deploy/fusion_cell/config.json`).
- Mesh heartbeat stale threshold: `86400s` (`fusion_projection.json`, mooring policy).

### 4.3 Output contract

Required outputs and receipts:

- Watch witness: `evidence/fusion_control/playwright_watch/playwright_watch_last_witness.json`
- Watch state: `evidence/fusion_control/playwright_watch/watch_state.json`
- Long-run JSONL: `evidence/fusion_control/long_run_signals.jsonl`
- Plant stack validation: `evidence/fusion_control/FUSION_PLANT_STACK_VALIDATION.json`
- Mooring status/policy output via `fusion_mooring.sh` functions and heartbeat tooling.

### 4.4 Safety/refusal behavior

Current refusal/degraded behavior includes:

- If mooring is required and stale, emit `fusion_mooring_degraded` and skip high-entropy batch execution.
- If real plant command is unset, emit blocked JSON (`real.command_not_configured`) and continue controlled loop.
- Watchdog produces `terminal=REFUSED` for failing cycles.

## 5) Per-Plant Detailed Test + I/O Specification

Note: plant-specific physical I/O endpoints are intentionally site-defined and not hardcoded as WAN defaults. Where facility-specific values are absent in repo, that row is `gap`.

---

## 5A) Tokamak (MCF)

### Plant profile

- Class: Magnetic confinement.
- Geometry: Toroidal.
- Repo projection anchor: `fusion_virtual_systems_catalog_s4.json` includes virtual tokamak and real tokamak ingress concepts.

### Input requirements

- Required config and projection files listed in Section 4.
- For real ingress mode, `deploy/fusion_cell/config.json` must set `real.command` and optional `real.env`.
- Optional live ingress via bridge/middleware contracts (`torax`, `marte2`) in `fusion_projection.json`.

### Plasma control and timing

- Virtual loop executes recurring batches under `fusion_cell_long_run_runner.sh`.
- If in real mode, command is bounded by `timeout_sec` (default 3600s).
- Degraded safety fallback every 60s when mooring is stale and required.

### Outputs

- Batch JSONL lines with `control_signal=fusion_cell_batch`, `tokamak_mode`, `exit_code`, `plant_flavor`, payment/mooring fields.
- Degraded lines with `control_signal=fusion_mooring_degraded`.

### Plant-side requirements

- Site PCS endpoint mapping and invoke vectors must be supplied by facility runbook.
- Mesh mooring + wallet + heartbeat required for payment-eligible operation.

### Meets/exceeds status

- Meets: virtual tokamak control receipt path, watchdog self-heal evidence, degraded safety signal.
- Exceeds: autonomous retry and continuous CURE/REFUSED cycle witnessing.
- Gap: no tokamak site-specific live PCS endpoint evidence sealed in this dossier.

---

## 5B) Stellarator (MCF)

### Plant profile

- Class: Magnetic confinement.
- Geometry: 3D helical coils.
- Taxonomy anchor: universal multi-concept framing in assessment document and catalog summary language.

### Input requirements

- Uses same app surface and same config/projection contract as tokamak path.
- Requires facility-provided mapping for actual command and endpoint vectors.

### Plasma control and timing

- Current timing contract is the same platform envelope as Section 4.
- No stellarator-specific timing constants are hardcoded in repository.

### Outputs

- Same S4 and JSONL contract shape as generic plant modes.

### Plant-side requirements

- Facility-specific PCS/middleware binding required.
- Live hardware attestation + mesh mooring prerequisites for payment eligibility.

### Meets/exceeds status

- Meets: shared universal control surface and receipt discipline.
- Gap: no stellarator-specific bridge command/evidence artifact in current receipts.

---

## 5C) FRC (MIF)

### Plant profile

- Class: Magneto-inertial confinement.
- Geometry: compact toroid / linear system profile.

### Input requirements

- Same control/config envelope as Section 4.
- FRC-specific actuator/sensor map is not hardcoded and must be facility-provided.

### Plasma control and timing

- Runner supports virtual and real command dispatch with timeout and degraded fallback.
- No FRC-specific timing constants in committed config.

### Outputs

- Same JSONL and witness schema set as other concepts.

### Plant-side requirements

- Site command vector (`real.command`) and plant integration runbook required.

### Meets/exceeds status

- Meets: concept included in taxonomy and universal operator model.
- Gap: no FRC live-bridge witness in current evidence set.

---

## 5D) Pulsed-Compression MIF

### Plant profile

- Class: Magneto-inertial pulsed compression.
- Architecture: dynamic magnetic implosion class (taxonomy-level).

### Input requirements

- Same baseline config/projection and mooring/payment controls.
- Pulse profile and trigger timing are site-defined and not represented as hardcoded constants.

### Plasma control and timing

- Generic control-loop timing envelope applies.
- No pulse-specific waveform timing receipts in current evidence files.

### Outputs

- Standard witness files and JSONL batch schema.

### Plant-side requirements

- Site pulse-control definitions and protection sequence evidence required.

### Meets/exceeds status

- Meets: platform-level acceptance and safety/refusal envelope.
- Gap: no pulsed-compression-specific timing witness captured yet.

---

## 5E) Laser ICF

### Plant profile

- Class: Inertial confinement fusion.
- Method: laser-driven target compression.

### Input requirements

- Same universal app/receipt contract.
- Laser pulse train and target handling parameters are facility-specific (not hardcoded).

### Plasma control and timing

- Current repository offers generic timing enforcement, not laser-pulse timing primitives.

### Outputs

- Standard CURE/REFUSED plus witness/state JSON family.

### Plant-side requirements

- Facility-provided optics/target control interfaces must be integrated through bridge/config path.

### Meets/exceeds status

- Meets: taxonomy and universal operator contract include inertial class.
- Gap: no laser ICF plant-specific command/evidence chain currently sealed.

---

## 5F) Other-Driver ICF

### Plant profile

- Class: Inertial confinement, non-laser driver.
- Method: architecture-specific target drive.

### Input requirements

- Same baseline config, projection, and mooring requirements.
- Driver-specific control vectors must be provided externally.

### Plasma control and timing

- Generic timing and refusal envelope applies.
- No driver-specific timing constants in repo.

### Outputs

- Same witness structure and terminal states as all concepts.

### Plant-side requirements

- Site integration documents define real command pipeline.

### Meets/exceeds status

- Meets: universal plant surface and governance envelope.
- Gap: no explicit non-laser ICF live command/evidence witness present.

## 6) Unified Requirement-to-Evidence Matrix

| Requirement family | Requirement detail | Implementation artifact(s) | Evidence path(s) | Status |
|---|---|---|---|---|
| Mac app self-heal | Self-heal test runs before full suite and auto-retries | `scripts/fusion_playwright_watch.sh` | `evidence/fusion_control/playwright_watch/playwright_watch_last_witness.json` | meets |
| Mac app continuity | Autonomous cycle persists with state+pid | `scripts/fusion_playwright_watch.sh` | `evidence/fusion_control/playwright_watch/watch_state.json`, `evidence/fusion_control/playwright_watch/playwright_watch.pid` | meets |
| Timing governance | 900s cycle + 10s retry wait implemented | `scripts/fusion_playwright_watch.sh` | script constants/env defaults | meets |
| Plasma loop persistence | Run-until-stop long-run loop | `scripts/fusion_cell_long_run_runner.sh` | `evidence/fusion_control/long_run_signals.jsonl` | meets |
| Degraded safety | Stale mooring forces degraded-off signal | `scripts/fusion_cell_long_run_runner.sh`, `scripts/lib/fusion_mooring.sh` | JSONL `fusion_mooring_degraded` shape in script/test contracts | meets |
| Real-mode execution guard | Real command timeout and blocked JSON when unset | `deploy/fusion_cell/config.json`, `scripts/fusion_cell_long_run_runner.sh` | config + script logic | meets |
| Port correctness | C4/S4 port separation maintained | `deploy/mac_cell_mount/MAC_FUSION_MESH_CELL_PORTS.md`, `services/gaiaos_ui_web/app/lib/macFusionCellPorts.ts` | both files | meets |
| Mesh/payment policy | Live-hardware + heartbeat + mooring for payment eligibility | `deploy/fusion_mesh/FUSION_PLANT_MOORING_AND_MESH_PAYMENT.md`, `deploy/fusion_mesh/fusion_projection.json` | policy + projection JSON | meets |
| Plant taxonomy coverage | All six concept classes represented | `evidence/fusion_control/FUSION_UNIVERSAL_PLANT_CONTROL_ASSESSMENT.md` | taxonomy table + narrative | meets |
| Tokamak live ingress proof | Facility live tokamak bridge invocation evidence | bridge invoke hooks in projection | no sealed live tokamak run receipt in referenced set | gap |
| Stellarator-specific live proof | Stellarator command-level evidence | universal config only | no stellarator-specific run receipt | gap |
| FRC-specific live proof | FRC command-level evidence | universal config only | no FRC-specific run receipt | gap |
| Pulsed MIF timing proof | Pulse timing envelopes evidenced | universal config only | no pulse-timing receipt | gap |
| Laser ICF timing proof | Laser shot timing/IO proof | universal config only | no laser-specific receipt | gap |
| Other ICF driver proof | Non-laser driver command evidence | universal config only | no driver-specific receipt | gap |

## 7) Meets vs Exceeds Summary

### Meets (C4-backed)

- Mac app self-heal + full-suite watchdog loop with CURE witness and persistent state artifacts.
- Unified app/control contract for all declared plant concepts.
- Deterministic refusal/degraded behavior for stale mooring and missing real-command configuration.
- Explicit C4/S4 port boundary contract (8803/4222/8900 vs 8910/14222).
- Payment/mooring policy fields and constraints projected and documented.

### Exceeds (current platform behavior)

- Autonomous retry and self-heal orchestration without manual intervention per cycle.
- Unified witness discipline across script execution, state files, and structured JSON outputs.
- Universal operator surface designed for backend interchangeability rather than per-plant UI forks.

### Gaps (must remain explicit)

- No sealed, plant-specific live facility receipts for stellarator/FRC/pulsed-MIF/laser-ICF/other-ICF in this evidence set.
- No site-specific PCS endpoint/timing runbooks attached in this dossier.

## 8) CEN Submission Checklist

- [x] Mac app-first watchdog path documented with current witness fields.
- [x] Input/control/output contracts documented with concrete file anchors.
- [x] Timing requirements documented from scripts/config.
- [x] Six plant concepts documented individually.
- [x] Requirement-to-evidence matrix included with meets/exceeds/gap tags.
- [x] C4-backed statements separated from S4 projections.
- [x] Gaps explicitly listed where receipts are not yet present.

## 9) Deployment-Later Annex (Sequenced After Mac App First)

The following are intentionally post-Mac-app-first and are not claimed as complete here:

1. Seal plant-specific live bridge receipts per concept (facility-run receipts for tokamak/stellarator/FRC/MIF/ICF variants).
2. Attach site-runbook timing envelopes and endpoint maps per plant installation.
3. Extend matrix rows from `gap` to `meets` only after corresponding C4 artifacts are written under `evidence/fusion_control/`.
4. Promote from Mac-local evidence to mesh-wide deployment receipts once nine-cell deployment evidence for the same test vectors is captured.

---

Generated for CEN request context (Sinem Salva Ersoy), Mac-app-first closure discipline, and full multi-concept plant coverage without unsealed live-plant claims.
