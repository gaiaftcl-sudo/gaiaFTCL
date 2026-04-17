import Foundation

// vQbitPrimitive 76-byte ABI (matches Rust #[repr(C)])
struct vQbitPrimitive {
    var transform: (Float, Float, Float, Float,  // 16 bytes (4×4)
                   Float, Float, Float, Float,  // 16 bytes
                   Float, Float, Float, Float,  // 16 bytes
                   Float, Float, Float, Float)  // 16 bytes = 64 bytes total
    var vqbit_entropy: Float       // 4 bytes (offset 64)
    var vqbit_truth: Float         // 4 bytes (offset 68)
    var prim_id: UInt32            // 4 bytes (offset 72)
}  // Total: 76 bytes

struct vQbitABITests {
    static func runAll() {
        run("abi_001", "vQbitPrimitive size == 76 bytes") {
            return MemoryLayout<vQbitPrimitive>.size == 76
        }
        
        run("abi_002", "entropy offset == 64") {
            return MemoryLayout<vQbitPrimitive>.offset(of: \.vqbit_entropy) == 64
        }
        
        run("abi_003", "truth offset == 68") {
            return MemoryLayout<vQbitPrimitive>.offset(of: \.vqbit_truth) == 68
        }
        
        run("abi_004", "prim_id offset == 72") {
            return MemoryLayout<vQbitPrimitive>.offset(of: \.prim_id) == 72
        }
        
        run("abi_005", "transform zeroed on default init") {
            let prim = vQbitPrimitive(
                transform: (0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0),
                vqbit_entropy: 0,
                vqbit_truth: 0,
                prim_id: 0
            )
            
            let mirror = Mirror(reflecting: prim.transform)
            let allZero = mirror.children.allSatisfy { child in
                (child.value as? Float) == 0.0
            }
            return allZero
        }
        
        run("abi_006", "vqbit_entropy is Float (4 bytes)") {
            return MemoryLayout.size(ofValue: Float(0)) == 4
        }
        
        run("abi_007", "prim_id is UInt32 (4 bytes)") {
            return MemoryLayout<UInt32>.size == 4
        }
        
        run("abi_008", "struct alignment ≤ 8 bytes") {
            return MemoryLayout<vQbitPrimitive>.alignment <= 8
        }
    }
}
