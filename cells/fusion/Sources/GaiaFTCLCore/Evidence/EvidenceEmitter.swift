import Foundation

public struct EvidenceReceipt: Codable {
    public var receiptVersion: String = "1.0"
    public var ursId: String = "GFTCL-URS-001"
    public var fsId: String = "GFTCL-ARCH-001"
    public var dsId: String = "GFTCL-DS-001"
    public var receiptSha: String
    public var terminalState: String
    public var timestamp: String
    public var cellId: String
    public var operatorWalletHash: String
    public var trainingMode: Bool
    public var command: String
    public var gateResults: GateResults
    public var evidencePaths: [String]
    
    public init(receiptVersion: String = "1.0", ursId: String = "GFTCL-URS-001", fsId: String = "GFTCL-ARCH-001", dsId: String = "GFTCL-DS-001", receiptSha: String, terminalState: String, timestamp: String, cellId: String, operatorWalletHash: String, trainingMode: Bool, command: String, gateResults: GateResults, evidencePaths: [String]) {
        self.receiptVersion = receiptVersion
        self.ursId = ursId
        self.fsId = fsId
        self.dsId = dsId
        self.receiptSha = receiptSha
        self.terminalState = terminalState
        self.timestamp = timestamp
        self.cellId = cellId
        self.operatorWalletHash = operatorWalletHash
        self.trainingMode = trainingMode
        self.command = command
        self.gateResults = gateResults
        self.evidencePaths = evidencePaths
    }
    
    enum CodingKeys: String, CodingKey {
        case receiptVersion = "receipt_version"
        case ursId = "urs_id"
        case fsId = "fs_id"
        case dsId = "ds_id"
        case receiptSha = "receipt_sha"
        case terminalState = "terminal_state"
        case timestamp
        case cellId = "cell_id"
        case operatorWalletHash = "operator_wallet_hash"
        case trainingMode = "training_mode"
        case command
        case gateResults = "gate_results"
        case evidencePaths = "evidence_paths"
    }
}

public struct GateResults: Codable {
    public var total: Int
    public var passed: Int
    public var failed: Int
    public var gateIds: [String]
    
    public init(total: Int, passed: Int, failed: Int, gateIds: [String]) {
        self.total = total
        self.passed = passed
        self.failed = failed
        self.gateIds = gateIds
    }
    
    enum CodingKeys: String, CodingKey {
        case total, passed, failed
        case gateIds = "gate_ids"
    }
}

public struct EvidenceEmitter {
    public static func emit(receipt: EvidenceReceipt, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let data = try JSONEncoder().encode(receipt)
        try data.write(to: url)
    }
}
