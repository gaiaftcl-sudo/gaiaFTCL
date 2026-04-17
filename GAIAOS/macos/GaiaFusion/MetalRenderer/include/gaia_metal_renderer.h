#ifndef GAIA_METAL_RENDERER_H
#define GAIA_METAL_RENDERER_H

#pragma once

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

typedef struct MetalRenderer MetalRenderer;

typedef struct vQbitPrimitive {
  float transform[4][4];
  float vqbit_entropy;
  float vqbit_truth;
  uint32_t prim_id;
} vQbitPrimitive;

struct MetalRenderer *gaia_metal_renderer_create(void *layer);

void gaia_metal_renderer_destroy(struct MetalRenderer *renderer);

int32_t gaia_metal_renderer_render_frame(struct MetalRenderer *renderer,
                                         uint32_t width,
                                         uint32_t height);

void gaia_metal_renderer_resize(struct MetalRenderer *renderer, uint32_t width, uint32_t height);

uintptr_t gaia_metal_parse_usd(const char *path,
                               struct vQbitPrimitive *prims_out,
                               uintptr_t max_prims);

int32_t gaia_metal_renderer_shell_world_matrix(struct MetalRenderer *renderer, float *out16);

int32_t gaia_metal_renderer_upload_primitives(struct MetalRenderer *renderer,
                                              const struct vQbitPrimitive *prims,
                                              uintptr_t count);

int32_t gaia_metal_renderer_set_tau(struct MetalRenderer *renderer, uint64_t block_height);

uint64_t gaia_metal_renderer_get_tau(struct MetalRenderer *renderer);

/**
 * Get last frame render time in microseconds
 * Patent requirement USPTO 19/460,960: <3000 μs with precompiled shaders
 */
uint64_t gaia_metal_renderer_get_frame_time_us(struct MetalRenderer *renderer);

/**
 * Switch to a different plant kind geometry
 * plant_kind_id: 0=Tokamak, 1=Stellarator, 2=FRC, 3=Spheromak, 4=Mirror,
 *                5=Inertial, 6=SphericalTokamak, 7=ZPinch, 8=MIF
 * Returns: 0 on success, -1 on invalid plant_kind_id, -2 on null renderer
 */
int32_t gaia_metal_renderer_switch_plant(struct MetalRenderer *renderer, uint32_t plant_kind_id);

/**
 * Set base wireframe color (WASM constitutional state visualization)
 * r, g, b, a: 0.0-1.0 color components
 * Returns: 0 on success, -1 on null renderer
 */
int32_t gaia_metal_renderer_set_base_color(struct MetalRenderer *renderer,
                                           float r,
                                           float g,
                                           float b,
                                           float a);

/**
 * Set plasma state for volume rendering inside wireframe
 * density: plasma density (particles/m³)
 * temperature: plasma temperature (keV)
 * magnetic_field: magnetic field strength (Tesla)
 * opacity: plasma volume opacity 0.0-1.0
 * Enable plasma particles (Phase 7: RUNNING/CONSTITUTIONAL_ALARM only)
 */
void gaia_metal_renderer_enable_plasma(struct MetalRenderer *renderer);

/**
 * Disable plasma particles and clear buffer (Phase 7: state exit)
 */
void gaia_metal_renderer_disable_plasma(struct MetalRenderer *renderer);

/**
 * Returns: 0 on success, -1 on null renderer
 */
int32_t gaia_metal_renderer_set_plasma_state(struct MetalRenderer *renderer,
                                             float density,
                                             float temperature,
                                             float magnetic_field,
                                             float opacity);

#endif  /* GAIA_METAL_RENDERER_H */
