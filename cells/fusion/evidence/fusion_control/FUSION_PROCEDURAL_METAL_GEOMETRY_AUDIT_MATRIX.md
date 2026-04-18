# Procedural Metal fusion geometry — audit matrix (C4)

**Receipt:** vocabulary lock for `plant_kind`, USD bundle, and Metal wireframe behavior.  
**Schema:** `gaiaftcl_native_fusion_plant_adapters_v1` — [`cells/fusion/spec/native_fusion/plant_adapters.json`](../../spec/native_fusion/plant_adapters.json).  
**Geometry:** [`FusionFacilityWireframeGeometry.swift`](../../macos/GaiaFusion/GaiaFusion/OpenUSD/FusionFacilityWireframeGeometry.swift).  
**Renderer:** [`OpenUSDMetalProxyRenderer.swift`](../../macos/GaiaFusion/GaiaFusion/OpenUSD/OpenUSDMetalProxyRenderer.swift) (per-kind `MTLBuffer`, USD Shell MVP).  
**SubGame Y:** [`OpenUSDProxy.metal`](../../macos/GaiaFusion/GaiaFusion/Shaders/OpenUSDProxy.metal) — `plantKindIndex`, `normalizedT`, `telemetryIp`, `telemetryBt`, `telemetryNe` (fragment modulation; no filled plasma pass). Receipt: [`SUBGAME_Y_WIREFRAME_UNIFORMS_RECEIPT.json`](SUBGAME_Y_WIREFRAME_UNIFORMS_RECEIPT.json).

**LOD:** `FusionFacilityWireframeGeometry.WireframeLOD` — viewport min dimension &lt; 420pt uses reduced segments / icosphere level / beam count; `OpenUSDMetalProxyRenderer` caches per `(plantKind, lod)`.

## Topology vs `plant_kind` vs USD vs Metal

| Spec topology | Canonical `plant_kind` | USD bundle (`usd/plants/<kind>/`) | Metal geometry (2026-04) | Gap / notes |
|---------------|------------------------|-------------------------------------|----------------------------|-------------|
| Tokamak | `tokamak` | `root.usda` + `timeline_v2.json` | Nested torus + PF rings + meridional TF polylines | HdStorm CAD mesh still parallel track; Shell remains empty Xform. |
| Spherical tokamak | `spherical_tokamak` | `root.usda` + `timeline_v2.json` | Lat/long sphere + hole ring + solenoid lines + asymmetric TF loop | Same. |
| Stellarator | `stellarator` | yes | Twisted torus grid + modular coil polylines | Same. |
| ICF / laser | `inertial` (alias `icf`) | yes | Icosphere L2 + hohlraum cylinder + 192 Fibonacci beamlines to origin | Volume plasma not in wire pass; fragment pulse only. |
| FRC | `frc` | yes | Cylinder + stacked end rings + center confinement rings | Same. |
| Magnetic mirror | `mirror` | yes | Cylinder + central sparse rings + stacked choke rings | Same. |
| Z-pinch | `z_pinch` | yes | Cylinder + end electrodes / radial spokes | Same. |
| Spheromak | `spheromak` | yes | Sphere grid + coax gun stub + injector beam segment | Same. |
| MIF / PJMIF | `mif` (alias `pjmif`) | yes | Icosphere + radial gun segments (Fibonacci sites) | Same. |

## Prior gap (pre-implementation) vs closed

| Item | Before | After |
|------|--------|--------|
| Metal proxy | Single 12-edge cube for all plants | Per-`PlantType` line list; buffer rebuild on kind change |
| Catalog | 6 kinds in JSON | 9 kinds + aliases `icf`→`inertial`, `pjmif`→`mif` |
| Shaders | Solid line color only | SubGame Y: kind + `normalized_t` + `B_T`/`n_e` tint branches (wireframe) |

## Non-goals (unchanged)

- Full **HdStorm** facility mesh — see [`docs/GAIAFUSION_USD_HYDRA_LINK.md`](../../docs/GAIAFUSION_USD_HYDRA_LINK.md).
- Replacing USD time/transform authority with pure Metal physics.

**HTTP:** `GET /api/fusion/plant-kinds` returns `kinds`, `count`, and `aliases` (`icf`→`inertial`, `pjmif`→`mif`, …) from [`PlantKindsCatalog.kindAliases`](../../macos/GaiaFusion/GaiaFusion/Models/PlantKindsCatalog.swift).

**Web (Fusion S⁴):** [`fusionGlobalI18n.ts`](../../services/gaiaos_ui_web/app/fusion-s4/fusionGlobalI18n.ts) — `resolveCanonicalPlantKind` / `getPlantDisplayName` mirror those aliases; [`page.tsx`](../../services/gaiaos_ui_web/app/fusion-s4/page.tsx) canonicalizes mesh `input`/`output` through the same map so cells can ship alias strings without breaking `normalizedKinds` checks.

Norwich — S⁴ serves C⁴.
