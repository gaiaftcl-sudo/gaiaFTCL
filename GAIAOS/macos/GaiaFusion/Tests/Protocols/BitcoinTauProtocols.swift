import XCTest
@testable import GaiaFusion

/// GFTCL-PQ-002: Bitcoin τ (Tau) Synchronization Protocols (PQ-TAU-001 through PQ-TAU-003)
/// GAMP 5 Performance Qualification - Sovereign Mesh Temporal Synchronization
/// CRITICAL: Mac cell and 9 mesh cells must share Bitcoin emergent time (τ = block height)
final class BitcoinTauProtocols: XCTestCase {
    
    var gameState: OpenUSDLanguageGameState!
    var playbackController: MetalPlaybackController!
    var natsService: NATSService!
    
    override func setUp() async throws {
        try await super.setUp()
        gameState = await MainActor.run { OpenUSDLanguageGameState() }
        playbackController = await MainActor.run { MetalPlaybackController() }
        natsService = NATSService.shared
        
        await playbackController.initialize(layer: nil)
        try await natsService.connect()
    }
    
    override func tearDown() async throws {
        // cleanup() not defined — disengage and nil out
        await playbackController?.disengage()
        playbackController = nil
        try await super.tearDown()
    }
    
    // MARK: - PQ-TAU-001: All 10 Cells Within ±2 Block Tolerance
    
    /// Test Protocol ID: PQ-TAU-001
    /// Invariant: INV-TAU-001 — Mac cell τ and all 9 mesh cells τ must be within ±2 blocks
    /// Acceptance: Δτ ≤ 2 blocks across all 10 cells (9 mesh + 1 Mac)
    /// Evidence: tau_synchronization_log.json
    func testPQTAU001_AllCellsWithinTolerance() async throws {
        let meshCells = [
            "77.42.85.60", "135.181.88.134", "77.42.32.156",
            "77.42.88.110", "37.27.7.9", "37.120.187.247",
            "152.53.91.220", "152.53.88.141", "37.120.187.174"
        ]
        
        var cellTauValues: [String: UInt64] = [:]
        
        for cellIP in meshCells {
            guard let tau = try await getMeshCellTau(ip: cellIP) else {
                XCTFail("Failed to get τ from mesh cell \(cellIP)")
                continue
            }
            cellTauValues[cellIP] = tau
        }
        
        let macTau = await playbackController.getTau()
        cellTauValues["Mac"] = macTau
        
        XCTAssertEqual(cellTauValues.count, 10,
            "Not all 10 cells reported τ (got \(cellTauValues.count)/10)")
        
        let tauValues = Array(cellTauValues.values)
        let minTau = tauValues.min() ?? 0
        let maxTau = tauValues.max() ?? 0
        let deltaTau = maxTau - minTau
        
        XCTAssertLessThanOrEqual(deltaTau, 2,
            "Δτ = \(deltaTau) blocks exceeds tolerance (±2 blocks)")
        
        let evidence = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "mac_tau": macTau,
            "mesh_tau_values": cellTauValues.filter { $0.key != "Mac" },
            "min_tau": minTau,
            "max_tau": maxTau,
            "delta_tau": deltaTau,
            "tolerance_met": deltaTau <= 2
        ] as [String: Any]
        
        try saveEvidence(filename: "tau_synchronization_log.json", data: evidence)
        
        print("PQ-TAU-001: Δτ = \(deltaTau) blocks (tolerance: ±2)")
        print("  Mac: \(macTau)")
        for (cell, tau) in cellTauValues.filter({ $0.key != "Mac" }).sorted(by: { $0.key < $1.key }) {
            print("  \(cell): \(tau)")
        }
    }
    
    // MARK: - PQ-TAU-002: Mac Cell τ Updates Every 30 Seconds
    
    /// Test Protocol ID: PQ-TAU-002
    /// Invariant: INV-TAU-002 — Mac renderer τ must update within 60s of new Bitcoin block
    /// Acceptance: τ update latency < 60s for 5 consecutive blocks
    /// Evidence: mac_tau_update_latency.csv
    func testPQTAU002_MacCellTauUpdatesEvery30Seconds() async throws {
        var updateLatencies: [(blockHeight: UInt64, latency: TimeInterval)] = []
        var lastTau: UInt64 = await playbackController.getTau()
        var lastUpdateTime = Date()
        
        let testDuration: TimeInterval = 600
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < testDuration {
            let currentTau = await playbackController.getTau()
            
            if currentTau > lastTau {
                let latency = Date().timeIntervalSince(lastUpdateTime)
                updateLatencies.append((currentTau, latency))
                
                XCTAssertLessThan(latency, 60.0,
                    "τ update latency = \(latency)s for block \(currentTau) (>60s limit)")
                
                lastTau = currentTau
                lastUpdateTime = Date()
            }
            
            try await Task.sleep(for: .seconds(1))
        }
        
        XCTAssertGreaterThanOrEqual(updateLatencies.count, 5,
            "Only \(updateLatencies.count) block updates (need ≥5)")
        
        let avgLatency = updateLatencies.map(\.latency).reduce(0, +) / Double(updateLatencies.count)
        let maxLatency = updateLatencies.map(\.latency).max() ?? 0
        
        var csvContent = "block_height,latency_seconds\n"
        for (blockHeight, latency) in updateLatencies {
            csvContent += "\(blockHeight),\(latency)\n"
        }
        
        try saveEvidenceText(filename: "mac_tau_update_latency.csv", content: csvContent)
        
        print("PQ-TAU-002: \(updateLatencies.count) block updates")
        print("  Avg latency: \(avgLatency)s")
        print("  Max latency: \(maxLatency)s")
    }
    
    // MARK: - PQ-TAU-003: Renderer Uses τ Not Local Frame Counter
    
    /// Test Protocol ID: PQ-TAU-003
    /// Invariant: INV-TAU-003 — Renderer frame timing driven by Bitcoin block height, not system_clock
    /// Acceptance: Renderer τ matches NATS within ±1 block, timeline advances on new blocks
    /// Evidence: renderer_tau_correlation.json
    func testPQTAU003_RendererUsesTauNotFrameCounter() async throws {
        await gameState.setPlantPayload("tokamak")
        try await Task.sleep(for: .seconds(2))
        
        var correlationSamples: [(timestamp: Date, nats_tau: UInt64, renderer_tau: UInt64)] = []
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < 120 {
            // NATSService is an actor — must await isolated property access
            if let natsTau = await natsService.lastBitcoinTau {
                let rendererTau = await playbackController.getTau()
                correlationSamples.append((Date(), natsTau, rendererTau))
                let deltaTau = abs(Int64(natsTau) - Int64(rendererTau))
                XCTAssertLessThanOrEqual(deltaTau, 1,
                    "Renderer τ (\(rendererTau)) diverged from NATS τ (\(natsTau)) by \(deltaTau) blocks")
            }
            
            try await Task.sleep(for: .seconds(2))
        }
        
        XCTAssertGreaterThan(correlationSamples.count, 50,
            "Insufficient correlation samples (\(correlationSamples.count))")
        
        let tauChanges = correlationSamples.indices.dropFirst().filter {
            correlationSamples[$0].nats_tau != correlationSamples[$0-1].nats_tau
        }
        
        XCTAssertGreaterThan(tauChanges.count, 0,
            "No τ changes observed (timeline not advancing)")
        
        for changeIdx in tauChanges {
            let prevSample = correlationSamples[changeIdx - 1]
            let currentSample = correlationSamples[changeIdx]
            
            let latency = currentSample.timestamp.timeIntervalSince(prevSample.timestamp)
            
            print("  Block \(prevSample.nats_tau) → \(currentSample.nats_tau): \(latency)s")
        }
        
        let evidence = correlationSamples.map { sample in
            [
                "timestamp": ISO8601DateFormatter().string(from: sample.timestamp),
                "nats_tau": sample.nats_tau,
                "renderer_tau": sample.renderer_tau,
                "delta": abs(Int64(sample.nats_tau) - Int64(sample.renderer_tau))
            ] as [String: Any]
        }
        
        try saveEvidence(filename: "renderer_tau_correlation.json", data: ["samples": evidence])
        
        let avgDelta = correlationSamples.map { abs(Int64($0.nats_tau) - Int64($0.renderer_tau)) }
            .reduce(0, +) / Int64(correlationSamples.count)
        
        print("PQ-TAU-003: \(correlationSamples.count) correlation samples")
        print("  Avg Δτ: \(avgDelta) blocks")
        print("  Timeline changes: \(tauChanges.count)")
    }
    
    // MARK: - Helper Functions
    
    private func getMeshCellTau(ip: String) async throws -> UInt64? {
        let url = URL(string: "http://\(ip):8850/heartbeat")!
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["block_height"] as? UInt64
    }
    
    private func saveEvidence(filename: String, data: [String: Any]) throws {
        let evidenceDir = URL(fileURLWithPath: "/Users/richardgillespie/Documents/FoT8D/GAIAOS/macos/GaiaFusion/evidence/pq_validation/tau")
        try FileManager.default.createDirectory(at: evidenceDir, withIntermediateDirectories: true)
        
        let fileURL = evidenceDir.appendingPathComponent(filename)
        let jsonData = try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
        try jsonData.write(to: fileURL)
        
        print("Evidence saved: \(fileURL.path)")
    }
    
    private func saveEvidenceText(filename: String, content: String) throws {
        let evidenceDir = URL(fileURLWithPath: "/Users/richardgillespie/Documents/FoT8D/GAIAOS/macos/GaiaFusion/evidence/pq_validation/tau")
        try FileManager.default.createDirectory(at: evidenceDir, withIntermediateDirectories: true)
        
        let fileURL = evidenceDir.appendingPathComponent(filename)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        
        print("Evidence saved: \(fileURL.path)")
    }
}
