// GaiaFTCL Metal Renderer — C FFI Header
// Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie
// Regenerate: cbindgen --config cbindgen.toml --crate gaia_metal_renderer --output gaia_metal_renderer.h

#ifndef GAIA_METAL_RENDERER_H
#define GAIA_METAL_RENDERER_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Opaque handle to a GaiaFTCL TauState instance.
 * GaiaFusion Swift stores this as UnsafeMutableRawPointer.
 */
typedef void *GaiaRendererHandle;

/**
 * Create a new TauState. Returns opaque handle.
 * Caller takes ownership — must call gaia_metal_renderer_destroy exactly once.
 * Returns NULL on allocation failure (extremely rare).
 */
GaiaRendererHandle gaia_metal_renderer_create(void);

/**
 * Destroy a TauState. Frees heap memory.
 * handle must be a valid non-null pointer returned by gaia_metal_renderer_create.
 * After this call, handle is dangling — do not use.
 * Safe to call with NULL (no-op).
 */
void gaia_metal_renderer_destroy(GaiaRendererHandle handle);

/**
 * Set τ — Bitcoin block height (sovereign consensus time).
 * Thread-safe. Call on each gaiaftcl.bitcoin.heartbeat NATS message (~every 10 min).
 * block_height = 0 means genesis / pre-sync.
 */
void gaia_metal_renderer_set_tau(GaiaRendererHandle handle, uint64_t block_height);

/**
 * Get current τ (Bitcoin block height).
 * Thread-safe. Returns 0 if handle is NULL or τ not yet set.
 */
uint64_t gaia_metal_renderer_get_tau(GaiaRendererHandle handle);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* GAIA_METAL_RENDERER_H */
