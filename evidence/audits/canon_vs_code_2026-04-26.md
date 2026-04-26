# Canon vs Code Audit (2026-04-26)

Scope: canon under `/Users/richardgillespie/Documents/Franklin_*.md` versus implementation under `gaiaFTCL`.

## Summary

- PASS: 0/10 (0%)
- DRIFT: 3/10 (30%)
- GAP: 7/10 (70%)

Fail-closed rule applied: where runtime confirmation was not deterministically available in this pass, status is `GAP`, not `PASS`.

## 1) Receipt contract (v1.2.0) vs runtime envelope

Status: **GAP**

- Gateway-side envelope types align with contract structures (`ReceiptEnvelope`, `PresenceEvidence`).
  - `GAIAOS/gateway/Sources/MCPGatewayCore/Envelope.swift`
  - `substrate/RECEIPT_CONTRACT.yaml`
- Required runtime Class-A clean-install receipt capture was not completed in this pass; mandatory runtime proof is missing.
- Additional drift signal: Franklin app dispatch currently uses placeholder build hash and synthetic route IDs.
  - `GAIAOS/macos/Franklin/Sources/FranklinApp/OperatorSurfaceModel.swift`

## 2) 69 refusal codes registry vs emitters

Status: **GAP**

- Canon expects materialized `substrate/REFUSAL_CODE_REGISTRY.yaml`; file is absent in this repo.
  - `docs/Franklin_Xcode_Tooling_Implementation_Plan.md`
- Presence 50–59 emitters exist in code.
  - `GAIAOS/gateway/Sources/MCPGatewayCore/PresenceLayerVerifier.swift`
- No single verifier found that enforces full registry<->emitter parity across 1–69.

## 3) RL-1..RL-33 enforcement points (including two tooling plugins)

Status: **GAP**

- `substrate/RL_REGISTRY.yaml` in repo contains only RL-26..RL-30.
  - `substrate/RL_REGISTRY.yaml`
- Required plugin artifacts named in scope were not found:
  - `animation-house-spring-lint-plugin` (not found)
  - `handrolled-ui-lint-plugin` (not found)
- Planned tooling build-plugin tree not found:
  - `GAIAOS/macos/Franklin/Tooling/BuildPlugins/*` (missing)
  - referenced by `docs/Franklin_Xcode_Tooling_Implementation_Plan.md`

## 4) PR-1..PR-30 runnable OQ assertions and current pass state

Status: **GAP**

- `scripts/gamp5_oq.sh` currently runs OQ-0..OQ-5 style checks, not explicit PR-1..PR-30 mapping.
  - `scripts/gamp5_oq.sh`
- `tests/oq/` directory for PR-tagged suites is not present.
- Existing OQ receipts in cell evidence show pass for available lanes, but do not prove PR-1..PR-30 coverage.
  - `cells/fusion/macos/GaiaFusion/evidence/oq/oq_receipt.json`
  - `cells/fusion/macos/MacHealth/evidence/oq/oq_receipt.json`

## 5) Five cell catalogs and Fusion Engage Class bug

Status: **DRIFT**

- Catalog verification script currently enforces four cells (`health`, `fusion`, `lithography`, `xcode`), not five.
  - `scripts/gamp5_oq_catalog_verify.sh`
- Fusion Engage route wiring to `LG-FUSION-PLANT-CYCLE-001` is present and connected.
  - `cells/fusion/macos/GaiaFusion/GaiaFusion/Layout/FusionControlSidebar.swift`
  - `cells/fusion/macos/GaiaFusion/GaiaFusion/LocalServer.swift`
- Catalog-level `interaction_class` enforcement in live YAML remains incomplete/uneven versus safety-contract expectations.
  - `cells/fusion/LANGUAGE_GAMES.yaml`
  - `docs/MAC_STACK_SAFETY_CRITICAL_INTERACTION_CONTRACT.md`

## 6) Fusion deltas A–M (Gap Analysis)

Status: **GAP**

- Canon reference source for A–M is outside repo and not available in this pass for per-letter traceability.
  - `.cursor/plans/plan_completion_delta_d0e877b2.plan.md`
- Several fusion substrate artifacts exist, but explicit A–M mapping evidence is incomplete.
  - `substrate/fusion_invariant_registry.yaml`
  - `substrate/fusion_modes.yaml`
  - `substrate/fusion_rollback_recipes.yaml`
  - `substrate/fusion_campaign_ledger.yaml`

## 7) SC-A..SC-O implementation status

Status: **GAP**

- Canon SC integration source (`SC-A..SC-O`) is not available in-repo under the expected filename for direct line-to-line validation.
- Plan state still shows execution in progress / pending fixtures for some SC integration tasks.
  - `.cursor/plans/plan_completion_delta_d0e877b2.plan.md`
- Gate-6 completeness script exists and runs, but does not by itself prove full SC-A..SC-O implementation parity.
  - `scripts/gamp5_pq.sh`
  - `scripts/verify_interaction_contract_completeness.py`

## 8) Presence layer artifact conformance

Status: **DRIFT**

- Present: orb, canvas, receipt tray, refusal bloom path, FranklinUIKit core package.
  - `GAIAOS/macos/Franklin/Sources/FranklinApp/FranklinApp.swift`
  - `GAIAOS/macos/Franklin/Sources/FranklinApp/CanvasView.swift`
  - `GAIAOS/macos/Franklin/Package.swift`
- Missing or partial versus canon promises in this pass: explicit halo subsystem, full voice/gesture/gaze operational lane, AppIntents-bundle parity.
  - `GAIAOS/macos/Franklin/Sources/FranklinApp/OperatorSurfaceModel.swift`

## 9) Xcode tooling artifacts and gaiaftcl subcommand surface

Status: **GAP**

- Canon tooling plan exists and is checked by plan-presence verification.
  - `docs/Franklin_Xcode_Tooling_Implementation_Plan.md`
  - `scripts/verify_xcode_tooling_plan_presence.py`
- Physical tooling deliverables required by canon are not materialized in expected paths in this pass:
  - `GAIAOS/macos/Franklin/Tooling/ProjectTemplates/*` (missing)
  - `GAIAOS/macos/Franklin/Tooling/FileTemplates/*` (missing)
  - `GAIAOS/macos/Franklin/Tooling/SourceEditorExtensions/*` (missing)
  - `GAIAOS/macos/Franklin/Tooling/BuildPlugins/*` (missing)
  - `cells/material-sciences/` (missing)

## 10) Hash locks correctness and boot refusal path

Status: **DRIFT**

- Gateway boot path includes hash-lock verification and emits `GW_REFUSE_HASH_LOCK_DRIFT` on mismatch.
  - `GAIAOS/gateway/Sources/MCPGatewayApp/main.swift`
  - `GAIAOS/gateway/Sources/MCPGatewayCore/PresenceLayerVerifier.swift`
- Franklin app boot path does not enforce the same lock gate in this pass.
  - `GAIAOS/macos/Franklin/Sources/FranklinApp/FranklinApp.swift`

## Blockers (ranked)

1. **No unified 1–69 refusal registry artifact wired to emitter parity checks** (`GAP`, release-blocking integrity risk).
2. **PR-1..PR-30 executable OQ mapping is incomplete** (`GAP`, release-blocking qualification risk).
3. **SC-A..SC-O and Fusion A–M per-item implementation traceability is incomplete in-repo** (`GAP`, release-blocking compliance/audit risk).

