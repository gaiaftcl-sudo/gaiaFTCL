# Franklin Avatar — Asset Gate (build-time + runtime + test)

**Document reference:** GFTCL-AVATAR-ASSET-GATE-001
**Spec authority:** this file. Cross-referenced by `cells/franklin/avatar/required_assets.json`, `cells/franklin/avatar/refusal_codes/AVATAR_ASSET.json`, `scripts/check_franklin_avatar_assets.zsh`, `GAIAOS/macos/Franklin/Plugins/CheckFranklinAvatarAssets/CheckFranklinAvatarAssets.swift`, `GAIAOS/macos/Franklin/Sources/FranklinApp/FranklinLaunchGate.swift`, `GAIAOS/macos/Franklin/Tests/FranklinPresenceTests/FranklinLaunchGateTests.swift`.

---

## Why this gate exists

A Passy-period Franklin avatar that boots into a red `Franklin Avatar Refused` screen because its required assets are missing is a build defect, not a runtime decision. The lifelike pipeline depends on six concrete files: the Passy mesh, the Metal shader library, three spectral LUTs, and the StyleTTS 2 CoreML manifest, plus a sibling voice profile. If any of them is missing the avatar cannot render a non-violated state, and the substrate is contractually required to refuse rather than show a stand-in face.

The gate makes the same decision in three places, so the operator can never see the red screen by accident:

The build-time script (`scripts/check_franklin_avatar_assets.zsh`) refuses `swift build` / `xcodebuild` when any required asset is missing or undersized. The SwiftPM build-tool plugin (`Plugins/CheckFranklinAvatarAssets/`) wires that script into the `FranklinApp` executable target, so any normal build invocation runs the check. The runtime gate (`Sources/FranklinApp/FranklinLaunchGate.swift`) re-verifies at launch and refuses to instantiate `CanvasView` if anything has drifted between build and run. The XCTest suite (`Tests/FranklinPresenceTests/FranklinLaunchGateTests.swift`) locks the contract in CI: if the JSON drifts from the test fixture, the test fails before either layer ships.

All four layers consume **one file**: `cells/franklin/avatar/required_assets.json`. That is the single source of truth. Edit nothing else without editing it; edit nothing else without updating the test that locks it.

---

## The six required assets

| Label | Relative path | Min bytes | Kind |
| --- | --- | --- | --- |
| `Franklin_Passy_V2.fblob` | `cells/franklin/avatar/bundle_assets/meshes/` | 1,000,000 | Mesh — 1.5 M-tri Passy reference |
| `Franklin_Z3_Materials.metallib` | `cells/franklin/avatar/bundle_assets/materials/` | 50,000 | Metal shader library (7-pass pipeline) |
| `beaver_cap_spectral_lut.exr` | `cells/franklin/avatar/bundle_assets/spectral_luts/` | 10,000 | Spectral reflectance for the beaver-fur Passy cap |
| `anisotropic_flow_map.exr` | `cells/franklin/avatar/bundle_assets/spectral_luts/` | 10,000 | Anisotropic strand-flow map (hair + cap) |
| `claret_silk_degradation.exr` | `cells/franklin/avatar/bundle_assets/spectral_luts/` | 10,000 | Period-aged claret silk reflectance (frock coat lining) |
| `styletts2_franklin_v1.coreml.mlmodelc/Manifest.json` | `cells/franklin/avatar/bundle_assets/voice/styletts2_franklin_v1.coreml.mlmodelc/` | 100 | StyleTTS 2 CoreML compiled-model manifest |

Plus the sibling voice profile at `cells/franklin/avatar/bundle_assets/voice/franklin_voice_profile.json` whose `personaID` must equal `franklin.guide.v1`.

---

## Refusal codes

Defined in `cells/franklin/avatar/refusal_codes/AVATAR_ASSET.json`. Each code is emitted with the same exit code by the script, the plugin, and the runtime gate.

| Refusal | Exit | Trigger |
| --- | --- | --- |
| `GW_REFUSE_ASSET_MISSING:<label>` | 215 | Required asset file is absent |
| `GW_REFUSE_ASSET_TOO_SMALL:<label>` | 216 | Asset present but below `min_bytes` |
| `GW_REFUSE_ASSET_HASH_MISMATCH:<label>` | 217 | Asset present, sized, but `sha256` (when pinned) does not match |
| `GW_REFUSE_FRANKLIN_VOICE_PROFILE_MISSING` | 218 | Voice profile JSON absent or unparseable |
| `GW_REFUSE_FRANKLIN_VOICE_PROFILE_INVALID_PERSONA` | 219 | Voice profile parses but `personaID` does not equal the required value |
| `GW_REFUSE_AVATAR_WORKSPACE_ROOT_UNRESOLVED` | 220 | Could not locate the gaiaFTCL workspace from build/launch context |
| `GW_REFUSE_AVATAR_REQUIRED_ASSETS_JSON_MISSING` | 221 | The canonical JSON itself is missing |

---

## How the build refuses

Running `swift build` against `GAIAOS/macos/Franklin/Package.swift` triggers the `CheckFranklinAvatarAssets` build-tool plugin **before** the FranklinApp executable target compiles. The plugin walks up from the package directory until it finds `cells/franklin/avatar/required_assets.json`, then runs `scripts/check_franklin_avatar_assets.zsh <workspaceRoot>`.

If the script exits non-zero, SwiftPM reports the failed pre-build command and aborts. The `.app` bundle is never produced. Xcode shows the same `REFUSED:GW_REFUSE_ASSET_*` lines in its Issues navigator.

There is no path where `swift build` succeeds and the runtime gate then refuses with `GW_REFUSE_ASSET_MISSING`. If those two layers ever disagree, either the JSON has drifted between build and run-time CWDs, or someone deleted an asset between build and launch — both are operational faults the tests catch.

---

## How the runtime refuses (defense in depth)

`FranklinLaunchGate.evaluate()` in `Sources/FranklinApp/FranklinLaunchGate.swift` walks up from the app's `currentDirectoryPath` until it finds the same JSON, then re-checks every asset. If any check fails, the SwiftUI scene routes to `FranklinLaunchRefusalView` (the red screen) instead of `CanvasView`. This catches the case where the operator moved or deleted an asset between build and launch — the build doesn't see it, but the runtime does.

The `evaluate(workspaceRoot:manifestURL:)` overload exists so the XCTest suite can drive the gate against synthetic fixtures without touching the real bundle.

---

## How CI locks the contract

`Tests/FranklinPresenceTests/FranklinLaunchGateTests.swift` builds a temp workspace per test with a synthetic `required_assets.json` and per-test asset perturbations:

`test_allAssetsPresent_isReady` — golden path. `test_eachMissingAsset_emitsExactRefusal` — six sub-tests, one per asset, each expects the matching `GW_REFUSE_ASSET_MISSING:<label>`. `test_undersizedAsset_emitsTooSmall`, `test_hashMismatch_emitsHashMismatch`, `test_voiceProfileMissing_emitsRefusal`, `test_voiceProfileWrongPersona_emitsRefusal`, `test_manifestMissing_emitsRefusal` — each refusal code has at least one test. `test_canonicalManifestEnumeratesSixAssets` — locks the live JSON to the test's canonical list; if you add or remove an asset, this test fails until you update both files in the same commit.

---

## No placeholders. Ever.

There is no developer-stub mode. There is no `dev_stub` marker, no `"kind": "placeholder"` payload, no padded-zero file that satisfies `min_bytes` to make the gate fake-pass. The build-time script and the runtime gate both refuse any required asset whose first 64 KB contains `dev_stub`, `PLACEHOLDER:`, `"kind":"placeholder"`, or `"origin":"dev_stub"` — emitting `GW_REFUSE_ASSET_PLACEHOLDER_MARKER:<label>`.

If a required asset is missing, the answer is to **run its production pipeline** until it exists. The pipelines live alongside this contract:

| Required artifact | Producing pipeline | Inputs that the operator must supply |
| --- | --- | --- |
| `Franklin_Passy_V2.fblob` | `cells/franklin/avatar/scripts/produce_franklin_passy_mesh.zsh` → `tools/bake_mesh/` | Master USDZ from Duplessis 1778 photogrammetry, retopologized to ~1.5 M tris, ARKit FACS-52 blendshape rig |
| `Franklin_Z3_Materials.metallib` | `cells/franklin/avatar/scripts/build_metallib.zsh` → `xcrun metal -c` per `.metal` source then `xcrun metallib` | Source shaders live at `cells/franklin/avatar/shaders/*.metal` and are tracked in git |
| `beaver_cap_spectral_lut.exr`, `anisotropic_flow_map.exr`, `claret_silk_degradation.exr` | `cells/franklin/avatar/scripts/produce_spectral_luts.py` | Wavelength-resolved CSV reflectance for each material, captured against a calibrated reference (Macbeth ColorChecker SG + period textile archive) |
| `styletts2_franklin_v1.coreml.mlmodelc/Manifest.json` (and the rest of the `.mlmodelc/`) | `cells/franklin/avatar/scripts/produce_styletts2_coreml.zsh` → `coremltools.convert(..., compute_units=.cpuAndNeuralEngine)` | StyleTTS 2 weights + reference audio + the existing voice profile |
| `franklin_voice_profile.json` | Tracked in git as a real config (not a binary). Source of truth for `personaID == franklin.guide.v1` | n/a (configuration, edited directly) |

Each pipeline script emits `GW_REFUSE_PIPELINE_TOOLCHAIN_MISSING:<tool>` when its dependency (`xcrun`, `coremltools`, etc.) is absent on the build host, and writes a build receipt next to the produced artifact so the FUIT signer can attach a provenance record.

When the FUIT bundle signer (`tools/sign_bundle/`) processes a bundle it MUST refuse with `GW_REFUSE_AVATAR_BUNDLE_PLACEHOLDER_IN_PRODUCTION` for any artifact whose header carries one of the forbidden substrings. This means even a binary that satisfies `min_bytes` and `sha256` cannot ship if it carries the marker — defense in depth.

---

## Cross-references

- `cells/franklin/avatar/required_assets.json` — the JSON
- `cells/franklin/avatar/refusal_codes/AVATAR_ASSET.json` — refusal-code registry
- `scripts/check_franklin_avatar_assets.zsh` — build-time script
- `GAIAOS/macos/Franklin/Plugins/CheckFranklinAvatarAssets/CheckFranklinAvatarAssets.swift` — SwiftPM plugin
- `GAIAOS/macos/Franklin/Package.swift` — declares the plugin under `FranklinApp`
- `GAIAOS/macos/Franklin/Sources/FranklinApp/FranklinLaunchGate.swift` — runtime gate
- `GAIAOS/macos/Franklin/Sources/FranklinApp/FranklinApp.swift` — uses the gate to route to refusal view or canvas
- `GAIAOS/macos/Franklin/Tests/FranklinPresenceTests/FranklinLaunchGateTests.swift` — XCTest contract
