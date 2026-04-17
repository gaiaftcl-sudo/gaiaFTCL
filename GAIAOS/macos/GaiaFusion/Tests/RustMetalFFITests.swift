import XCTest
@testable import GaiaFusion
import GaiaMetalRenderer
import Metal
import QuartzCore

final class RustMetalFFITests: XCTestCase {
    func testFFIPointerNotNull() {
        // Gap #5: Mock CAMetalLayer for test
        let layer = CAMetalLayer()
        let ptr = Unmanaged.passUnretained(layer).toOpaque()
        let rendererPtr = gaia_metal_renderer_create(ptr)
        XCTAssertNotNil(rendererPtr, "Renderer pointer should not be null")
        if let ptr = rendererPtr {
            gaia_metal_renderer_destroy(ptr)  // Gap #2: Clean up
        }
    }
    
    func testFFIPanicSafety() {
        // Gap #3: Verify null inputs don't crash
        let result = gaia_metal_renderer_create(nil)
        XCTAssertNil(result, "Should return null for nil layer")
        
        let parseResult = gaia_metal_parse_usd(nil, nil, 0)
        XCTAssertEqual(parseResult, 0, "Should return 0 for invalid inputs")
    }
    
    func testParseUSDBasic() {
        // Gap #8: Allocate buffer
        let maxPrims = 16
        let buffer = UnsafeMutablePointer<vQbitPrimitive>.allocate(capacity: maxPrims)
        defer { buffer.deallocate() }
        
        // Create a temporary USD file for testing
        let testUSD = """
        #usda 1.0
        def "World" {
            def Scope "Cell1" {
                float custom_vQbit:entropy_delta = 0.5
                float custom_vQbit:truth_threshold = 0.9
            }
        }
        """
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).usda")
        try? testUSD.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let count = tempURL.path.withCString { pathPtr in
            gaia_metal_parse_usd(pathPtr, buffer, UInt(maxPrims))
        }
        
        XCTAssertEqual(count, 1, "Should parse one primitive")
        if count >= 1 {
            XCTAssertEqual(buffer[0].vqbit_entropy, 0.5, accuracy: 0.001)
            XCTAssertEqual(buffer[0].vqbit_truth, 0.9, accuracy: 0.001)
        }
    }
    
    func testMetalPQOffscreenRender() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            XCTFail("No Metal GPU — PQ FAIL")
            return
        }
        guard let queue = device.makeCommandQueue() else {
            XCTFail("MTLCommandQueue creation failed")
            return
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .managed
        guard let tex = device.makeTexture(descriptor: desc) else {
            XCTFail("MTLTexture creation failed"); return
        }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = tex
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1.0) // Tokamak M
        rpd.colorAttachments[0].storeAction = .store
        let cmd = queue.makeCommandBuffer()!
        let enc = cmd.makeRenderCommandEncoder(descriptor: rpd)!
        enc.endEncoding(); cmd.commit(); cmd.waitUntilCompleted()
        let sync = queue.makeCommandBuffer()!
        let blit = sync.makeBlitCommandEncoder()!
        blit.synchronize(resource: tex); blit.endEncoding(); sync.commit(); sync.waitUntilCompleted()
        var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
        tex.getBytes(&pixels, bytesPerRow: 64 * 4,
                     from: MTLRegionMake2D(0, 0, 64, 64), mipmapLevel: 0)
        let nonZero = pixels.filter { $0 > 0 }.count
        XCTAssertGreaterThan(nonZero, 0, "Metal render produced all-zero pixels — GPU pipeline broken")
        // Write PQ receipt
        let receipt: [String: Any] = [
            "spec": "GFTCL-PQ-MACFUSION-001",
            "phase": "PQ",
            "cell": "MacFusion",
            "metal_device_name": device.name,
            "nonzero_pixels": nonZero,
            "pq_status": nonZero > 0 ? "PASS" : "FAIL",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "pii_stored": false,
        ]
        let path = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()    // Tests/
            .deletingLastPathComponent()    // GaiaFusion/
            .appendingPathComponent("evidence/pq/macfusion_pq_receipt.json")
        try? FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONSerialization.data(withJSONObject: receipt, options: .prettyPrinted)
                             .write(to: path)
        print("MacFusion PQ receipt: \(path.path)")
    }
}
