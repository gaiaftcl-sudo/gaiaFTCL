// MacHealthTests.swift — MacHealth unit tests
// Fast tests only — all complete in <5 seconds
// Patents: USPTO 19/460,960 | USPTO 19/096,071

import XCTest
import Metal
import QuartzCore
@testable import MacHealth
import GaiaHealthRenderer

final class MacHealthTests: XCTestCase {

    // FFI lifecycle
    func testRendererCreateDestroy() {
        let h = gaia_health_renderer_create()
        XCTAssertNotNil(h, "Renderer create must return non-nil")
        if let h = h {
            gaia_health_renderer_destroy(h)
        }
    }

    func testEpistemicRoundTrip() {
        guard let h = gaia_health_renderer_create() else {
            XCTFail("Renderer create returned nil")
            return
        }
        defer { gaia_health_renderer_destroy(h) }
        gaia_health_renderer_set_epistemic(h, 0)
        XCTAssertEqual(gaia_health_renderer_get_epistemic(h), 0) // Measured
        gaia_health_renderer_set_epistemic(h, 1)
        XCTAssertEqual(gaia_health_renderer_get_epistemic(h), 1) // Inferred
        gaia_health_renderer_set_epistemic(h, 2)
        XCTAssertEqual(gaia_health_renderer_get_epistemic(h), 2) // Assumed
    }

    func testFrameCountIncrements() {
        guard let h = gaia_health_renderer_create() else {
            XCTFail("Renderer create returned nil")
            return
        }
        defer { gaia_health_renderer_destroy(h) }
        gaia_health_renderer_tick_frame(h)
        gaia_health_renderer_tick_frame(h)
        XCTAssertEqual(gaia_health_renderer_get_frame_count(h), 2)
    }

    func testNullHandleSafety() {
        gaia_health_renderer_set_epistemic(nil, 0)          // must not crash
        let tag = gaia_health_renderer_get_epistemic(nil)
        XCTAssertEqual(tag, 2, "Null handle defaults to Assumed")
    }

    func testOutOfRangeEpistemicClamped() {
        guard let h = gaia_health_renderer_create() else {
            XCTFail("Renderer create returned nil")
            return
        }
        defer { gaia_health_renderer_destroy(h) }
        gaia_health_renderer_set_epistemic(h, 99)
        XCTAssertEqual(gaia_health_renderer_get_epistemic(h), 2, "Out-of-range clamped to Assumed")
    }

    // PQ: Metal GPU offscreen render
    func testMetalPQOffscreenRender() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            XCTFail("No Metal GPU detected — MacHealth PQ FAIL")
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
        rpd.colorAttachments[0].texture     = tex
        rpd.colorAttachments[0].loadAction  = .clear
        rpd.colorAttachments[0].clearColor  = MTLClearColor(red: 0.0, green: 0.4, blue: 0.9, alpha: 1.0)
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
        XCTAssertGreaterThan(nonZero, 0, "MacHealth Metal PQ: rendered frame is all-zero")

        // Write PQ receipt
        let receipt: [String: Any] = [
            "spec":              "GAIA-HEALTH-PQ-MAC-001",
            "phase":             "PQ",
            "cell":              "MacHealth",
            "metal_device_name": device.name,
            "nonzero_pixels":    nonZero,
            "pq_status":         nonZero > 0 ? "PASS" : "FAIL",
            "timestamp":         ISO8601DateFormatter().string(from: Date()),
            "pii_stored":        false,
        ]
        let pqDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // MacHealth/ root
            .appendingPathComponent("evidence/pq")
        try? FileManager.default.createDirectory(at: pqDir, withIntermediateDirectories: true)
        let pqFile = pqDir.appendingPathComponent("machealth_pq_receipt.json")
        try? JSONSerialization.data(withJSONObject: receipt, options: .prettyPrinted)
                             .write(to: pqFile)
        print("MacHealth PQ receipt: \(pqFile.path)")
    }
}
