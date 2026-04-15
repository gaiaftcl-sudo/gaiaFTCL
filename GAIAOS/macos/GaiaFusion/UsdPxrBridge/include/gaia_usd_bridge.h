#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/// Returns 1 if `pxr::UsdStage::CreateInMemory()` yields a valid stage, else 0.
int gaia_usd_inmemory_stage_probe(void);

/// Monolithic USD `PXR_VERSION` integer (see `pxr/pxr.h`), e.g. 2605 for 0.26.5.
int gaia_usd_pxr_version_int(void);

/// 1 if an in-memory stage can define `/PlantControlViewport` as `UsdGeomXform`, else 0.
int gaia_usd_plant_control_viewport_prim_probe(void);

/// 1 if `/World/Facility/TokamakNSTX_U` xform chain + `/PlantControlViewport` bootstrap in one in-memory stage.
int gaia_usd_boot_facility_tokamak_probe(void);

/// Open a USD root layer from disk for playback (replaces prior playback stage handle).
/// Returns 1 on success.
int gaia_usd_open_stage_from_file(const char* path_utf8);

/// Authoritative playback clock for sampling (must match SetTime).
void gaia_usd_stage_set_time(double time_code);

/// Scalar witness for Metal clear / health (samples `/World/Facility/Shell` local X at current time).
double gaia_usd_playback_visual_proxy(void);

/// Set `UsdGeomImageable` visibility on an arbitrary prim path (playback stage only). Returns 1 on success.
int gaia_usd_prim_visibility_set(const char* path_utf8, int visible);

/// SubGame Z: show (1) or hide (0) `/World/Cell4Diagnostic` via UsdGeomImageable visibility.
int gaia_usd_cell4_diagnostic_set_visible(int visible);

/// Column-major `float4x4` (16 floats) for Metal: `UsdGeomXformable::ComputeLocalToWorldTransform` at playback time.
/// Returns 1 on success, 0 if stage or prim missing.
int gaia_usd_shell_world_matrix_float4x4(float* out_column_major_16);

/// Release playback stage handle (between DRAINING → load).
void gaia_usd_close_playback_stage(void);

#ifdef __cplusplus
}
#endif
