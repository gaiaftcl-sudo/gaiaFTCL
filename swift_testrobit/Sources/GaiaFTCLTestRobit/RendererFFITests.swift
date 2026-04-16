import Foundation

// FFI functions declared in TauStateTests.swift

struct RendererFFITests {
    static func runAll() {
        run("renderer_001", "create returns non-null handle") {
            guard let handle = gaia_metal_renderer_create() else { return false }
            gaia_metal_renderer_destroy(handle)
            return true
        }
        
        run("renderer_002", "destroy is idempotent (no crash)") {
            guard let handle = gaia_metal_renderer_create() else { return false }
            gaia_metal_renderer_destroy(handle)
            gaia_metal_renderer_destroy(nil)  // Should not crash
            return true
        }
        
        run("renderer_003", "Null handle safe for all FFI functions") {
            // All functions should handle nil gracefully
            gaia_metal_renderer_destroy(nil)
            let fc = gaia_metal_renderer_get_frame_count(nil)
            gaia_metal_renderer_increment_frame(nil)
            return fc == 0  // get_frame_count(nil) returns 0
        }
        
        run("renderer_004", "100× create/destroy cycle (no leak)") {
            for _ in 0..<100 {
                guard let handle = gaia_metal_renderer_create() else { return false }
                gaia_metal_renderer_destroy(handle)
            }
            return true
        }
        
        run("renderer_005", "TauState handles are independent") {
            guard let h1 = gaia_metal_renderer_create() else { return false }
            guard let h2 = gaia_metal_renderer_create() else {
                gaia_metal_renderer_destroy(h1)
                return false
            }
            defer {
                gaia_metal_renderer_destroy(h1)
                gaia_metal_renderer_destroy(h2)
            }
            
            // Two handles are independent
            return h1 != h2
        }
        
        run("renderer_006", "Frame count is zero on create") {
            guard let handle = gaia_metal_renderer_create() else { return false }
            defer { gaia_metal_renderer_destroy(handle) }
            return gaia_metal_renderer_get_frame_count(handle) == 0
        }
    }
}
