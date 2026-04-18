use std::panic::{catch_unwind, AssertUnwindSafe};
use std::os::raw::{c_char, c_void};
use std::ffi::CStr;
use std::ptr;

use vqbit_usd_parser::parse_usd_file;
use crate::renderer::MetalRenderer;

// Re-export vQbitPrimitive for cbindgen
#[repr(C)]
#[derive(Copy, Clone, Debug)]
pub struct vQbitPrimitive {
    pub transform: [[f32; 4]; 4],
    pub vqbit_entropy: f32,
    pub vqbit_truth: f32,
    pub prim_id: u32,
}

// Gap #5 Fix: CAMetalLayer ownership contract
// Swift calls: Unmanaged.passUnretained(metalLayer).toOpaque()
// Rust borrows the layer; Swift owns it and must keep it alive
// for the full lifetime of this MetalRenderer.
// Gap #3 Fix: Panic safety with catch_unwind
#[no_mangle]
pub extern "C" fn gaia_metal_renderer_create(layer: *mut c_void) -> *mut MetalRenderer {
    let result = catch_unwind(|| {
        if layer.is_null() {
            return ptr::null_mut();
        }
        // MetalRenderer::new_from_layer borrows the CAMetalLayer raw pointer
        match MetalRenderer::new_from_layer(layer) {
            Ok(renderer) => Box::into_raw(Box::new(renderer)),
            Err(_) => ptr::null_mut(),
        }
    });
    result.unwrap_or(ptr::null_mut())
}

// Gap #2 Fix: Destroy to reclaim Box<MetalRenderer>
#[no_mangle]
pub extern "C" fn gaia_metal_renderer_destroy(renderer: *mut MetalRenderer) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if !renderer.is_null() {
            unsafe {
                let _ = Box::from_raw(renderer);  // Drop and free
            }
        }
    }));
}

#[no_mangle]
pub extern "C" fn gaia_metal_renderer_render_frame(renderer: *mut MetalRenderer, width: u32, height: u32) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| {
        if renderer.is_null() {
            return -1;
        }
        unsafe {
            (*renderer).render_frame(width, height);
            0
        }
    }));
    result.unwrap_or(-1)
}

#[no_mangle]
pub extern "C" fn gaia_metal_renderer_resize(renderer: *mut MetalRenderer, width: u32, height: u32) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if !renderer.is_null() {
            unsafe {
                (*renderer).resize(width, height);
            }
        }
    }));
}

// Gap #8 Fix: Buffer allocation contract documented
// Swift must allocate: UnsafeMutablePointer<vQbitPrimitive>.allocate(capacity: max_prims)
// Rust writes into prims_out up to max_prims slots.
// Swift must deallocate after use: prims_out.deallocate()
// Returns: actual number of primitives written (may be < max_prims).
#[no_mangle]
pub extern "C" fn gaia_metal_parse_usd(
    path: *const c_char,
    prims_out: *mut vQbitPrimitive,
    max_prims: usize
) -> usize {
    let result = catch_unwind(|| {
        if path.is_null() || prims_out.is_null() || max_prims == 0 {
            return 0;
        }
        let path_str = unsafe {
            match CStr::from_ptr(path).to_str() {
                Ok(s) => s,
                Err(_) => return 0,
            }
        };
        let prims = match parse_usd_file(path_str) {
            Ok(p) => p,
            Err(_) => return 0,
        };
        let count = prims.len().min(max_prims);
        unsafe {
            // Convert from parser's vQbitPrimitive to our FFI vQbitPrimitive
            for i in 0..count {
                let src = &prims[i];
                let dst = &mut *prims_out.add(i);
                dst.transform = src.transform;
                dst.vqbit_entropy = src.vqbit_entropy;
                dst.vqbit_truth = src.vqbit_truth;
                dst.prim_id = src.prim_id;
            }
        }
        count
    });
    result.unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn gaia_metal_renderer_shell_world_matrix(
    renderer: *mut MetalRenderer,
    out16: *mut f32
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| {
        if renderer.is_null() || out16.is_null() {
            return -1;
        }
        unsafe {
            let matrix = (*renderer).get_shell_world_matrix();
            ptr::copy_nonoverlapping(matrix.as_ptr(), out16, 16);
        }
        0
    }));
    result.unwrap_or(-1)
}

#[no_mangle]
pub extern "C" fn gaia_metal_renderer_upload_primitives(
    renderer: *mut MetalRenderer,
    prims: *const vQbitPrimitive,
    count: usize
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| {
        if renderer.is_null() || prims.is_null() || count == 0 {
            return -1;
        }
        unsafe {
            // Convert from FFI vQbitPrimitive to parser's vQbitPrimitive
            let slice = std::slice::from_raw_parts(prims, count);
            let mut converted = Vec::with_capacity(count);
            for p in slice {
                converted.push(vqbit_usd_parser::vQbitPrimitive {
                    transform: p.transform,
                    vqbit_entropy: p.vqbit_entropy,
                    vqbit_truth: p.vqbit_truth,
                    prim_id: p.prim_id,
                });
            }
            (*renderer).upload_geometry_from_primitives(&converted);
            0
        }
    }));
    result.unwrap_or(-1)
}

#[no_mangle]
pub extern "C" fn gaia_metal_renderer_set_tau(
    renderer: *mut MetalRenderer,
    block_height: u64
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| {
        if renderer.is_null() {
            return -1;
        }
        unsafe {
            (*renderer).set_tau(block_height);
        }
        0
    }));
    result.unwrap_or(-1)
}

#[no_mangle]
pub extern "C" fn gaia_metal_renderer_get_tau(
    renderer: *mut MetalRenderer
) -> u64 {
    let result = catch_unwind(AssertUnwindSafe(|| {
        if renderer.is_null() {
            return 0;
        }
        unsafe { (*renderer).get_tau() }
    }));
    result.unwrap_or(0)
}

/// Get last frame render time in microseconds
/// Patent requirement USPTO 19/460,960: <3000 μs with precompiled shaders
#[no_mangle]
pub extern "C" fn gaia_metal_renderer_get_frame_time_us(
    renderer: *mut MetalRenderer
) -> u64 {
    let result = catch_unwind(AssertUnwindSafe(|| {
        if renderer.is_null() {
            return 0;
        }
        unsafe { (*renderer).get_frame_time_us() }
    }));
    result.unwrap_or(0)
}

/// Switch to a different plant kind geometry
/// plant_kind_id: 0=Tokamak, 1=Stellarator, 2=FRC, 3=Spheromak, 4=Mirror,
///                5=Inertial, 6=SphericalTokamak, 7=ZPinch, 8=MIF
/// Returns: 0 on success, -1 on invalid plant_kind_id, -2 on null renderer
#[no_mangle]
pub extern "C" fn gaia_metal_renderer_switch_plant(
    renderer: *mut MetalRenderer,
    plant_kind_id: u32
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| {
        if renderer.is_null() {
            return -2;
        }
        unsafe {
            if (*renderer).switch_plant(plant_kind_id) {
                0 // Success
            } else {
                -1 // Invalid plant_kind_id
            }
        }
    }));
    result.unwrap_or(-1)
}

/// Set base wireframe color (WASM constitutional state visualization)
/// r, g, b, a: 0.0-1.0 color components
/// Returns: 0 on success, -1 on null renderer
#[no_mangle]
pub extern "C" fn gaia_metal_renderer_set_base_color(
    renderer: *mut MetalRenderer,
    r: f32, g: f32, b: f32, a: f32
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| {
        if renderer.is_null() {
            return -1;
        }
        unsafe {
            (*renderer).set_base_color([r, g, b, a]);
            0
        }
    }));
    result.unwrap_or(-1)
}

/// Set plasma state for volume rendering inside wireframe
/// density: plasma density (particles/m³)
/// temperature: plasma temperature (keV)
/// magnetic_field: magnetic field strength (Tesla)
/// opacity: plasma volume opacity 0.0-1.0
/// Enable plasma particles (Phase 7: RUNNING/CONSTITUTIONAL_ALARM only)
#[no_mangle]
pub extern "C" fn gaia_metal_renderer_enable_plasma(renderer: *mut MetalRenderer) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if !renderer.is_null() {
            unsafe {
                (*renderer).enable_plasma();
            }
        }
    }));
}

/// Disable plasma particles and clear buffer (Phase 7: state exit)
#[no_mangle]
pub extern "C" fn gaia_metal_renderer_disable_plasma(renderer: *mut MetalRenderer) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if !renderer.is_null() {
            unsafe {
                (*renderer).disable_plasma();
            }
        }
    }));
}

/// Returns: 0 on success, -1 on null renderer
#[no_mangle]
pub extern "C" fn gaia_metal_renderer_set_plasma_state(
    renderer: *mut MetalRenderer,
    density: f32,
    temperature: f32,
    magnetic_field: f32,
    opacity: f32
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| {
        if renderer.is_null() {
            return -1;
        }
        unsafe {
            (*renderer).set_plasma_state(density, temperature, magnetic_field, opacity);
            0
        }
    }));
    result.unwrap_or(-1)
}
