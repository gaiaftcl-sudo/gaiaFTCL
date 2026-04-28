# Franklin Swift App: Human Narrative

This document explains the entire Franklin Swift app in plain language: what each Swift file does, how runtime control flows, which JSON assets are consumed, which APIs are called, and which libraries/frameworks are used.

## 1) What this app is trying to be

Franklin is a macOS SwiftUI app with two windows:

- A **main operator canvas** where you route commands, inspect receipts, and control audio/visual/recording behavior.
- A **small presence window** (avatar bubble) that provides always-on status and quick activation.

The Swift side is designed as a control surface and evidence writer around a larger substrate workflow:

- It talks to a local service on `127.0.0.1:8830`.
- It loads avatar assets from `cells/franklin/avatar/bundle_assets`.
- It optionally bridges into Rust via `libavatar_bridge.dylib`.
- It emits evidence files for `sprout` gates and qualification loops.

## 2) Package and target structure

`GAIAOS/macos/Franklin/Package.swift` defines:

- **Product `FranklinUIKit`** (library): UI material/animation primitives and bundled sounds.
- **Product `FranklinApp`** (executable): main app runtime.
- **Target `FranklinPresenceTests`**: contract and behavior tests.

The package declares macOS platform `.v15`, while specific functionality (Foundation Models) is gated to newer availability checks in code.

## 3) Swift file-by-file narrative

## `Sources/FranklinApp/FranklinApp.swift`

- Entry point (`@main`).
- Starts `SproutEvidenceCoordinator` in `init()`.
- Opens two windows:
  - `WindowGroup("Franklin")` -> `CanvasView`.
  - `WindowGroup("Franklin Avatar Presence")` -> `AvatarView`.
- `AvatarView` is a compact circular status UI:
  - Pulses based on animation phase.
  - Reflects refusal/healthy color.
  - Polls health periodically (`refreshStatus()`).
  - Tap-to-activate behavior for main interaction.

Humanly: this file is the app shell and stage manager.

## `Sources/FranklinApp/CanvasView.swift`

- Main operator UI composition:
  - Facet switching (`Health`, `Fusion`, `Lithography`, `Xcode`).
  - Command dispatch field and class-A justification input.
  - Greet/Guide, Audio toggle, Visual toggle, Recording toggle.
  - Language game chip launcher.
  - Receipt tray and guidance text.
  - Lithography-specific conversation view.
- Contains `FranklinAvatarStage`, which renders the avatar pane and status overlays.
- Includes `FranklinMeshFallbackView`:
  - A deterministic fallback projection if bridge/render path is unavailable.
  - Explicit refusal text for bridge-unavailable state.

Humanly: this is the operator cockpit and the most visible behavior surface.

## `Sources/FranklinApp/OperatorSurfaceModel.swift`

This is the core orchestration brain (state + behavior):

- Manages active facet, last result, refusal bloom, receipts, conversation history, and signed utterance receipts.
- Health polling:
  - `GET http://127.0.0.1:8830/health`.
- Route dispatch:
  - `POST http://127.0.0.1:8830/xcode/intelligence`.
  - Sends `FranklinDispatchPayload` with `presence_evidence`.
  - Query now includes `guide=franklin_avatar`.
- Class-A operation gating:
  - Requires justification for sensitive verbs (`engage`, `mint`, `mask load`, etc.).
- Audio/visual/recording controls:
  - Audio -> `FranklinSpeechLoopService`.
  - Visual -> `FranklinVisionAttentionService`.
  - Recording -> `FranklinRecordService`.
- Language-game execution:
  - Enforces executable game IDs from catalog.
- Refusal intelligence:
  - Parses `GW_REFUSE_*`.
  - Builds diagnostic chains.
  - Provides human guidance text.
- Conversation evidence:
  - Signs utterance chain with Curve25519 key.
  - Persists JSONL receipts in Application Support.
- Domain narration helpers:
  - Lithography pre-emission, characterization, refusal explanations.
  - Group chat negotiation mode.
  - Closure essay generation from evidence vault.

Humanly: this file decides what Franklin says, where Franklin routes, when Franklin refuses, and what forensic evidence is written.

## `Sources/FranklinApp/FranklinAvatarRuntime.swift`

Visual runtime and frame-budget enforcement:

- Uses `Metal`/`MetalKit` (`MTKView`) instead of SceneKit primitives.
- `FranklinAvatarSceneController` tracks:
  - posture, active viseme, bridge version, frame ms, refusal code, asset binding.
- `FranklinAvatarAssetBinding.load()` discovers:
  - mesh file existence (`franklin_passy_v1.*`).
  - viseme/expression/posture counts from JSON folders.
- Deterministic refusal assignment:
  - Missing mesh.
  - Rig cardinality below minimums.
  - Frame budget overrun.
- `FranklinMetalRenderer`:
  - Clears/pulses color by posture state.
  - Registers frame timing against Rust bridge budget validator.
  - Configured for `120 FPS` preferred cadence.

Humanly: this is currently a Metal-hosted presence renderer with strict contract checks, not yet a full photoreal character renderer.

## `Sources/FranklinApp/FranklinRustBridge.swift`

FFI bridge to Rust shared library:

- Loads `cells/franklin/avatar/target/release/libavatar_bridge.dylib` via `dlopen`.
- Resolves symbols:
  - `franklin_avatar_bridge_version`
  - `franklin_avatar_validate_frame`
  - `franklin_avatar_first_viseme`
- Exposes Swift methods:
  - `version`
  - `validateFrame(frameMs:targetHz:)`
  - `firstViseme(for:)`

Humanly: if this bridge is unavailable, avatar behavior degrades and explicit refusal messaging appears.

## `Sources/FranklinApp/FranklinLiveIOServices.swift`

Local AI I/O service wrappers:

- `FranklinSpeechLoopService`:
  - AVSpeech synthesizer output.
  - SFSpeech recognizer authorization/start/stop.
  - Loads voice profile JSON from bundle assets.
  - Applies persona prosody (`rate`, `pitch`, preferred/fallback voice identifiers).
- `FranklinVisionAttentionService`:
  - Uses `VNDetectFaceLandmarksRequest` as attention primitive.
- `FranklinFoundationDialogService`:
  - Uses `LanguageModelSession` when available (`macOS 26+` gate).
  - Returns deterministic fallback line on failure/unavailability.

Humanly: this file binds Apple frameworks for voice, speech input permissions, vision hooks, and optional on-device model dialog.

## `Sources/FranklinApp/FranklinRecordService.swift`

Recording/evidence contract service:

- `start()` records session metadata intent.
- `stop()` writes JSON receipt:
  - `tau`, `lg_id`, timestamps, duration, pass state.

Humanly: this is evidence output for recording actions, not an MP4 compositor itself.

## `Sources/FranklinApp/FranklinLanguageGameCatalog.swift`

Hard-coded game catalog by facet:

- Health/Fusion/Lithography/Xcode route and qualification verbs.
- Shared Franklin avatar OQ/PQ games.

Humanly: this is the in-app command lexicon exposed in chips and used for route execution.

## `Sources/FranklinApp/SproutEvidenceCoordinator.swift`

Sprout integration/evidence writer:

- Activates only when environment variable `FRANKLIN_AVATAR_EVIDENCE` is set.
- Writes `iq/visible.json` with:
  - avatar mode
  - controls
  - frame budgets
  - material/period profile
  - lithography contract required games
  - rig channel counts
- Watches for `oq/.start` and `pq/.start` markers and writes completion receipts.

Humanly: this file is the Swift side of gate-friendly evidence generation for lifecycle orchestration.

## `Sources/FranklinUIKit/GlassMaterial.swift`

- Defines reusable SwiftUI material constants (`avatar`, `canvas`, `bubble`, `confirmationInset`).

## `Sources/FranklinUIKit/HouseSpring.swift`

- Defines shared spring animation (`Animation.franklin`).

## `Tests/FranklinPresenceTests/FranklinPresenceTests.swift`

Large contract suite validating:

- Window composition and primary UI host.
- Payload and route contract shape.
- Refusal extraction and guidance behavior.
- Recording receipt writes.
- Rust bridge symbol expectations.
- Metal runtime usage (and no SceneKit primitives).
- Presence evidence fields in source.
- Required language game IDs.
- No simulation/mock language in core avatar sources.
- Bundle counting behavior and visible contract material.

Humanly: tests are mostly contract assertions over source/runtime behavior and evidence semantics.

## 4) JSON assets and how Swift uses them

Asset root used by Swift:

- `cells/franklin/avatar/bundle_assets`

Consumed groups:

- `meshes/franklin_passy_v1.*`
  - Swift checks file presence and stores path in runtime binding.
  - Supported extensions:
    - `usdz`, `usda`, `usdc`, `obj`, `gltf`, `glb`
- `pose_templates/viseme/*.json`
  - Counted for rig cardinality.
- `pose_templates/expression/*.json`
  - Counted for rig cardinality.
- `pose_templates/posture/*.json`
  - Counted for rig cardinality.
- `illuminants/*.json`
  - Counted into visible contract (`material_system.illuminants`).
- `voice/franklin_voice_profile.json`
  - Decoded by `FranklinSpeechLoopService` for persona voice config.

Current JSON assets present include:

- 11 visemes
- 12 expressions
- 6 postures
- 4 illuminants
- 1 voice profile JSON

## 5) APIs and endpoints used by Swift

Local HTTP endpoints:

- `GET http://127.0.0.1:8830/health`
- `POST http://127.0.0.1:8830/xcode/intelligence`

Payload structures:

- `FranklinDispatchPayload`
  - `query` string includes target facet and guide marker.
  - `presence_evidence` nested object with modality, facet, posture metadata, hashes.

Evidence file APIs:

- Writes to environment-controlled evidence roots (IQ/OQ/PQ and recordings).
- Writes signed utterance receipts to application support JSONL.

Rust ABI boundary:

- Dynamic library + C symbol lookup via `dlopen`/`dlsym`.

## 6) Apple and system libraries/frameworks used

Swift modules imported across app:

- `SwiftUI`
- `Foundation`
- `AppKit`
- `CryptoKit`
- `AVFoundation`
- `Speech`
- `Vision`
- `Metal`
- `MetalKit`
- `Darwin`
- `FoundationModels` (conditional import/availability)

Functional use:

- UI composition/windowing: SwiftUI/AppKit
- Cryptographic signing/hash: CryptoKit
- Speech synthesis + audio session pieces: AVFoundation
- Speech recognition auth hook: Speech
- Face landmark request hook: Vision
- Rendering surface and frame timing: Metal/MetalKit
- Dynamic linking for Rust bridge: Darwin
- Optional on-device dialog generation: FoundationModels

## 7) Runtime flow in plain English

1. App boots, starts evidence coordinator if env vars request sprout evidence.
2. Presence bubble and main canvas are available.
3. Operator toggles facets and enters a route command.
4. `OperatorSurfaceModel` validates prompt, class-A justification if required.
5. Model submits route to local service endpoint with structured presence evidence.
6. Response maps to `CALORIE`/`REFUSED`, receipt bubble, diagnostics, and guidance.
7. Avatar stage updates posture and viseme state; frame budgets are checked.
8. If Rust bridge or assets are missing/invalid, deterministic refusal codes appear.
9. Conversations are hash-chained and signed; receipts are persisted.
10. In sprout mode, IQ/OQ/PQ witness JSON files are emitted from Swift side.

## 8) What this codebase currently does not yet deliver fully

Based on current Swift implementation shape:

- It does **not** yet contain a full photoreal facial rig renderer in Swift.
- It does **not** yet expose ARKit-52 blendshape channels in Swift runtime structs.
- It does **not** yet include explicit `MeshInstancesComponent` fur instancing code.
- Foundation model dialog is present as a service wrapper, but deep persona instruction/adapters are not fully wired as a strict production gate.

In short: the app is now a strong contract/control/evidence shell with partial avatar runtime and explicit refusal behavior, but still needs additional rendering/persona depth to match a fully lifelike Ben Franklin target.

## 9) Quick index of authoritative Swift sources

- `GAIAOS/macos/Franklin/Sources/FranklinApp/FranklinApp.swift`
- `GAIAOS/macos/Franklin/Sources/FranklinApp/CanvasView.swift`
- `GAIAOS/macos/Franklin/Sources/FranklinApp/OperatorSurfaceModel.swift`
- `GAIAOS/macos/Franklin/Sources/FranklinApp/FranklinAvatarRuntime.swift`
- `GAIAOS/macos/Franklin/Sources/FranklinApp/FranklinRustBridge.swift`
- `GAIAOS/macos/Franklin/Sources/FranklinApp/FranklinLiveIOServices.swift`
- `GAIAOS/macos/Franklin/Sources/FranklinApp/FranklinRecordService.swift`
- `GAIAOS/macos/Franklin/Sources/FranklinApp/FranklinLanguageGameCatalog.swift`
- `GAIAOS/macos/Franklin/Sources/FranklinApp/SproutEvidenceCoordinator.swift`
- `GAIAOS/macos/Franklin/Sources/FranklinUIKit/GlassMaterial.swift`
- `GAIAOS/macos/Franklin/Sources/FranklinUIKit/HouseSpring.swift`
- `GAIAOS/macos/Franklin/Tests/FranklinPresenceTests/FranklinPresenceTests.swift`

