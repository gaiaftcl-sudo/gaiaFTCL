import XCTest
@testable import GaiaFTCLCore

final class SubstrateEngineTests: XCTestCase {

    func testConstitutionalPassNominal() {
        let e = SubstrateEngine()
        XCTAssertEqual(e.constitutionalViolationCode(i_p: 1.0e6, b_t: 5.0, n_e: 1.0e20), 0)
    }

    func testC001HighCurrent() {
        let e = SubstrateEngine()
        XCTAssertEqual(e.constitutionalViolationCode(i_p: 25.0e6, b_t: 5.0, n_e: 1.0e20), 1)
    }

    func testC004NaN() {
        let e = SubstrateEngine()
        XCTAssertEqual(e.constitutionalViolationCode(i_p: .nan, b_t: 5.0, n_e: 1e20), 4)
    }

    func testC005Negative() {
        let e = SubstrateEngine()
        XCTAssertEqual(e.constitutionalViolationCode(i_p: -1, b_t: 5.0, n_e: 1e20), 5)
    }

    func testLegacyFusionSnapshotNominal() {
        let e = SubstrateEngine()
        let s = e.checkConstitutional(i_p: 1e6, b_t: 5, n_e: 1e20, plantKind: 0)
        XCTAssertEqual(s.violationCode, 0)
        XCTAssertEqual(s.terminalState, 0)
        XCTAssertGreaterThan(s.closureResidual, 0)
    }

    func testVMConstitutionalGeometryDegradedMapsC4FromTensor() {
        let e = SubstrateEngine()
        let inputs = ConstitutionalInputs(
            s1_structural: 0.05,
            s2_temporal: 0.05,
            s3_spatial: 0.05,
            s4_observable: 0.05,
            plasmaPressure: 0.05,
            fieldStrength: 0.05,
            minPlasmaPressure: 0.3,
            minFieldStrength: 0.3,
            plantKind: 0
        )
        let o = e.checkConstitutional(inputs)
        XCTAssertEqual(o.c1_trust, 0.05, accuracy: 0.001)
        XCTAssertEqual(o.c3_closure, 0.05, accuracy: 0.001)
        XCTAssertEqual(o.c4_consequence, 0.05, accuracy: 0.001)
        XCTAssertEqual(o.terminalState, .blocked)
        XCTAssertGreaterThanOrEqual(o.violationCode, 4)
    }
}
