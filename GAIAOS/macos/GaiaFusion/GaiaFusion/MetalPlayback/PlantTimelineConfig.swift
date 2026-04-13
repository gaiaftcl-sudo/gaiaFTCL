import Foundation

/// `timeline_v2.json` beside each `plants/<kind>/root.usda`.
struct PlantTimelineConfig: Codable, Sendable {
    let schema: String
    let plant: String
    let usdRoot: String
    let driveVariable: String
    let telemetryInputs: [String]?
    let phases: [Phase]
    let timeCodeEnd: Double
    let telemetryMin: Double?
    let telemetryMax: Double?
    /// Scale for `drive_variable` == `vqbit_rate` (delta since ENGAGE / mesh vQbit sample).
    let vqbitScale: Double?

    struct Phase: Codable, Sendable {
        let id: String
        let start: Double
        let end: Double
    }

    enum CodingKeys: String, CodingKey {
        case schema
        case plant
        case usdRoot = "usd_root"
        case driveVariable = "drive_variable"
        case telemetryInputs = "telemetry_inputs"
        case phases
        case timeCodeEnd = "time_code_end"
        case telemetryMin = "telemetry_min"
        case telemetryMax = "telemetry_max"
        case vqbitScale = "vqbit_scale"
    }
}
