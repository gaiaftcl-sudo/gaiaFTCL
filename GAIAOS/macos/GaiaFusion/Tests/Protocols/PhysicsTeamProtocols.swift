import XCTest
@testable import GaiaFusion

/// GFTCL-PQ-002: Physics Team Test Protocols (PQ-PHY-001 through PQ-PHY-008)
/// GAMP 5 Performance Qualification - Physics Invariants
final class PhysicsTeamProtocols: XCTestCase {
    
    var gameState: OpenUSDLanguageGameState!
    var playbackController: MetalPlaybackController!
    
    override func setUp() async throws {
        try await super.setUp()
        gameState = OpenUSDLanguageGameState()
        playbackController = MetalPlaybackController()
        
        await playbackController.initialize(layer: nil)
    }
    
    override func tearDown() async throws {
        playbackController?.cleanup()
        try await super.tearDown()
    }
    
    // MARK: - PQ-PHY-001: Tokamak Plasma Current Range
    
    /// Test Protocol ID: PQ-PHY-001
    /// Invariant: INV-PHY-001 — Tokamak I_p must be 1–25 MA
    /// Acceptance: All telemetry within bounds for 60 seconds
    func testPQPHY001_TokamakPlasmaCurrent() async throws {
        let plantKind = FusionPlantKind.tokamak
        gameState.requestPlantSwap(to: plantKind)
        
        try await Task.sleep(for: .seconds(2))
        XCTAssertEqual(gameState.currentActivePlant, plantKind, "Plant swap failed")
        
        var measurements: [(timestamp: Date, current_MA: Double)] = []
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < 60 {
            if let telemetry = gameState.currentPlantTelemetry {
                if let currentMA = telemetry["I_p_MA"] as? Double {
                    measurements.append((Date(), currentMA))
                    
                    XCTAssertGreaterThanOrEqual(currentMA, 1.0,
                        "Plasma current below minimum (1 MA)")
                    XCTAssertLessThanOrEqual(currentMA, 25.0,
                        "Plasma current exceeds maximum (25 MA)")
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        
        XCTAssertGreaterThan(measurements.count, 500,
            "Insufficient telemetry samples (need >500 in 60s)")
        
        let avgCurrent = measurements.map(\.current_MA).reduce(0, +) / Double(measurements.count)
        print("PQ-PHY-001: Avg I_p = \(avgCurrent) MA over \(measurements.count) samples")
    }
    
    // MARK: - PQ-PHY-002: Stellarator Magnetic Field Range
    
    /// Test Protocol ID: PQ-PHY-002
    /// Invariant: INV-PHY-002 — Stellarator B_T must be 1–10 T
    /// Acceptance: All telemetry within bounds for 60 seconds
    func testPQPHY002_StellatorMagneticField() async throws {
        let plantKind = FusionPlantKind.stellarator
        gameState.requestPlantSwap(to: plantKind)
        
        try await Task.sleep(for: .seconds(2))
        XCTAssertEqual(gameState.currentActivePlant, plantKind, "Plant swap failed")
        
        var measurements: [(timestamp: Date, field_T: Double)] = []
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < 60 {
            if let telemetry = gameState.currentPlantTelemetry {
                if let fieldT = telemetry["B_T_tesla"] as? Double {
                    measurements.append((Date(), fieldT))
                    
                    XCTAssertGreaterThanOrEqual(fieldT, 1.0,
                        "Magnetic field below minimum (1 T)")
                    XCTAssertLessThanOrEqual(fieldT, 10.0,
                        "Magnetic field exceeds maximum (10 T)")
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        
        XCTAssertGreaterThan(measurements.count, 500,
            "Insufficient telemetry samples")
        
        let avgField = measurements.map(\.field_T).reduce(0, +) / Double(measurements.count)
        print("PQ-PHY-002: Avg B_T = \(avgField) T over \(measurements.count) samples")
    }
    
    // MARK: - PQ-PHY-003: ICF Laser Energy Range
    
    /// Test Protocol ID: PQ-PHY-003
    /// Invariant: INV-PHY-003 — ICF E_laser must be 0.1–5 MJ
    /// Acceptance: All telemetry within bounds for 60 seconds
    func testPQPHY003_ICFLaserEnergy() async throws {
        let plantKind = FusionPlantKind.icf
        gameState.requestPlantSwap(to: plantKind)
        
        try await Task.sleep(for: .seconds(2))
        XCTAssertEqual(gameState.currentActivePlant, plantKind, "Plant swap failed")
        
        var measurements: [(timestamp: Date, energy_MJ: Double)] = []
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < 60 {
            if let telemetry = gameState.currentPlantTelemetry {
                if let energyMJ = telemetry["E_laser_MJ"] as? Double {
                    measurements.append((Date(), energyMJ))
                    
                    XCTAssertGreaterThanOrEqual(energyMJ, 0.1,
                        "Laser energy below minimum (0.1 MJ)")
                    XCTAssertLessThanOrEqual(energyMJ, 5.0,
                        "Laser energy exceeds maximum (5 MJ)")
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        
        XCTAssertGreaterThan(measurements.count, 500,
            "Insufficient telemetry samples")
        
        let avgEnergy = measurements.map(\.energy_MJ).reduce(0, +) / Double(measurements.count)
        print("PQ-PHY-003: Avg E_laser = \(avgEnergy) MJ over \(measurements.count) samples")
    }
    
    // MARK: - PQ-PHY-004: FRC Electron Density Range
    
    /// Test Protocol ID: PQ-PHY-004
    /// Invariant: INV-PHY-004 — FRC n_e must be 1e18–1e21 m^-3
    /// Acceptance: All telemetry within bounds for 60 seconds
    func testPQPHY004_FRCElectronDensity() async throws {
        let plantKind = FusionPlantKind.frc
        gameState.requestPlantSwap(to: plantKind)
        
        try await Task.sleep(for: .seconds(2))
        XCTAssertEqual(gameState.currentActivePlant, plantKind, "Plant swap failed")
        
        var measurements: [(timestamp: Date, density_m3: Double)] = []
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < 60 {
            if let telemetry = gameState.currentPlantTelemetry {
                if let densityM3 = telemetry["n_e_m3"] as? Double {
                    measurements.append((Date(), densityM3))
                    
                    XCTAssertGreaterThanOrEqual(densityM3, 1e18,
                        "Electron density below minimum (1e18 m^-3)")
                    XCTAssertLessThanOrEqual(densityM3, 1e21,
                        "Electron density exceeds maximum (1e21 m^-3)")
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        
        XCTAssertGreaterThan(measurements.count, 500,
            "Insufficient telemetry samples")
        
        let avgDensity = measurements.map(\.density_m3).reduce(0, +) / Double(measurements.count)
        print("PQ-PHY-004: Avg n_e = \(avgDensity) m^-3 over \(measurements.count) samples")
    }
    
    // MARK: - PQ-PHY-005: Spheromak Helicity Range
    
    /// Test Protocol ID: PQ-PHY-005
    /// Invariant: INV-PHY-005 — Spheromak K_mag must be 10–200 Wb^2
    /// Acceptance: All telemetry within bounds for 60 seconds
    func testPQPHY005_SpheromagHelicity() async throws {
        let plantKind = FusionPlantKind.spheromak
        gameState.requestPlantSwap(to: plantKind)
        
        try await Task.sleep(for: .seconds(2))
        XCTAssertEqual(gameState.currentActivePlant, plantKind, "Plant swap failed")
        
        var measurements: [(timestamp: Date, helicity_Wb2: Double)] = []
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < 60 {
            if let telemetry = gameState.currentPlantTelemetry {
                if let helicityWb2 = telemetry["K_mag_Wb2"] as? Double {
                    measurements.append((Date(), helicityWb2))
                    
                    XCTAssertGreaterThanOrEqual(helicityWb2, 10.0,
                        "Magnetic helicity below minimum (10 Wb^2)")
                    XCTAssertLessThanOrEqual(helicityWb2, 200.0,
                        "Magnetic helicity exceeds maximum (200 Wb^2)")
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        
        XCTAssertGreaterThan(measurements.count, 500,
            "Insufficient telemetry samples")
        
        let avgHelicity = measurements.map(\.helicity_Wb2).reduce(0, +) / Double(measurements.count)
        print("PQ-PHY-005: Avg K_mag = \(avgHelicity) Wb^2 over \(measurements.count) samples")
    }
    
    // MARK: - PQ-PHY-006: Mirror Ratio Range
    
    /// Test Protocol ID: PQ-PHY-006
    /// Invariant: INV-PHY-006 — Mirror R_mirror must be 2–20
    /// Acceptance: All telemetry within bounds for 60 seconds
    func testPQPHY006_MirrorRatio() async throws {
        let plantKind = FusionPlantKind.magneticMirror
        gameState.requestPlantSwap(to: plantKind)
        
        try await Task.sleep(for: .seconds(2))
        XCTAssertEqual(gameState.currentActivePlant, plantKind, "Plant swap failed")
        
        var measurements: [(timestamp: Date, ratio: Double)] = []
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < 60 {
            if let telemetry = gameState.currentPlantTelemetry {
                if let ratio = telemetry["R_mirror"] as? Double {
                    measurements.append((Date(), ratio))
                    
                    XCTAssertGreaterThanOrEqual(ratio, 2.0,
                        "Mirror ratio below minimum (2)")
                    XCTAssertLessThanOrEqual(ratio, 20.0,
                        "Mirror ratio exceeds maximum (20)")
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        
        XCTAssertGreaterThan(measurements.count, 500,
            "Insufficient telemetry samples")
        
        let avgRatio = measurements.map(\.ratio).reduce(0, +) / Double(measurements.count)
        print("PQ-PHY-006: Avg R_mirror = \(avgRatio) over \(measurements.count) samples")
    }
    
    // MARK: - PQ-PHY-007: Z-Pinch Current Range
    
    /// Test Protocol ID: PQ-PHY-007
    /// Invariant: INV-PHY-007 — Z-pinch I_pinch must be 1–50 MA
    /// Acceptance: All telemetry within bounds for 60 seconds
    func testPQPHY007_ZPinchCurrent() async throws {
        let plantKind = FusionPlantKind.zpinch
        gameState.requestPlantSwap(to: plantKind)
        
        try await Task.sleep(for: .seconds(2))
        XCTAssertEqual(gameState.currentActivePlant, plantKind, "Plant swap failed")
        
        var measurements: [(timestamp: Date, current_MA: Double)] = []
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < 60 {
            if let telemetry = gameState.currentPlantTelemetry {
                if let currentMA = telemetry["I_pinch_MA"] as? Double {
                    measurements.append((Date(), currentMA))
                    
                    XCTAssertGreaterThanOrEqual(currentMA, 1.0,
                        "Pinch current below minimum (1 MA)")
                    XCTAssertLessThanOrEqual(currentMA, 50.0,
                        "Pinch current exceeds maximum (50 MA)")
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        
        XCTAssertGreaterThan(measurements.count, 500,
            "Insufficient telemetry samples")
        
        let avgCurrent = measurements.map(\.current_MA).reduce(0, +) / Double(measurements.count)
        print("PQ-PHY-007: Avg I_pinch = \(avgCurrent) MA over \(measurements.count) samples")
    }
    
    // MARK: - PQ-PHY-008: Theta-Pinch Field Range
    
    /// Test Protocol ID: PQ-PHY-008
    /// Invariant: INV-PHY-008 — Theta-pinch B_theta must be 1–15 T
    /// Acceptance: All telemetry within bounds for 60 seconds
    func testPQPHY008_ThetaPinchField() async throws {
        let plantKind = FusionPlantKind.thetaPinch
        gameState.requestPlantSwap(to: plantKind)
        
        try await Task.sleep(for: .seconds(2))
        XCTAssertEqual(gameState.currentActivePlant, plantKind, "Plant swap failed")
        
        var measurements: [(timestamp: Date, field_T: Double)] = []
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < 60 {
            if let telemetry = gameState.currentPlantTelemetry {
                if let fieldT = telemetry["B_theta_T"] as? Double {
                    measurements.append((Date(), fieldT))
                    
                    XCTAssertGreaterThanOrEqual(fieldT, 1.0,
                        "Theta field below minimum (1 T)")
                    XCTAssertLessThanOrEqual(fieldT, 15.0,
                        "Theta field exceeds maximum (15 T)")
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        
        XCTAssertGreaterThan(measurements.count, 500,
            "Insufficient telemetry samples")
        
        let avgField = measurements.map(\.field_T).reduce(0, +) / Double(measurements.count)
        print("PQ-PHY-008: Avg B_theta = \(avgField) T over \(measurements.count) samples")
    }
}
