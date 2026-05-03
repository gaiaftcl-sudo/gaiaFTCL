import Foundation
import GaiaFTCLCore
import GaiaGateKit

/// Global constitutional gates for the **C4** measurement plane: **τ** freshness + Franklin **mooring**.
final class VQbitMeasurementGate: @unchecked Sendable {
    static let shared = VQbitMeasurementGate()

    private let lock = NSLock()
    private var lastTauHeight: UInt64 = 0
    private var lamportCounter: Int64 = 0
    /// Until first **τ** frame (**self-fetch** or mesh), Lamport base may fall back to delta sequence.
    private var tauSeen = false
    private var tauStale = true
    private var moored = false
    private var tauSourceLabel: String = "none"
    private var staleWatch: Task<Void, Never>?

    private init() {}

    func recordTau(blockHeight: UInt64, sourceLabel: String) {
        lock.lock()
        lastTauHeight = blockHeight
        tauSeen = true
        tauStale = false
        tauSourceLabel = sourceLabel
        lamportCounter = 0
        lock.unlock()
        TauSyncStateFileWriter.write(blockHeight: blockHeight, tauSource: sourceLabel)
        staleWatch?.cancel()
        staleWatch = Task { [weak self] in
            try? await Task.sleep(for: .seconds(NATSConfiguration.tauStalenessSeconds))
            self?.markTauStale()
        }
    }

    /// Called when HTTP polling determines τ has exceeded staleness window (`TauSyncMonitor`).
    func notifyTauStaleFromMonitor() {
        lock.lock()
        tauStale = true
        lock.unlock()
    }

    func setMoored(_ value: Bool) {
        lock.lock()
        moored = value
        lock.unlock()
    }

    /// Next **τ**-anchored Lamport-style sequence for **C⁴** frames.
    func nextLamportSequence(fallback: Int64) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        guard tauSeen, lastTauHeight > 0 else { return fallback }
        lamportCounter += 1
        return Int64(lastTauHeight) * 1_000_000 + lamportCounter
    }

    enum BlockReason: Sendable {
        case none
        case unmoored
        case tauStaleOrAbsent
    }

    func blockReason() -> BlockReason {
        lock.lock()
        defer { lock.unlock() }
        return blockReasonLocked()
    }

    func mooringAcquired() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return moored
    }

    func tauSynchronized() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return tauSeen && !tauStale
    }

    func tauBlockHeightForHeartbeat() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return lastTauHeight
    }

    func tauSourceLabelForHeartbeat() -> String {
        lock.lock()
        defer { lock.unlock() }
        return tauSourceLabel
    }

    private func blockReasonLocked() -> BlockReason {
        if !tauSeen || tauStale { return .tauStaleOrAbsent }
        if !moored { return .unmoored }
        return .none
    }

    private func markTauStale() {
        lock.lock()
        tauStale = true
        lock.unlock()
    }
}

enum TauSyncStateFileWriter {
    private struct Payload: Codable {
        let block_height: UInt64
        let received_at_iso: String
        let tau_source: String?
        let schema_version: Int
    }

    static func write(blockHeight: UInt64, tauSource: String) {
        let p = Payload(
            block_height: blockHeight,
            received_at_iso: ISO8601DateFormatter().string(from: Date()),
            tau_source: tauSource,
            schema_version: 2
        )
        guard let data = try? JSONEncoder().encode(p) else { return }
        let url = GaiaInstallPaths.tauSyncStateURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
