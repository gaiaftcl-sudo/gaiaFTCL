# Franklin Avatar Full FSD + RTM

## Functional Requirements
- `FR-AV-001` Lifelike runtime host must use Metal-backed avatar surface.
- `FR-AV-002` Avatar must bind mesh and rig channels from signed bundle assets.
- `FR-AV-003` Frame budget violations must produce deterministic refusal codes.
- `FR-AV-004` Voice output must use Franklin identity profile, not generic fallback-first behavior.
- `FR-AV-005` Operator interactions must route through Franklin guide contract.
- `FR-AV-006` Recording control must produce evidence receipts.
- `FR-AV-007` Rust bridge symbols must load deterministically.
- `FR-AV-008` Validation stack must pass before workflow sprout run.

## API and Asset Acceptance Gates
- `API-AV-001` Mesh load API resolves `franklin_passy_v1.*`.
- `API-AV-002` Rig API exposes viseme/expression/posture counts.
- `API-AV-003` Frame API enforces budget using bridge validation.
- `API-AV-004` Speech API loads `franklin_voice_profile.json`.
- `API-AV-005` Route payload embeds `guide=franklin_avatar`.
- `ASSET-AV-001` Required mesh exists.
- `ASSET-AV-002` Viseme assets >= 11.
- `ASSET-AV-003` Expression assets >= 12.
- `ASSET-AV-004` Posture assets >= 6.
- `ASSET-AV-005` Illuminants >= 4.
- `ASSET-AV-006` Voice identity profile exists and is loadable.

## Traceability Matrix
| FR ID | Implementation | Test/Validator | Refusal/Gate |
| --- | --- | --- | --- |
| FR-AV-001 | `FranklinAvatarRuntime.swift` | `testAvatarRuntimeUsesMetalHostAndNoSceneKitPrimitives` | `sprout` visible invariant |
| FR-AV-002 | `FranklinAvatarAssetBinding.load()` | `testAvatarRuntimeBindsBridgeAndRigChannels` | `GW_REFUSE_AVATAR_MESH_ASSET_MISSING` |
| FR-AV-003 | `registerFrame(frameMs:targetHz:)` | `testAvatarRuntimeBindsBridgeAndRigChannels` | `GW_REFUSE_AVATAR_FRAME_BUDGET_OVERRUN` |
| FR-AV-004 | `FranklinSpeechLoopService` voice profile loader | `testLiveIOServicesUseAppleLocalFrameworks` | `validate_franklin_avatar_fsd.sh` |
| FR-AV-005 | `OperatorSurfaceModel.makeDispatchPayload()` | `testDispatchPayloadContainsPresenceEvidence` | route contract checks |
| FR-AV-006 | `OperatorSurfaceModel.toggleRecording()` | `testRecordingToggleWritesReceiptPath` | recording receipt path evidence |
| FR-AV-007 | `FranklinRustBridge.load()` | `testRustBridgeLoadsDeterministicSymbols` | bridge load refusal by behavior |
| FR-AV-008 | validation scripts + sprout orchestration | `validate_franklin_avatar_fsd.sh`, `validate_mac_cell_stacks_tsd.sh` | `sprout` gates A->J |

## Evidence Deliverables
- Component/API/asset inventory: `docs/FRANKLIN_AVATAR_COMPONENT_API_ASSET_INVENTORY.md`
- RTM and acceptance mapping: `docs/FRANKLIN_AVATAR_FSD_RTM.md`
- Franklin validator receipt: `scripts/validate_franklin_avatar_fsd.sh` output
- Workflow evidence: `cells/franklin/avatar/evidence/*` from `sprout.zsh`
