import Foundation

public struct PlantKindsCatalog: Sendable {
    public static let shared = PlantKindsCatalog()

    /// Canonical plant kinds from `spec/native_fusion/plant_adapters.json`.
    public static let canonicalKinds: Set<String> = [
        "tokamak", "stellarator", "frc", "spheromak", "mirror", "inertial",
        "spherical_tokamak", "z_pinch", "mif",
    ]
    
    /// Alias for test compatibility
    public static let canonicalNames: Set<String> = canonicalKinds

    /// Narrow alias map (logged on resolve). Exposed for `/api/fusion/plant-kinds` and WASM clients.
    public static let kindAliases: [String: String] = [
        "virtual": "tokamak",
        "real": "tokamak",
        "icf": "inertial",
        "pjmif": "mif",
    ]

    private let fallbackKinds: [String] = [
        "tokamak", "stellarator", "frc", "spheromak", "mirror", "inertial",
        "spherical_tokamak", "z_pinch", "mif",
    ]

    public let kinds: [String]

    public init() {
        kinds = Self.loadKinds(from: Self.plantAdapterPath()) ?? fallbackKinds
    }

    public func contains(_ raw: String?) -> Bool {
        guard let normalized = Self.resolve(raw) else {
            return false
        }
        return kinds.contains(normalized)
    }

    public func canonical(_ raw: String?) -> PlantType {
        guard let normalized = Self.resolve(raw) else {
            return .unknown
        }
        return PlantType(rawValue: normalized) ?? .unknown
    }

    public static func resolve(_ raw: String?) -> String? {
        guard let raw else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            return nil
        }

        if canonicalKinds.contains(trimmed) {
            return trimmed
        }

        if let mapped = kindAliases[trimmed] {
            print("[PlantKindsCatalog] legacy alias resolved: \"\(trimmed)\" -> \"\(mapped)\"")
            return mapped
        }

        print("[PlantKindsCatalog] REFUSED: unsupported plant kind \"\(trimmed)\"")
        return nil
    }

    private static func plantAdapterPath() -> URL? {
        if let bundled = Bundle.module.url(
            forResource: "plant_adapters",
            withExtension: "json",
            subdirectory: "spec/native_fusion"
        ) {
            return bundled
        }
        let fm = FileManager.default
        var current = URL(fileURLWithPath: fm.currentDirectoryPath)
        for _ in 0..<12 {
            if current.lastPathComponent == "GAIAOS" {
                return current.appendingPathComponent("spec/native_fusion/plant_adapters.json")
            }
            let parent = current.deletingLastPathComponent()
            if parent == current {
                break
            }
            current = parent
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents")
            .appendingPathComponent("FoT8D")
            .appendingPathComponent("GAIAOS")
            .appendingPathComponent("spec/native_fusion/plant_adapters.json")
    }

    private static func loadKinds(from path: URL?) -> [String]? {
        guard let path,
              let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let object = json as? [String: Any],
              let rawKinds = object["kinds"] as? [String] else {
            return nil
        }
        let normalized = rawKinds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .filter { canonicalKinds.contains($0) }

        return normalized.isEmpty ? nil : normalized
    }
}

