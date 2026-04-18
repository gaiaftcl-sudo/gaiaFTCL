import Foundation
import Metal
import MetalKit
import simd
import GaiaMetalRenderer

/// Rust Metal renderer proxy - replaces OpenUSD with lightweight Rust FFI
final class RustMetalProxyRenderer {
    private var rendererPtr: OpaquePointer?
    private var metalLayer: CAMetalLayer  // Strong reference - Swift owns this
    
    init(layer: CAMetalLayer) {
        self.metalLayer = layer
        // Gap #5: Pass unretained pointer - Rust borrows, Swift owns
        let layerPtr = Unmanaged.passUnretained(layer).toOpaque()
        self.rendererPtr = gaia_metal_renderer_create(layerPtr)
        guard rendererPtr != nil else {
            fatalError("Failed to create Rust Metal renderer")
        }
    }
    
    deinit {
        // Gap #2: Explicit destroy call
        if let ptr = rendererPtr {
            gaia_metal_renderer_destroy(ptr)
        }
    }
    
    func renderFrame(width: UInt32, height: UInt32) {
        guard let ptr = rendererPtr else { return }
        let result = gaia_metal_renderer_render_frame(ptr, width, height)
        if result != 0 {
            print("Render frame failed: \(result)")
        }
    }
    
    func resize(width: UInt32, height: UInt32) {
        guard let ptr = rendererPtr else { return }
        gaia_metal_renderer_resize(ptr, width, height)
    }
    
    func shellWorldMatrix() -> simd_float4x4 {
        guard let ptr = rendererPtr else { return matrix_identity_float4x4 }
        var mat = [Float](repeating: 0, count: 16)
        let result = mat.withUnsafeMutableBufferPointer { buf in
            gaia_metal_renderer_shell_world_matrix(ptr, buf.baseAddress!)
        }
        if result != 0 {
            return matrix_identity_float4x4
        }
        return simd_float4x4(columns: (
            SIMD4<Float>(mat[0], mat[1], mat[2], mat[3]),
            SIMD4<Float>(mat[4], mat[5], mat[6], mat[7]),
            SIMD4<Float>(mat[8], mat[9], mat[10], mat[11]),
            SIMD4<Float>(mat[12], mat[13], mat[14], mat[15])
        ))
    }
    
    func uploadPrimitives(_ prims: [vQbitPrimitive]) {
        guard let ptr = rendererPtr else { return }
        prims.withUnsafeBufferPointer { buf in
            let result = gaia_metal_renderer_upload_primitives(ptr, buf.baseAddress!, UInt(buf.count))
            if result != 0 {
                print("Failed to upload primitives: \(result)")
            }
        }
    }
    
    func setTau(_ blockHeight: UInt64) {
        guard let ptr = rendererPtr else { return }
        let result = gaia_metal_renderer_set_tau(ptr, blockHeight)
        if result != 0 {
            print("Failed to set tau: \(result)")
        }
    }
    
    func getTau() -> UInt64 {
        guard let ptr = rendererPtr else { return 0 }
        return gaia_metal_renderer_get_tau(ptr)
    }
    
    /// Get last frame render time in microseconds
    /// Patent requirement USPTO 19/460,960: <3000 μs with precompiled shaders
    func getFrameTimeUs() -> UInt64 {
        guard let ptr = rendererPtr else { return 0 }
        return gaia_metal_renderer_get_frame_time_us(ptr)
    }
    
    /// Enable plasma particle rendering
    func enablePlasma() {
        guard let ptr = rendererPtr else { return }
        // FFI function will be implemented in Rust library
        // gaia_metal_renderer_enable_plasma(ptr)
        print("enablePlasma() called - Rust FFI not yet wired")
    }
    
    /// Disable plasma particle rendering
    func disablePlasma() {
        guard let ptr = rendererPtr else { return }
        // FFI function will be implemented in Rust library
        // gaia_metal_renderer_disable_plasma(ptr)
        print("disablePlasma() called - Rust FFI not yet wired")
    }
    
    /// Update the Metal drawable size when viewport geometry changes
    func updateDrawableSize(_ size: CGSize) {
        resize(width: UInt32(size.width), height: UInt32(size.height))
    }
    
    /// Set the base wireframe color (RGBA normalized 0-1)
    func setWireframeBaseColor(_ rgba: [Float]) {
        guard let ptr = rendererPtr, rgba.count >= 4 else { return }
        // FFI function will be implemented in Rust library
        // rgba.withUnsafeBufferPointer { buf in
        //     gaia_metal_renderer_set_wireframe_color(ptr, buf.baseAddress!)
        // }
        print("setWireframeBaseColor(\(rgba)) called - Rust FFI not yet wired")
    }
}
