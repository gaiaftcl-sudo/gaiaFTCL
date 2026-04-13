import XCTest
@testable import GaiaFusion
import GaiaMetalRenderer

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
}
