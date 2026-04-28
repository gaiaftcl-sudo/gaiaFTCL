import Foundation

struct FranklinAppConfiguration {
    let enforceHardLaunchGate: Bool
    let showTechnicalDiagnostics: Bool

    static func load() -> FranklinAppConfiguration {
        FranklinAppConfiguration(
            enforceHardLaunchGate: envFlag("FRANKLIN_STRICT_LAUNCH_GATE", defaultValue: false),
            showTechnicalDiagnostics: envFlag("FRANKLIN_SHOW_TECHNICAL_DIAGNOSTICS", defaultValue: false)
        )
    }

    private static func envFlag(_ key: String, defaultValue: Bool) -> Bool {
        guard let raw = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return defaultValue
        }
        return raw == "1" || raw == "true" || raw == "yes" || raw == "on"
    }
}
