# Mac Cell Stacks TSD

## Scope

This TSD defines deterministic readiness checks for all on-Mac stacks:

- Franklin avatar/operator stack
- GaiaFusion macOS stack
- MacHealth macOS stack
- Lithography stack alignment (Mac path + qualification docs)

The checks are designed to fail fast with explicit refusal codes before IQ/OQ/PQ progression.

## TSD Clauses

- `TSD-MAC-001` Franklin app source contract
  - `GAIAOS/macos/Franklin/Package.swift` exists.
  - Core Franklin app sources exist under `GAIAOS/macos/Franklin/Sources/FranklinApp/`.

- `TSD-MAC-002` Franklin avatar Rust workspace contract
  - `cells/franklin/avatar/Cargo.toml` exists.
  - Crates exist: `avatar-core`, `avatar-tts`, `avatar-render`, `avatar-bridge`, `avatar-runtime`.

- `TSD-MAC-003` Franklin avatar bundle baseline contract
  - `cells/franklin/avatar/bundle_assets/illuminants` has at least 4 JSON files.
  - `cells/franklin/avatar/bundle_assets/pose_templates/viseme` has at least 11 JSON files.
  - `cells/franklin/avatar/bundle_assets/pose_templates/expression` has at least 12 JSON files.
  - `cells/franklin/avatar/bundle_assets/pose_templates/posture` has at least 6 JSON files.
  - Passy mesh exists in supported format under `cells/franklin/avatar/bundle_assets/meshes/`:
    `franklin_passy_v1.usdz` OR `franklin_passy_v1.usda` OR `franklin_passy_v1.usdc`
    OR `franklin_passy_v1.obj` OR `franklin_passy_v1.gltf` OR `franklin_passy_v1.glb`.

- `TSD-MAC-004` GaiaFusion macOS stack contract
  - `cells/fusion/macos/GaiaFusion/Package.swift` exists.
  - `cells/fusion/macos/GaiaFusion/GaiaFusion/GaiaFusionApp.swift` exists.
  - `cells/fusion/macos/GaiaFusion/MetalRenderer/rust/Cargo.toml` exists.
  - `cells/fusion/macos/GaiaFusion/MetalRenderer/include/gaia_metal_renderer.h` exists.
  - `cells/fusion/macos/GaiaFusion/MetalRenderer/lib/libgaia_metal_renderer.a` exists.

- `TSD-MAC-005` MacHealth + health Rust stack contract
  - `cells/fusion/macos/MacHealth/Package.swift` exists.
  - `cells/health/Cargo.toml` exists.
  - `cells/health/gaia-health-renderer/src/lib.rs` exists.
  - `cells/health/biologit_md_engine/src/lib.rs` exists.

- `TSD-MAC-006` Lithography + material science contract
  - `cells/lithography/docs/IQ_OQ_PQ_LITHOGRAPHY_CELL.md` exists.
  - `cells/lithography/docs/GAMP5_LIFECYCLE.md` exists.
  - `cells/lithography/docs/FUNCTIONAL_SPECIFICATION.md` exists.
  - `cells/franklin/docs/LITHOGRAPHY_MAC_PATH.md` exists.
  - `wiki/M8_Lithography_Silicon_Cell_Wiki.md` exists.
  - `wiki/Qualification-Catalog.md` exists.

## Refusal Codes

- `GW_REFUSE_TSD_MAC_001` Franklin app source contract failed.
- `GW_REFUSE_TSD_MAC_002` Franklin avatar Rust workspace contract failed.
- `GW_REFUSE_TSD_MAC_003` Franklin avatar bundle baseline contract failed.
- `GW_REFUSE_TSD_MAC_004` GaiaFusion macOS stack contract failed.
- `GW_REFUSE_TSD_MAC_005` MacHealth/health Rust stack contract failed.
- `GW_REFUSE_TSD_MAC_006` Lithography/material science contract failed.

## Gate Policy

`scripts/validate_mac_cell_stacks_tsd.sh` is the executable validator for this TSD.

- Sprout MUST execute this validator before IQ.
- Any refusal code MUST stop progression to IQ/OQ/PQ.
