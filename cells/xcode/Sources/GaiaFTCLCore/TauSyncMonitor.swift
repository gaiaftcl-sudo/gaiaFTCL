import Foundation

// MARK: — Plaintext tip-height response (testable)

public enum TauSyncHTTPParsing: Sendable {
    /// Blockstream / mempool `GET …/blocks/tip/height` returns ASCII digits only.
    public static func blockHeight(fromPlaintextTipBody data: Data) -> UInt64? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return UInt64(trimmed)
    }
}

/// τ (Bitcoin block height) — self-sovereign timing primitive.
///
/// The vQbit VM fetches block height directly via URLSession.
/// Mesh τ from `gaiaftcl.mesh.tau` is accepted when present (**additive**), never required.
public actor TauSyncMonitor {
    public struct TauState: Sendable {
        public let blockHeight: UInt64
        public let source: Source
        public let receivedAt: Date

        public enum Source: Sendable, Equatable {
            case selfFetched
            case meshReceived
        }
    }

    private static let primaryURL = "https://blockstream.info/api/blocks/tip/height"
    private static let fallbackURL = "https://mempool.space/api/blocks/tip/height"
    private static let pollInterval: Double = 60

    public private(set) var current: TauState?
    public private(set) var isStale: Bool = false

    private let onTick: @Sendable (TauState) async -> Void
    private let onStale: @Sendable () async -> Void
    private var pollTask: Task<Void, Never>?

    public init(
        onTick: @escaping @Sendable (TauState) async -> Void,
        onStale: @escaping @Sendable () async -> Void
    ) {
        self.onTick = onTick
        self.onStale = onStale
    }

    public func start() {
        pollTask?.cancel()
        pollTask = Task {
            await self.fetchAndTick()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.pollInterval))
                guard !Task.isCancelled else { break }
                await self.fetchAndTick()
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Optional mesh publisher on **`gaiaftcl.mesh.tau`** — accepted when **`block_height`** advances current.
    public func receiveMeshTau(_ data: Data) async {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let height = (dict["block_height"] as? UInt64)
              ?? (dict["block_height"] as? Int).map(UInt64.init)
        else { return }

        guard height > (current?.blockHeight ?? 0) else { return }

        let state = TauState(
            blockHeight: height,
            source: .meshReceived,
            receivedAt: Date()
        )
        current = state
        isStale = false
        await onTick(state)
    }

    private func fetchAndTick() async {
        guard let height = await fetchBlockHeight() else { return }
        guard height > (current?.blockHeight ?? 0) else { return }

        let state = TauState(
            blockHeight: height,
            source: .selfFetched,
            receivedAt: Date()
        )
        current = state
        isStale = false
        await onTick(state)
    }

    private func fetchBlockHeight() async -> UInt64? {
        for urlString in [Self.primaryURL, Self.fallbackURL] {
            guard let url = URL(string: urlString) else { continue }
            do {
                var request = URLRequest(url: url, timeoutInterval: 10)
                request.setValue("GaiaFTCL/1.0", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
                guard let height = TauSyncHTTPParsing.blockHeight(fromPlaintextTipBody: data) else { continue }
                return height
            } catch {
                continue
            }
        }
        if let last = current?.receivedAt,
           Date().timeIntervalSince(last) > NATSConfiguration.tauStalenessSeconds {
            isStale = true
            await onStale()
        }
        return nil
    }

    public var lamportBase: Int64 {
        Int64(current?.blockHeight ?? 0) * 1_000_000
    }

    public var sourceLabel: String {
        switch current?.source {
        case .selfFetched: return "self"
        case .meshReceived: return "mesh"
        case nil: return "none"
        }
    }
}
