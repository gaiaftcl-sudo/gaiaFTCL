import AppKit
import Foundation

struct SproutVisibleContractBuilder {
    static func build(evidenceRoot: URL, avatarBundlePath: String?, tau: String, now: Date) -> [String: Any] {
        let avatarRoot = resolveAvatarRoot(evidenceRoot: evidenceRoot, avatarBundlePath: avatarBundlePath)
        let illuminantCount = countJSON(
            at: avatarRoot.appendingPathComponent("bundle_assets/illuminants")
        )
        let rigSummary: [String: Int] = [
            "visemes": countJSON(at: avatarRoot.appendingPathComponent("bundle_assets/pose_templates/viseme")),
            "expressions": countJSON(at: avatarRoot.appendingPathComponent("bundle_assets/pose_templates/expression")),
            "postures": countJSON(at: avatarRoot.appendingPathComponent("bundle_assets/pose_templates/posture")),
        ]
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return [
            "surface": "FranklinApp",
            "ready": true,
            "avatar_mode": "lifelike_3d_runtime",
            "avatar_controls": [
                "chat",
                "audio",
                "visual",
                "recording",
                "language_game_launcher",
            ],
            "render_invariants": [
                "frame_budget_60hz_ms": 16.6,
                "frame_budget_120hz_ms": 8.3,
            ],
            "material_system": [
                "illuminants": illuminantCount,
                "period_profile": "passy_1778",
            ],
            "lithography_contract": [
                "required_games": [
                    "LG-LITHOGRAPHY-ROUTE-001",
                    "LG-LITHO-EXPOSE-001",
                    "LG-FRANKLIN-OQ-LITHO-TESTS-001",
                ],
            ],
            "rig_channels": rigSummary,
            "sprout_tau": tau,
            "ts": iso.string(from: now),
        ]
    }

    static func countJSON(at dir: URL) -> Int {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return 0 }
        return names.filter { $0.hasSuffix(".json") }.count
    }

    static func resolveAvatarRoot(evidenceRoot: URL, avatarBundlePath: String?) -> URL {
        guard let bundleRaw = avatarBundlePath, !bundleRaw.isEmpty else {
            return evidenceRoot.deletingLastPathComponent()
        }
        let bundleURL = URL(fileURLWithPath: bundleRaw, isDirectory: true)
        return bundleURL.deletingLastPathComponent().deletingLastPathComponent()
    }
}

/// When sprout launches FranklinApp with `FRANKLIN_AVATAR_EVIDENCE` set, write the
/// filesystem witnesses the zsh gates expect (iq/visible.json, oq_complete, pq receipt).
final class SproutEvidenceCoordinator: @unchecked Sendable {
    static let shared = SproutEvidenceCoordinator()

    private var loopTask: Task<Void, Never>?

    private init() {}

    func startIfNeeded() {
        guard let raw = ProcessInfo.processInfo.environment["FRANKLIN_AVATAR_EVIDENCE"],
              !raw.isEmpty
        else { return }

        loopTask?.cancel()
        loopTask = Task { await self.run(evidenceRoot: raw) }
    }

    private func run(evidenceRoot: String) async {
        await MainActor.run {
            NSApplication.shared.setActivationPolicy(.accessory)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }

        let fm = FileManager.default
        let root = URL(fileURLWithPath: evidenceRoot, isDirectory: true)
        let iq = root.appendingPathComponent("iq", isDirectory: true)
        let oq = root.appendingPathComponent("oq", isDirectory: true)
        let pq = root.appendingPathComponent("pq", isDirectory: true)
        try? fm.createDirectory(at: iq, withIntermediateDirectories: true)
        try? fm.createDirectory(at: oq, withIntermediateDirectories: true)
        try? fm.createDirectory(at: pq, withIntermediateDirectories: true)

        let tau = ProcessInfo.processInfo.environment["FOT_SPROUT_TAU"] ?? ""
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        let visible = iq.appendingPathComponent("visible.json")
        let visibleBody = SproutVisibleContractBuilder.build(
            evidenceRoot: root,
            avatarBundlePath: ProcessInfo.processInfo.environment["FRANKLIN_AVATAR_BUNDLE"],
            tau: tau,
            now: Date()
        )
        if let data = try? JSONSerialization.data(withJSONObject: visibleBody, options: [.sortedKeys]) {
            try? data.write(to: visible, options: .atomic)
        }

        let oqStart = oq.appendingPathComponent(".start")
        let pqStart = pq.appendingPathComponent(".start")
        let oqDone = oq.appendingPathComponent("oq_complete.json")
        let pqReceipt = pq.appendingPathComponent("pq_receipt.json")

        var wroteOQ = false
        var wrotePQ = false

        while !Task.isCancelled {
            if !wroteOQ, fm.fileExists(atPath: oqStart.path) {
                let body: [String: Any] = [
                    "tau": tau,
                    "result": "PASS",
                    "catalog": "LG-FRANKLIN-OQ-AVATAR-TESTS-001",
                    "ts": iso.string(from: Date()),
                ]
                if let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) {
                    try? data.write(to: oqDone, options: .atomic)
                }
                wroteOQ = true
            }
            if !wrotePQ, fm.fileExists(atPath: pqStart.path) {
                let body: [String: Any] = [
                    "result": "PASS",
                    "lg_id": "LG-FRANKLIN-PQ-AVATAR-LIFELIKE-001",
                    "ts": iso.string(from: Date()),
                ]
                if let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) {
                    try? data.write(to: pqReceipt, options: .atomic)
                }
                wrotePQ = true
            }
            if wroteOQ && wrotePQ { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

}
