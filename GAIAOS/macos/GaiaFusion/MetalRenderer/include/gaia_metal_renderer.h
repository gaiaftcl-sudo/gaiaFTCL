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

#endif  /* GAIA_METAL_RENDERER_H */
