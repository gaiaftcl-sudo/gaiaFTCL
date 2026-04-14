import Foundation

public enum PlantType: String, Codable, CaseIterable, Sendable {
    case tokamak = "tokamak"
    case stellarator = "stellarator"
    case frc = "frc"
    case spheromak = "spheromak"
    case mirror = "mirror"
    case inertial = "inertial"
    /// Compact HTS / low aspect ratio (cored sphere + central solenoid).
    case sphericalTokamak = "spherical_tokamak"
    case zPinch = "z_pinch"
    /// Magneto-inertial / plasma-jet merger (alias `pjmif` in catalog).
    case mif = "mif"
    case unknown = "unknown"
}

/// PQ test protocol alias
public typealias FusionPlantKind = PlantType

public extension PlantType {
    /// Test protocol aliases for canonical naming
    static var magneticMirror: PlantType { .mirror }
    static var zpinch: PlantType { .zPinch }
    static var icf: PlantType { .inertial }
    static var thetaPinch: PlantType { .mif }
    
    static func normalized(raw: String?) -> PlantType {
        PlantKindsCatalog.shared.canonical(raw)
    }

    var label: String {
        rawValue.capitalized
    }
}

public struct CellState: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var ipv4: String
    public var role: String
    public var health: Double
    public var status: String
    public var inputPlantType: PlantType
    public var outputPlantType: PlantType
    public var active: Bool

    public init(
        id: String,
        name: String,
        ipv4: String,
        role: String,
        health: Double,
        status: String,
        inputPlantType: PlantType = .unknown,
        outputPlantType: PlantType = .unknown,
        active: Bool
    ) {
        self.id = id
        self.name = name
        self.ipv4 = ipv4
        self.role = role
        self.health = health
        self.status = status
        self.inputPlantType = inputPlantType
        self.outputPlantType = outputPlantType
        self.active = active
    }

    public var healthPercent: Double {
        max(0.0, min(100.0, health * 100.0))
    }
}

public extension CellState {
    static let fallback = CellState(
        id: "unknown",
        name: "unknown",
        ipv4: "127.0.0.1",
        role: "offline",
        health: 0.0,
        status: "offline",
        inputPlantType: .unknown,
        outputPlantType: .unknown,
        active: false
    )
}
