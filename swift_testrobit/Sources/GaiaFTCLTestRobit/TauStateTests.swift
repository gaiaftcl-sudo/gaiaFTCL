import Foundation

// FFI imports (matching Rust lib.rs exports)
@_silgen_name("gaia_metal_renderer_create")
func gaia_metal_renderer_create() -> OpaquePointer?

@_silgen_name("gaia_metal_renderer_destroy")
func gaia_metal_renderer_destroy(_: OpaquePointer?)

@_silgen_name("gaia_metal_renderer_set_tau")
func gaia_metal_renderer_set_tau(_: OpaquePointer?, _: UInt64)

@_silgen_name("gaia_metal_renderer_get_tau")
func gaia_metal_renderer_get_tau(_: OpaquePointer?) -> UInt64

@_silgen_name("gaia_metal_renderer_get_frame_count")
func gaia_metal_renderer_get_frame_count(_: OpaquePointer?) -> UInt64

@_silgen_name("gaia_metal_renderer_increment_frame")
func gaia_metal_renderer_increment_frame(_: OpaquePointer?)

@_silgen_name("gaia_metal_renderer_set_epistemic")
func gaia_metal_renderer_set_epistemic(_: OpaquePointer?, _: UInt32)

@_silgen_name("gaia_metal_renderer_get_epistemic")
func gaia_metal_renderer_get_epistemic(_: OpaquePointer?) -> UInt32

struct TauStateTests {
    static func runAll() {
        run("tau_001", "Initial τ is zero on create") {
            guard let handle = gaia_metal_renderer_create() else { return false }
            defer { gaia_metal_renderer_destroy(handle) }
            return gaia_metal_renderer_get_tau(handle) == 0
        }
        
        run("tau_002", "set_tau → get_tau roundtrip") {
            guard let handle = gaia_metal_renderer_create() else { return false }
            defer { gaia_metal_renderer_destroy(handle) }
            gaia_metal_renderer_set_tau(handle, 100)
            return gaia_metal_renderer_get_tau(handle) == 100
        }
        
        run("tau_003", "Large block height (870,000)") {
            guard let handle = gaia_metal_renderer_create() else { return false }
            defer { gaia_metal_renderer_destroy(handle) }
            gaia_metal_renderer_set_tau(handle, 870_000)
            return gaia_metal_renderer_get_tau(handle) == 870_000
        }
        
        run("tau_004", "Set τ to zero") {
            guard let handle = gaia_metal_renderer_create() else { return false }
            defer { gaia_metal_renderer_destroy(handle) }
            gaia_metal_renderer_set_tau(handle, 42)
            gaia_metal_renderer_set_tau(handle, 0)
            return gaia_metal_renderer_get_tau(handle) == 0
        }
        
        run("tau_005", "Sequential updates → latest value") {
            guard let handle = gaia_metal_renderer_create() else { return false }
            defer { gaia_metal_renderer_destroy(handle) }
            gaia_metal_renderer_set_tau(handle, 10)
            gaia_metal_renderer_set_tau(handle, 20)
            gaia_metal_renderer_set_tau(handle, 30)
            return gaia_metal_renderer_get_tau(handle) == 30
        }
        
        run("tau_006", "Null handle set_tau is safe (no crash)") {
            gaia_metal_renderer_set_tau(nil, 100)
            return true
        }
        
        run("tau_007", "Null handle get_tau returns 0") {
            return gaia_metal_renderer_get_tau(nil) == 0
        }
        
        run("tau_008", "Max block height (UInt64.max)") {
            guard let handle = gaia_metal_renderer_create() else { return false }
            defer { gaia_metal_renderer_destroy(handle) }
            gaia_metal_renderer_set_tau(handle, UInt64.max)
            return gaia_metal_renderer_get_tau(handle) == UInt64.max
        }
        
        run("tau_009", "Create → set → get → destroy lifecycle") {
            guard let handle = gaia_metal_renderer_create() else { return false }
            gaia_metal_renderer_set_tau(handle, 42)
            let value = gaia_metal_renderer_get_tau(handle)
            gaia_metal_renderer_destroy(handle)
            return value == 42
        }
        
        run("tau_010", "Two handles have independent τ values") {
            guard let h1 = gaia_metal_renderer_create() else { return false }
            guard let h2 = gaia_metal_renderer_create() else {
                gaia_metal_renderer_destroy(h1)
                return false
            }
            defer {
                gaia_metal_renderer_destroy(h1)
                gaia_metal_renderer_destroy(h2)
            }
            
            gaia_metal_renderer_set_tau(h1, 100)
            gaia_metal_renderer_set_tau(h2, 200)
            
            return gaia_metal_renderer_get_tau(h1) == 100 && 
                   gaia_metal_renderer_get_tau(h2) == 200
        }
    }
}
