import XCTest
@testable import GaiaFusion

/// PQ-QA-009: Continuous Operation Tests
/// Validates all 9 plants can run non-stop without crashes or degradation
@MainActor
final class PlantContinuousOperationTests: XCTestCase {
    
    var playbackController: MetalPlaybackController!
    var openUSDState: OpenUSDLanguageGameState!
    
    override func setUp() async throws {
        playbackController = MetalPlaybackController()
        openUSDState = OpenUSDLanguageGameState()
    }
    
    override func tearDown() async throws {
        playbackController = nil
        openUSDState = nil
    }
    
    // MARK: - Continuous Operation Tests
    
    /// Test: Tokamak runs for 5 minutes without crash
    func testTokamakContinuousOperation() async throws {
        let plant = "tokamak"
        try await runContinuousOperationTest(plant: plant, durationSeconds: 300)
    }
    
    /// Test: Stellarator runs for 5 minutes without crash
    func testStellaratorContinuousOperation() async throws {
        let plant = "stellarator"
        try await runContinuousOperationTest(plant: plant, durationSeconds: 300)
    }
    
    /// Test: FRC runs for 5 minutes without crash
    func testFRCContinuousOperation() async throws {
        let plant = "frc"
        try await runContinuousOperationTest(plant: plant, durationSeconds: 300)
    }
    
    /// Test: Spheromak runs for 5 minutes without crash
    func testSpheromakContinuousOperation() async throws {
        let plant = "spheromak"
        try await runContinuousOperationTest(plant: plant, durationSeconds: 300)
    }
    
    /// Test: Reversed-Field Pinch runs for 5 minutes without crash
    func testReversedFieldPinchContinuousOperation() async throws {
        let plant = "reversed_field_pinch"
        try await runContinuousOperationTest(plant: plant, durationSeconds: 300)
    }
    
    /// Test: Magnetic Mirror runs for 5 minutes without crash
    func testMagneticMirrorContinuousOperation() async throws {
        let plant = "magnetic_mirror"
        try await runContinuousOperationTest(plant: plant, durationSeconds: 300)
    }
    
    /// Test: Tandem Mirror runs for 5 minutes without crash
    func testTandemMirrorContinuousOperation() async throws {
        let plant = "tandem_mirror"
        try await runContinuousOperationTest(plant: plant, durationSeconds: 300)
    }
    
    /// Test: Spherical Tokamak runs for 5 minutes without crash
    func testSphericalTokamakContinuousOperation() async throws {
        let plant = "spherical_tokamak"
        try await runContinuousOperationTest(plant: plant, durationSeconds: 300)
    }
    
    /// Test: Field-Reversed Configuration (alias) runs for 5 minutes without crash
    func testFieldReversedConfigurationContinuousOperation() async throws {
        let plant = "field_reversed_configuration"
        try await runContinuousOperationTest(plant: plant, durationSeconds: 300)
    }
    
    // MARK: - All Plants Sequential Run
    
    /// Test: All 9 plants run sequentially for 1 minute each (9 minutes total)
    func testAllPlantsSequentialContinuousOperation() async throws {
        let plants = [
            "tokamak",
            "stellarator",
            "frc",
            "spheromak",
            "reversed_field_pinch",
            "magnetic_mirror",
            "tandem_mirror",
            "spherical_tokamak",
            "field_reversed_configuration"
        ]
        
        for plant in plants {
            print("Testing continuous operation for \(plant)...")
            try await runContinuousOperationTest(plant: plant, durationSeconds: 60)
        }
        
        print("✅ All 9 plants completed continuous operation test")
    }
    
    // MARK: - 24-Hour Soak Test (Disabled by default)
    
    /// Test: 24-hour soak test with random plant swaps
    /// This test is disabled by default (requires manual execution)
    func DISABLED_test24HourSoakTest() async throws {
        let plants = PlantKindsCatalog.canonicalNames
        let testDurationSeconds: TimeInterval = 24 * 60 * 60 // 24 hours
        let swapIntervalSeconds: TimeInterval = 5 * 60 // 5 minutes
        
        let startTime = Date()
        var swapCount = 0
        
        while Date().timeIntervalSince(startTime) < testDurationSeconds {
            let randomPlant = plants.randomElement()!
            print("[\(Date())] Swap #\(swapCount + 1): Loading \(randomPlant)")
            
            playbackController.loadPlant(randomPlant)
            
            // Simulate telemetry updates every 10 seconds for swap interval
            let telemetryUpdateCount = Int(swapIntervalSeconds / 10)
            for _ in 0..<telemetryUpdateCount {
                let randomTelemetry = generateRandomTelemetry(for: randomPlant)
                openUSDState.setMeasuredTelemetry(randomTelemetry)
                
                try await Task.sleep(for: .seconds(10))
            }
            
            swapCount += 1
            
            // Check for degradation
            XCTAssertTrue(playbackController.stageLoaded, "Plant failed to load after \(swapCount) swaps")
            XCTAssertGreaterThan(playbackController.fps, 55.0, "FPS dropped below 55 after \(swapCount) swaps")
        }
        
        print("✅ 24-hour soak test completed: \(swapCount) swaps")
    }
    
    // MARK: - Helper Methods
    
    /// Run continuous operation test for a specific plant
    private func runContinuousOperationTest(plant: String, durationSeconds: TimeInterval) async throws {
        print("Starting continuous operation test for \(plant) (\(durationSeconds)s)")
        
        // Load plant
        playbackController.loadPlant(plant)
        XCTAssertTrue(playbackController.stageLoaded, "\(plant) failed to load")
        XCTAssertEqual(playbackController.plantKind, plant, "Plant kind mismatch")
        
        // Simulate telemetry updates every second
        let startTime = Date()
        var updateCount = 0
        var fpsSum: Double = 0.0
        
        while Date().timeIntervalSince(startTime) < durationSeconds {
            // Generate random telemetry within physics bounds
            let telemetry = generateRandomTelemetry(for: plant)
            openUSDState.setMeasuredTelemetry(telemetry)
            
            // Sample FPS
            fpsSum += playbackController.fps
            updateCount += 1
            
            // Verify plant still loaded
            XCTAssertTrue(playbackController.stageLoaded, "\(plant) crashed after \(updateCount) updates")
            XCTAssertEqual(playbackController.plantKind, plant, "\(plant) plant kind changed unexpectedly")
            
            // Wait 1 second
            try await Task.sleep(for: .seconds(1))
        }
        
        // Verify performance
        let avgFPS = fpsSum / Double(updateCount)
        XCTAssertGreaterThan(avgFPS, 55.0, "\(plant) average FPS (\(avgFPS)) below 55 FPS")
        
        print("✅ \(plant) continuous operation test passed (\(updateCount) updates, avg FPS: \(String(format: "%.1f", avgFPS)))")
    }
    
    /// Generate random telemetry within physics bounds for a specific plant
    private func generateRandomTelemetry(for plant: String) -> [String: Double] {
        switch plant {
        case "tokamak":
            return [
                "I_p": Double.random(in: 0.5...30.0),
                "B_T": Double.random(in: 1.0...13.0),
                "n_e": Double.random(in: 0.1...3.0)
            ]
        case "stellarator":
            return [
                "I_p": Double.random(in: 0.0...0.2),
                "B_T": Double.random(in: 1.5...5.0),
                "n_e": Double.random(in: 0.05...2.0)
            ]
        case "frc", "field_reversed_configuration":
            return [
                "I_p": Double.random(in: 0.1...2.0),
                "B_T": Double.random(in: 0.0...0.1),
                "n_e": Double.random(in: 0.5...10.0)
            ]
        case "spheromak":
            return [
                "I_p": Double.random(in: 0.05...1.0),
                "B_T": Double.random(in: 0.0...0.5),
                "n_e": Double.random(in: 0.1...5.0)
            ]
        case "reversed_field_pinch":
            return [
                "I_p": Double.random(in: 0.5...5.0),
                "B_T": Double.random(in: 0.1...1.5),
                "n_e": Double.random(in: 0.2...3.0)
            ]
        case "magnetic_mirror":
            return [
                "I_p": Double.random(in: 0.0...0.05),
                "B_T": Double.random(in: 1.0...10.0),
                "n_e": Double.random(in: 0.01...1.0)
            ]
        case "tandem_mirror":
            return [
                "I_p": Double.random(in: 0.0...0.1),
                "B_T": Double.random(in: 1.0...15.0),
                "n_e": Double.random(in: 0.05...2.0)
            ]
        case "spherical_tokamak":
            return [
                "I_p": Double.random(in: 0.5...10.0),
                "B_T": Double.random(in: 0.5...3.0),
                "n_e": Double.random(in: 0.2...8.0)
            ]
        default:
            // Default tokamak values
            return [
                "I_p": 15.0,
                "B_T": 5.5,
                "n_e": 1.0
            ]
        }
    }
}
