# Franklin Xcode 26.4 Execution Spec

This document locks the Franklin Avatar target state to an Xcode 26.4-era architecture and defines what must change from the current Franklin macOS Swift implementation.

## Target Platform Profile

- IDE target: `Xcode 26.4 (Build 17E192)`
- Swift target: `Swift 6.3`
- Compiler posture:
  - strict concurrency complete
  - modern C++ interop mode for mixed pipelines where required
- Primary runtime target: visionOS-class spatial runtime
- Secondary runtime target: macOS control/operator surface

## Non-Negotiable Goal

Retire legacy "sprout-era avatar shell" behavior and deliver a Franklin runtime that is:

- visually embodied (not status-only)
- voice-identity specific
- deterministic under refusal contracts
- evidence-producing for qualification workflows

## Execution Policy Update (No Blanket Blockers)

Franklin runtime policy is now:

- **No blanket hard-fail across the entire app.**
- **Fusion-critical path may hard-refuse** when invariants are violated.
- For non-fusion flows, Franklin can **degrade gracefully** (slower cadence / reduced fidelity) while preserving evidence and refusal semantics.
- Avatar only fully withdraws when explicitly required by Fusion safety/sovereign constraints.

This keeps the operator surface alive while enforcing strict safety where it matters most.

## Asset Contract (Franklin Bundle)

Required high-fidelity avatar asset groups:

- volumetric mesh primary
- spectacles/glass sub-entity
- blendshape bank with baseline + Franklin-specific channels
- prosody/voice model artifact
- runtime data contract JSON

Current repository baseline (already present):

- `cells/franklin/avatar/bundle_assets/meshes/franklin_passy_v1.usda`
- `cells/franklin/avatar/bundle_assets/pose_templates/*`
- `cells/franklin/avatar/bundle_assets/illuminants/*`
- `cells/franklin/avatar/bundle_assets/voice/franklin_voice_profile.json`

Gap to close:

- add true production mesh/material set and rig beyond the placeholder mesh
- add explicit bridge/runtime loading contract for advanced mesh/shape assets

## OpenUSD Manifold Contract (M8 = S4 x C4)

Franklin state authority is moved into OpenUSD schema semantics:

- S4 (spatial/physical) manifold keys:
  - projection mode
  - M8 coordinate
- C4 (administrative/sovereign) manifold keys:
  - sovereign authority bit
  - administrative origin declaration
- Runtime state key:
  - `vQbitDelta` (single state-change driver)

Language-game transitions must be gated by `vQbitDelta` thresholds and recorded as evidence receipts.

## Frame-Rate Invariant (Low-Drag Mode)

Target runtime cadence for Real Guide mode:

- **29 fps fixed target**
- interval ~`1/29` seconds (~34.48ms cadence)

Operational interpretation:

- Franklin prioritizes deterministic low-drag behavior over high-refresh cosmetic motion.
- Non-fusion flows may run at this fixed cadence without refusal.
- Fusion-critical flows can escalate to refusal when state-contract violations occur.

## Required Runtime Modules

## 1) Franklin Core Runtime

Primary responsibilities:

- instantiate avatar entity from production mesh bundle
- bind expression/viseme channels at frame cadence
- enforce frame-budget invariants and refuse deterministically when violated
- expose observability telemetry for IQ/OQ/PQ evidence

## 2) Voice/Dialogue Runtime

Primary responsibilities:

- load Franklin identity voice contract
- apply persona-safe speech policy and cadence
- support local/offline-first dialogue path
- prohibit generic fallback voice as default production path

## 3) Visual/Spatial Runtime

Primary responsibilities:

- bind high-fidelity mesh entity with spectacles/glass material behavior
- apply blendshape streams to render pipeline
- support explicit fallback projection in non-fusion contexts
- reserve hard refusal for fusion-critical invariant breaches

## 4) Operator Surface Integration

Primary responsibilities:

- keep existing Franklin command/receipt tray capabilities
- drive route payloads with `guide=franklin_avatar`
- keep signed utterance receipts and evidence storage

## Franklin Logic Contract (Swift)

The Franklin runtime must preserve these implementation constraints:

- `@MainActor` UI-facing orchestration
- strict state ownership with observable model updates
- no mock/sim-only path in production execution flow
- refusal-first only where policy marks invariant as hard terminal (primarily fusion-critical)
- otherwise deterministic degrade with evidence receipts

High-level shape:

- avatar entity init (async)
- expression update per stream tick
- optics/material component setup for spectacles
- frame-budget measurement and refusal propagation

## Data Contract JSON (Runtime)

Required fields in Franklin runtime data manifest:

- project identity
- compiler/feature flags
- asset pointers (mesh, voice)
- runtime constraints (fps, thermal thresholds)

This must be validated before runtime activation and included in evidence receipts.

## Migration Map (Current -> Target)

Current Swift implementation anchors:

- `GAIAOS/macos/Franklin/Sources/FranklinApp/FranklinAvatarRuntime.swift`
- `GAIAOS/macos/Franklin/Sources/FranklinApp/FranklinLiveIOServices.swift`
- `GAIAOS/macos/Franklin/Sources/FranklinApp/OperatorSurfaceModel.swift`
- `GAIAOS/macos/Franklin/Sources/FranklinApp/CanvasView.swift`
- `GAIAOS/macos/Franklin/Sources/FranklinApp/FranklinRustBridge.swift`

Required hardening steps:

1. Replace placeholder visual behavior with production mesh entity pipeline.
2. Expand rig contract from cardinality-only checks to full channel mapping checks.
3. Promote bridge-unavailable from degraded UX to explicit launch refusal policy where required.
4. Add runtime manifest validation step before avatar activation.
5. Add explicit concurrency audit for all actor boundaries and async calls.

## Validation Requirements

Gate must fail if any of the below are unmet:

- fusion-critical invariant invalid and unrecoverable
- required evidence artifacts missing for qualification path
- sovereign/admin manifold state invalid for constrained operations

For non-fusion routes, these conditions should prefer **degraded operation + explicit receipted warnings** over terminal fail:

- bridge unavailable
- reduced mesh/material fidelity
- temporary voice identity fallback
- frame pacing below target

## Cache/Toolchain Hygiene (Operator)

For stale legacy build artifact cleanup and toolchain verification:

- clear old derived data for legacy Franklin/Sprout-era targets
- verify active Swift toolchain version in current Xcode selection

All cleanup operations should be executed manually by operator confirmation in sensitive environments.

## Acceptance Criteria

- Franklin is visibly embodied in runtime (not zero-avatar)
- voice identity path is deterministic and non-generic
- route/guidance controls remain functional
- evidence generation remains intact for sprout and qualification loops
- strict refusal semantics are explicit and actionable
- fusion path remains hard-safe; non-fusion path remains operational under controlled degrade

## Proposed OpenUSD Schema Naming

Recommended schema artifact names for implementation:

- `FranklinSubstrate.usd` (root layer)
- `FranklinAvatarAPI` (applied API schema)
- S4 keys:
  - `franklin:s4:projectionMode`
  - `franklin:s4:m8_coordinate`
- C4 keys:
  - `franklin:c4:isSovereign`
  - `franklin:c4:originGeometry`
- state key:
  - `franklin:state:vQbitDelta`

These keys should be the canonical bridge contract between OpenUSD stage state and Franklin language-game dispatch.

