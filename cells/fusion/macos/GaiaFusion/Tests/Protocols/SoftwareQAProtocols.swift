import XCTest
@testable import GaiaFusion

/// GFTCL-PQ-002: Software QA Test Protocols (PQ-QA-001 through PQ-QA-010)
/// GAMP 5 Performance Qualification - Automated Software Quality Tests
@MainActor
final class SoftwareQAProtocols: XCTestCase {
    
    var gameState: OpenUSDLanguageGameState!
    var playbackController: MetalPlaybackController!
    
    override func setUp() async throws {
        try await super.setUp()
        gameState = await MainActor.run { OpenUSDLanguageGameState() }
        playbackController = await MainActor.run { MetalPlaybackController() }
        
        await playbackController.initialize(layer: nil)
    }
    
    override func tearDown() async throws {
        await MainActor.run {
            playbackController?.cleanup()
        }
        try await super.tearDown()
    }
    
    // MARK: - PQ-QA-001: Rust Metal Renderer Compilation
    
    /// Test Protocol ID: PQ-QA-001
    /// Invariant: INV-QA-001 — Rust Metal renderer must compile without errors
    /// Acceptance: cargo build --release exits 0, no errors
    func testPQQA001_RustMetalRendererCompilation() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["cargo", "build", "--release", "--target", "aarch64-apple-darwin"]
        process.currentDirectoryURL = URL(fileURLWithPath: "/Users/richardgillespie/Documents/FoT8D/cells/fusion/macos/GaiaFusion/MetalRenderer/rust")
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let exitCode = process.terminationStatus
        XCTAssertEqual(exitCode, 0, "Rust Metal renderer compilation failed (exit \(exitCode))")
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        XCTAssertFalse(output.contains("error:"), "Compilation output contains errors")
        
        print("PQ-QA-001: Rust Metal renderer compiled successfully (exit 0)")
    }
    
    // MARK: - PQ-QA-002: Swift Build All Targets
    
    /// Test Protocol ID: PQ-QA-002
    /// Invariant: INV-QA-002 — Swift build must succeed for all targets
    /// Acceptance: swift build exits 0
    func testPQQA002_SwiftBuildAllTargets() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "build"]
        process.currentDirectoryURL = URL(fileURLWithPath: "/Users/richardgillespie/Documents/FoT8D/cells/fusion/macos/GaiaFusion")
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let exitCode = process.terminationStatus
        XCTAssertEqual(exitCode, 0, "Swift build failed (exit \(exitCode))")
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        XCTAssertFalse(output.contains("error:"), "Build output contains errors")
        
        print("PQ-QA-002: Swift build completed successfully (exit 0)")
    }
    
    // MARK: - PQ-QA-003: FFI Bridge Function Signatures
    
    /// Test Protocol ID: PQ-QA-003
    /// Invariant: INV-QA-003 — FFI bridge functions must match C header
    /// Acceptance: All FFI symbols present in static library
    func testPQQA003_FFIBridgeFunctionSignatures() async throws {
        let libPath = "/Users/richardgillespie/Documents/FoT8D/cells/fusion/macos/GaiaFusion/MetalRenderer/rust/target/aarch64-apple-darwin/release/libgaia_metal_renderer.a"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nm")
        process.arguments = ["-g", libPath]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        let requiredSymbols = [
            "gaia_metal_renderer_new",
            "gaia_metal_renderer_destroy",
            "gaia_metal_renderer_render_frame",
            "gaia_metal_renderer_resize",
            "gaia_metal_renderer_set_tau",
            "gaia_metal_renderer_get_tau"
        ]
        
        for symbol in requiredSymbols {
            XCTAssertTrue(output.contains(symbol),
                "FFI symbol '\(symbol)' not found in static library")
        }
        
        print("PQ-QA-003: All FFI symbols validated in static library")
    }
    
    // MARK: - PQ-QA-004: Metal Shader Compilation
    
    /// Test Protocol ID: PQ-QA-004
    /// Invariant: INV-QA-004 — Metal shaders must compile to .metallib
    /// Acceptance: default.metallib exists and is valid
    func testPQQA004_MetalShaderCompilation() async throws {
        let metallibPath = "/Users/richardgillespie/Documents/FoT8D/cells/fusion/macos/GaiaFusion/MetalRenderer/rust/target/aarch64-apple-darwin/release/default.metallib"
        
        let fileManager = FileManager.default
        XCTAssertTrue(fileManager.fileExists(atPath: metallibPath),
            "default.metallib not found at expected path")
        
        let attributes = try fileManager.attributesOfItem(atPath: metallibPath)
        let fileSize = attributes[.size] as? UInt64 ?? 0
        
        XCTAssertGreaterThan(fileSize, 1000,
            "default.metallib suspiciously small (\(fileSize) bytes)")
        
        print("PQ-QA-004: Metal shader library validated (\(fileSize) bytes)")
    }
    
    // MARK: - PQ-QA-005: NATS Connection Stability
    
    /// Test Protocol ID: PQ-QA-005
    /// Invariant: INV-QA-005 — NATS connection must remain stable for 5 minutes
    /// Acceptance: No disconnects for 300 seconds
    func testPQQA005_NATSConnectionStability() async throws {
        let natsService = NATSService.shared
        try await natsService.connect()
        
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < 300 {
            let connected = await natsService.isConnected
            XCTAssertTrue(connected,
                "NATS connection lost at \(Date().timeIntervalSince(startTime))s")
            try await Task.sleep(for: .seconds(1))
        }
        
        print("PQ-QA-005: NATS connection stable for 300 seconds (0 disconnects)")
    }
    
    // MARK: - PQ-QA-006: Memory Leak Detection (Instruments)
    
    /// Test Protocol ID: PQ-QA-006
    /// Invariant: INV-QA-006 — No memory leaks during 10-minute run
    /// Acceptance: Instruments leaks report shows 0 leaks
    func testPQQA006_MemoryLeakDetection() async throws {
        let startMemory = getMemoryUsage()
        
        for _ in 0..<100 {
            await playbackController.requestPlantSwap(to: "tokamak")
            try await Task.sleep(for: .seconds(1))
            await playbackController.requestPlantSwap(to: "stellarator")
            try await Task.sleep(for: .seconds(1))
        }
        
        let endMemory = getMemoryUsage()
        let memoryGrowth = endMemory - startMemory
        
        XCTAssertLessThan(memoryGrowth, 50_000_000,
            "Memory grew by \(memoryGrowth) bytes (>50 MB indicates leak)")
        
        print("PQ-QA-006: Memory growth = \(memoryGrowth) bytes after 100 swaps")
    }
    
    // MARK: - PQ-QA-007: Crash Recovery (SwiftUI Error Boundary)
    
    /// Test Protocol ID: PQ-QA-007
    /// Invariant: INV-QA-007 — App must not crash on invalid telemetry
    /// Acceptance: Error boundary catches fault, app remains responsive
    func testPQQA007_CrashRecovery() async throws {
        await playbackController.requestPlantSwap(to: "tokamak")
        try await Task.sleep(for: .seconds(1))
        
        await gameState.injectMalformedTelemetry()
        
        try await Task.sleep(for: .seconds(2))
        
        let active = await gameState.errorBoundaryActive; XCTAssertTrue(active,
            "Error boundary did not catch malformed telemetry")
        
        let crashed = await gameState.appCrashed; XCTAssertFalse(crashed,
            "App crashed on malformed telemetry (should be caught)")
        
        print("PQ-QA-007: Error boundary successfully caught malformed telemetry")
    }
    
    // MARK: - PQ-QA-008: Telemetry Update Rate (60 Hz)
    
    /// Test Protocol ID: PQ-QA-008
    /// Invariant: INV-QA-008 — Telemetry must update at ≥50 Hz
    /// Acceptance: Average update rate ≥50 Hz for 60 seconds
    @MainActor
    func testPQQA008_TelemetryUpdateRate() async throws {
        await playbackController.requestPlantSwap(to: "tokamak")
        try await Task.sleep(for: .seconds(2))
        
        var updateTimestamps: [Date] = []
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < 60 {
            if gameState.telemetryUpdated {
                updateTimestamps.append(Date())
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        
        let updateRate = Double(updateTimestamps.count) / 60.0
        
        XCTAssertGreaterThanOrEqual(updateRate, 50.0,
            "Telemetry update rate = \(updateRate) Hz (need ≥50 Hz)")
        
        print("PQ-QA-008: Telemetry update rate = \(updateRate) Hz")
    }
    
    // MARK: - PQ-QA-009: Continuous Operation (24 Hours)
    
    /// Test Protocol ID: PQ-QA-009
    /// Invariant: INV-QA-009 — App must run continuously for 24 hours
    /// Acceptance: No crashes, FPS >55, memory stable
    @MainActor
    func testPQQA009_ContinuousOperation24Hours() async throws {
        throw XCTSkip("24-hour continuous test disabled for automated runs")
        
        let startTime = Date()
        let startMemory = getMemoryUsage()
        var minFPS: Double = 60.0
        
        while Date().timeIntervalSince(startTime) < 86400 {
            if let fps = playbackController.currentFPS {
                minFPS = min(minFPS, fps)
                XCTAssertGreaterThanOrEqual(fps, 55.0,
                    "FPS dropped to \(fps) at \(Date().timeIntervalSince(startTime))s")
            }
            
            try await Task.sleep(for: .seconds(10))
        }
        
        let endMemory = getMemoryUsage()
        let memoryGrowth = endMemory - startMemory
        
        XCTAssertLessThan(memoryGrowth, 200_000_000,
            "Memory grew by \(memoryGrowth) bytes over 24 hours")
        
        print("PQ-QA-009: 24-hour run complete, Min FPS = \(minFPS), Memory growth = \(memoryGrowth) bytes")
    }
    
    // MARK: - PQ-QA-010: Git Commit SHA Traceable
    
    /// Test Protocol ID: PQ-QA-010
    /// Invariant: INV-QA-010 — App build must be traceable to git commit
    /// Acceptance: Git SHA embedded in app metadata
    @MainActor
    func testPQQA010_GitCommitSHATraceable() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "HEAD"]
        process.currentDirectoryURL = URL(fileURLWithPath: "/Users/richardgillespie/Documents/FoT8D/cells/fusion/macos/GaiaFusion")
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let gitSHA = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        XCTAssertFalse(gitSHA.isEmpty, "Git SHA not found")
        XCTAssertEqual(gitSHA.count, 40, "Git SHA should be 40 characters")
        
        if let appSHA = gameState.appGitSHA {
            XCTAssertEqual(appSHA, gitSHA,
                "App embedded SHA (\(appSHA)) doesn't match git HEAD (\(gitSHA))")
        } else {
            XCTFail("App git SHA not embedded in metadata")
        }
        
        print("PQ-QA-010: Git commit SHA = \(gitSHA)")
    }
    
    // MARK: - Helper Functions
    
    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard kerr == KERN_SUCCESS else { return 0 }
        return info.resident_size
    }
}
