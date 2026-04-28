# Franklin Asset Registry (SDK 26)

This registry records approved external sources for Franklin assets and models.

Important:
- These links are provenance only.
- Runtime, FSD, and sprout must use in-repo files only.
- No network fetches are allowed during app launch or sprout qualification.

## 1) Geometry And Rig Sources

- Free3D Benjamin Franklin High Poly (ID 1217)  
  https://free3d.com/3d-model/benjamin-franklin-1217.html
- CGTrader Rigged Franklin  
  https://www.cgtrader.com/3d-models/character/historic/benjamin-franklin-137b0185-3b95-4672-881c-22534579c09c
- Smithsonian Houdon reference (NPG.70.16)  
  https://www.si.edu/object/benjamin-franklin:npg_NPG.70.16

## 2) Voice And Alignment Sources

- DIA (Nari Labs)  
  https://github.com/nari-labs/dia
- Kokoro-82M  
  https://huggingface.co/hexgrad/Kokoro-82M
- F5-TTS  
  https://github.com/SWivid/F5-TTS

## 3) Apple SDK References

- Foundation Models documentation  
  https://developer.apple.com/documentation/foundationmodels
- Xcode 26.4 release notes  
  https://developer.apple.com/documentation/xcode-release-notes/xcode-26_4-release-notes

## 4) In-Repo Contract Targets

All required runtime files must be present under:

- `cells/franklin/avatar/bundle_assets/meshes/Franklin_Passy_V2.fblob`
- `cells/franklin/avatar/bundle_assets/materials/Franklin_Z3_Materials.metallib`
- `cells/franklin/avatar/bundle_assets/spectral_luts/beaver_cap_spectral_lut.exr`
- `cells/franklin/avatar/bundle_assets/spectral_luts/anisotropic_flow_map.exr`
- `cells/franklin/avatar/bundle_assets/spectral_luts/claret_silk_degradation.exr`
- `cells/franklin/avatar/bundle_assets/voice/styletts2_franklin_v1.coreml.mlmodelc/Manifest.json`

Runtime gates:
- `scripts/require_franklin_passy_assets.sh`
- `scripts/validate_franklin_avatar_fsd.sh`
- `cells/franklin/avatar/scripts/sprout.zsh` Gate A preflight
