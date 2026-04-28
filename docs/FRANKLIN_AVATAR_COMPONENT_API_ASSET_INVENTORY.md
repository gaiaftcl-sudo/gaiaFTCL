# Franklin Avatar Component/API/Asset Inventory

## Runtime Components
- `GAIAOS/macos/Franklin/Sources/FranklinApp/FranklinApp.swift`
- `GAIAOS/macos/Franklin/Sources/FranklinApp/CanvasView.swift`
- `GAIAOS/macos/Franklin/Sources/FranklinApp/OperatorSurfaceModel.swift`
- `GAIAOS/macos/Franklin/Sources/FranklinApp/FranklinAvatarRuntime.swift`
- `GAIAOS/macos/Franklin/Sources/FranklinApp/FranklinRustBridge.swift`
- `GAIAOS/macos/Franklin/Sources/FranklinApp/FranklinLiveIOServices.swift`
- `GAIAOS/macos/Franklin/Sources/FranklinApp/FranklinRecordService.swift`
- `GAIAOS/macos/Franklin/Sources/FranklinApp/SproutEvidenceCoordinator.swift`

## Required API Contracts
- Visual:
  - Mesh discovery for `franklin_passy_v1.*`
  - Rig channel presence (`viseme`, `expression`, `posture`)
  - Frame budget refusal (`GW_REFUSE_AVATAR_FRAME_BUDGET_OVERRUN`)
- Voice:
  - Franklin persona voice profile loaded from `bundle_assets/voice/franklin_voice_profile.json`
  - Voice selection via `AVSpeechSynthesisVoice(identifier:)`
  - Non-generic speaking profile (`rate`, `pitchMultiplier`)
- Guide behavior:
  - Dispatch query carries `guide=franklin_avatar`
  - Avatar greeting and language-game guidance available from operator surface
- Evidence:
  - Recording start/stop evidence receipt path emission
  - Signed conversation receipts with hash chaining

## Rust Workspace Contracts
- Workspace root: `cells/franklin/avatar/Cargo.toml`
- Crates:
  - `cells/franklin/avatar/crates/avatar-core`
  - `cells/franklin/avatar/crates/avatar-tts`
  - `cells/franklin/avatar/crates/avatar-render`
  - `cells/franklin/avatar/crates/avatar-bridge`
  - `cells/franklin/avatar/crates/avatar-runtime`

## Asset Contracts
- Root: `cells/franklin/avatar/bundle_assets`
- Must-exist groups:
  - `meshes/franklin_passy_v1.(usdz|usda|usdc|obj|gltf|glb)`
  - `pose_templates/viseme/*.json` (>=11)
  - `pose_templates/expression/*.json` (>=12)
  - `pose_templates/posture/*.json` (>=6)
  - `illuminants/*.json` (>=4)
  - `voice/franklin_voice_profile.json`

## Validation Entrypoints
- Swift tests: `GAIAOS/macos/Franklin/Tests/FranklinPresenceTests/FranklinPresenceTests.swift`
- TSD validator: `scripts/validate_mac_cell_stacks_tsd.sh`
- Franklin-specific validator: `scripts/validate_franklin_avatar_fsd.sh`
- Workflow gate: `cells/franklin/avatar/scripts/sprout.zsh`
