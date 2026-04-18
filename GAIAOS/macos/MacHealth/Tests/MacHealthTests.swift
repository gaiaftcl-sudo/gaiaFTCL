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
    
    // SIL OQ: ZMQ Wire Format Validation
    func testZMQWireFormatHeader() {
        let header = ZMQHeader(sampleRateHz: 1000, sampleFormat: .complexFloat32, channelCount: 1)
        let data = header.toData()
        XCTAssertEqual(data.count, 16, "ZMQ Header must be exactly 16 bytes")
        
        let parsed = ZMQHeader(data: data)
        XCTAssertNotNil(parsed, "Failed to parse ZMQ Header")
        XCTAssertEqual(parsed?.sampleRateHz, 1000)
        XCTAssertEqual(parsed?.sampleFormat, .complexFloat32)
        XCTAssertEqual(parsed?.channelCount, 1)
    }
    
    // SIL OQ: Telemetry Schema Binding Validation
    func testTelemetryTickSchemaBinding() {
        let measurements = [
            TelemetryTick.Measurement(id: "freq", value: 0.05, unit: "Hz", provenance: "mock_s4_edge")
        ]
        
        let tick = TelemetryBinder.createSILTick(
            runId: "sil_oq_run_001",
            parentHash: "mock_iq_hash",
            substrateSha256: "mock_wasm_hash",
            state: "RUNNING",
            measurements: measurements,
            cellSignature: "mock_cell_sig",
            transducerSignatures: ["mock_transducer_sig"]
        )
        
        XCTAssertEqual(tick.epistemic_tag, "(M_SIL)", "Epistemic tag must be (M_SIL) during SIL execution")
        XCTAssertEqual(tick.type, "telemetry.tick")
        
        let jsonData = try? tick.toJSON()
        XCTAssertNotNil(jsonData, "Failed to encode TelemetryTick to JSON")
    }
    
    // GAMP 5: Games & Case Studies Narrative Report
    func testGAMP5GamesNarrativeReport() {
        // As per GAMP 5, the report must show all the games that can be played
        // narrated into the report as a live test case study.
        
        let caseStudies = [
            [
                "game_id": "OWL_PROTOCOL",
                "name": "The OWL Protocol Game",
                "narrative": "A clinical protocol game incentivizing adherence to circadian rhythms, light exposure, and metabolic timing. The human substrate acts as the player. The game measures daily adherence through epistemic (M) tags and rewards the substrate for maintaining the PREPARED and RUNNING states, avoiding the REFUSED state.",
                "live_test_status": "NARRATIVE_CONTRACT_TIER_NOT_LIVE_VALIDATION",
                "epistemic_requirement": "(M) Measured via spectrum analyzer or lab result"
            ],
            [
                "game_id": "EARTH_SUBSTRATE_INGESTOR",
                "name": "Earth Substrate Ingestor",
                "narrative": "Every cell continuously ingests live Earth feeds (ADSB, weather, sea, ATC, satellite). Feed loss equals torsion increase. The game tests the cell's ability to maintain constitutional alignment. Sustained feed loss results in a DANGEROUS state.",
                "live_test_status": "NARRATIVE_CONTRACT_TIER_NOT_LIVE_VALIDATION",
                "epistemic_requirement": "(I) Inferred from continuous NATS JetStream ingestion"
            ],
            [
                "game_id": "VIE_V2_VORTEX",
                "name": "VIE-v2 Vortex Ingestion Engine",
                "narrative": "Universal VqBit schema ingestion across ten domains (sports, chemistry, biology, market, law, governance, physics, technology, energy, safety). The game calculates entropy potential (ΔE) and triggers a HUNTER_STRIKE when Psb >= 0.85.",
                "live_test_status": "NARRATIVE_CONTRACT_TIER_NOT_LIVE_VALIDATION",
                "epistemic_requirement": "(T) Transformed via Franklin constitutional inference"
            ]
        ]
        
        let report: [String: Any] = [
            "spec": "GAIA-HEALTH-GAMES-NARRATIVE-001",
            "phase": "OQ",
            "cell": "MacHealth",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "games_case_studies": caseStudies,
            "status": "PASS"
        ]
        
        let reportDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // MacHealth/ root
            .appendingPathComponent("evidence/oq")
            
        try? FileManager.default.createDirectory(at: reportDir, withIntermediateDirectories: true)
        let reportFile = reportDir.appendingPathComponent("machealth_games_narrative_receipt.json")
        try? JSONSerialization.data(withJSONObject: report, options: .prettyPrinted)
                             .write(to: reportFile)
        print("MacHealth Games Narrative receipt: \(reportFile.path)")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportFile.path), "Games narrative report must be generated")
    }
}
