import XCTest
@testable import GaiaFTCLCore

final class InvariantTests: XCTestCase {
    func testSchemaValidation() throws {
        let record = InvariantRecord(
            invariantId: "TEST-INV-001",
            title: "Test Invariant",
            domain: "test",
            owlClassification: "hardware",
            epistemicTag: "M",
            status: "DRAFT",
            description: "Test description"
        )
        XCTAssertEqual(record.status, "DRAFT")
    }
    
    func testSignatureRoundtrip() throws {
        var record = InvariantRecord(
            invariantId: "TEST-INV-002",
            title: "Test Invariant 2",
            domain: "test",
            owlClassification: "hardware",
            epistemicTag: "M",
            status: "DRAFT",
            description: "Test description"
        )
        
        try InvariantSigner.sign(&record, walletHash: "sha256:test", cellId: "local")
        XCTAssertTrue(InvariantSigner.verify(record))
    }
}
