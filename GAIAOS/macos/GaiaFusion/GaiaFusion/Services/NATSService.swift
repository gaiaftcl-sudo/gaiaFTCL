import Foundation
import Network

struct NATSCellEnvelope: Sendable {
    let subject: String
    let payload: Data
    let receivedAt: Date
}

actor NATSService {
    /// Shared singleton — used by PQ test protocols and GaiaFusion app.
    static let shared = NATSService()

    /// Last Bitcoin block height received on `gaiaftcl.bitcoin.heartbeat`.
    /// Updated by the bitcoin heartbeat subscription. nil = not yet received.
    private(set) var lastBitcoinTau: UInt64? = nil
    
    /// Connection status for PQ tests
    var isConnected: Bool {
        return connection != nil
    }
    
    /// Disconnect callback for PQ tests
    var onDisconnect: (() -> Void)?

    /// Connect to the local NATS server (nats://localhost:4222).
    /// Subscribes to `gaiaftcl.bitcoin.heartbeat` and updates `lastBitcoinTau`.
    /// Throws if NATS is unreachable (non-fatal in dev — mesh may not be running).
    func connect() async throws {
        let urlString = "nats://localhost:4222"
        guard isURLReachable(urlString) else {
            // Not an error in dev — bitcoin heartbeat service may be offline
            return
        }
        let _ = await startCellStatusStream(
            urlString: urlString,
            subjects: ["gaiaftcl.bitcoin.heartbeat"]
        ) { [weak self] envelope in
            guard let json = try? JSONSerialization.jsonObject(with: envelope.payload) as? [String: Any],
                  let blockHeight = json["block_height"] as? UInt64 else { return }
            Task { await self?.updateTau(blockHeight) }
        }
    }

    private func updateTau(_ blockHeight: UInt64) {
        lastBitcoinTau = blockHeight
    }

    private final class ProbeState: @unchecked Sendable {
        private var done = false
        private let continuation: CheckedContinuation<Bool, Never>

        init(_ continuation: CheckedContinuation<Bool, Never>) {
            self.continuation = continuation
        }

        func finish(_ value: Bool) {
            guard !done else {
                return
            }
            done = true
            continuation.resume(returning: value)
        }
    }

    private final class NATSProbeState: @unchecked Sendable {
        private var done = false
        private let continuation: CheckedContinuation<String, Never>

        init(_ continuation: CheckedContinuation<String, Never>) {
            self.continuation = continuation
        }

        func finish(_ value: String) {
            guard !done else {
                return
            }
            done = true
            continuation.resume(returning: value)
        }
    }

    private static let lineTerminator = Data([0x0D, 0x0A])
    private static let maxPayloadFallback = 4096
    private static let receiveBatchBytes = 65536

    private var connection: NWConnection?
    private var readerTask: Task<Void, Never>?
    private let receiveQueue = DispatchQueue(label: "fusion.nats.connection")

    func startCellStatusStream(
        urlString: String,
        subjects: [String],
        maxPayloadBytes: Int = maxPayloadFallback,
        onMessage: @Sendable @escaping (NATSCellEnvelope) -> Void
    ) async -> Bool {
        let normalizedSubjects = subjects
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalizedSubjects.isEmpty else {
            return false
        }

        await stopCellStatusStream()

        guard isURLReachable(urlString),
              let parsed = URLComponents(string: urlString),
              let host = parsed.host else {
            return false
        }

        let portValue = parsed.port ?? 4222
        guard let port = NWEndpoint.Port(rawValue: UInt16(portValue)) else {
            return false
        }

        let nwConnection = NWConnection(host: .init(host), port: port, using: .tcp)
        let connected = await withCheckedContinuation { continuation in
            let probe = ProbeState(continuation)
            nwConnection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    probe.finish(true)
                case .waiting(_), .failed:
                    probe.finish(false)
                default:
                    break
                }
            }
            nwConnection.start(queue: receiveQueue)
        }

        guard connected else {
            nwConnection.cancel()
            return false
        }

        connection = nwConnection

        let connectFrame = "CONNECT {\"verbose\":false,\"pedantic\":false,\"headers\":false}\r\n"
        guard await sendFrame(connectFrame, over: nwConnection) else {
            nwConnection.cancel()
            connection = nil
            return false
        }

        for (index, subject) in normalizedSubjects.enumerated() {
            let subscribeFrame = "SUB \(subject) \(index + 1)\r\n"
            let subscribed = await sendFrame(subscribeFrame, over: nwConnection)
            if !subscribed {
                nwConnection.cancel()
                connection = nil
                return false
            }
        }

        let pingSent = await sendFrame("PING\r\n", over: nwConnection)
        if !pingSent {
            nwConnection.cancel()
            connection = nil
            return false
        }

        readerTask = Task {
            await self.readLoop(connection: nwConnection, maxPayloadBytes: maxPayloadBytes, onMessage: onMessage)
        }

        return true
    }

    func stopCellStatusStream() async {
        readerTask?.cancel()
        readerTask = nil
        connection?.cancel()
        connection = nil
        onDisconnect?()
    }
    
    /// Simulate disconnect for PQ-SAF-007 testing
    func simulateDisconnect() {
        Task {
            await stopCellStatusStream()
        }
    }

    nonisolated func isURLReachable(_ raw: String) -> Bool {
        guard let url = URL(string: raw.lowercased()),
              let scheme = url.scheme,
              ["nats", "tls", "wss", "ws"].contains(scheme.lowercased()) else {
            return false
        }
        return url.host != nil
    }

    nonisolated func checkConnection(urlString: String) -> Bool {
        isURLReachable(urlString)
    }

    func natsServerID(from urlString: String) async -> String {
        guard isURLReachable(urlString),
              let parsed = URLComponents(string: urlString),
              let host = parsed.host,
              let rawPort = parsed.port else {
            return "nats_unavailable"
        }
        let port = NWEndpoint.Port(rawValue: UInt16(rawPort)) ?? .http
        return await withTaskGroup(of: String.self) { group in
            group.addTask { [host] in
                await self.fetchNatsServerID(host: host, port: port)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(4))
                return "nats_unavailable"
            }
            let first = await group.next() ?? "nats_unavailable"
            group.cancelAll()
            return first
        }
    }

    private func fetchNatsServerID(host: String, port: NWEndpoint.Port) async -> String {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "fusion.nats.service")
            let connection = NWConnection(host: .init(host), port: port, using: .tcp)
            let probeState = NATSProbeState(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.receive(
                        minimumIncompleteLength: 1,
                        maximumLength: 4096
                    ) { data, _, _, error in
                        if error != nil {
                            connection.cancel()
                            probeState.finish("nats_unavailable")
                            return
                        }
                        guard let data else {
                            connection.cancel()
                            probeState.finish("nats_unavailable")
                            return
                        }

                        let raw = String(data: data, encoding: .utf8) ?? ""
                        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard let infoStart = normalized.range(of: "{") else {
                            connection.cancel()
                            probeState.finish("nats_unavailable")
                            return
                        }
                        let infoJSON = String(normalized[infoStart.lowerBound...])
                        guard let infoData = infoJSON.data(using: .utf8),
                              let parsed = try? JSONSerialization.jsonObject(with: infoData) as? [String: Any],
                              let serverID = parsed["server_id"] as? String else {
                            connection.cancel()
                            probeState.finish("nats_unavailable")
                            return
                        }
                        connection.cancel()
                        probeState.finish(serverID)
                    }
                case .waiting(_):
                    connection.cancel()
                    probeState.finish("nats_unavailable")
                case .failed:
                    connection.cancel()
                    probeState.finish("nats_unavailable")
                case .cancelled, .preparing, .setup:
                    break
                @unknown default:
                    connection.cancel()
                    probeState.finish("nats_unavailable")
                }
            }
            connection.start(queue: queue)
        }
    }

    private func sendFrame(_ command: String, over nwConnection: NWConnection) async -> Bool {
        await withCheckedContinuation { continuation in
            guard let content = command.data(using: .utf8) else {
                continuation.resume(returning: false)
                return
            }
            nwConnection.send(content: content, completion: .contentProcessed { error in
                continuation.resume(returning: error == nil)
            })
        }
    }

    private func receiveChunk(from nwConnection: NWConnection) async -> Data? {
        await withCheckedContinuation { continuation in
            nwConnection.receive(minimumIncompleteLength: 1, maximumLength: Self.receiveBatchBytes) { data, _, _, error in
                if let _ = error {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }

    private func parseFrame(from buffer: inout Data, maxPayloadBytes: Int) -> ParsedFrame? {
        guard let lineEnd = buffer.range(of: Self.lineTerminator) else {
            return nil
        }

        let lineData = buffer.subdata(in: 0..<lineEnd.lowerBound)
        let headerEnd = lineEnd.upperBound
        let headerText = String(data: lineData, encoding: .utf8) ?? ""

        if headerText == "PING" {
            buffer.removeSubrange(0..<headerEnd)
            return .ping
        }

        if headerText.hasPrefix("INFO") || headerText.hasPrefix("-ERR") || headerText.hasPrefix("PONG") {
            buffer.removeSubrange(0..<headerEnd)
            return .ignored
        }

        if !headerText.hasPrefix("MSG ") {
            buffer.removeSubrange(0..<headerEnd)
            return .ignored
        }

        let parts = headerText.split(separator: " ")
        guard parts.count >= 4,
              let byteCount = Int(String(parts.last ?? "")) else {
            buffer.removeSubrange(0..<headerEnd)
            return .ignored
        }

        let subject = String(parts[1])
        let totalBytes = headerEnd + byteCount + 2
        if byteCount > maxPayloadBytes {
            guard buffer.count >= totalBytes else {
                return nil
            }
            buffer.removeSubrange(0..<totalBytes)
            return .ignored
        }

        guard buffer.count >= totalBytes else {
            return nil
        }

        let payloadStart = headerEnd
        let payloadEnd = headerEnd + byteCount
        let payload = buffer.subdata(in: payloadStart..<payloadEnd)
        let trailer = buffer.subdata(in: payloadEnd..<(payloadEnd + 2))
        buffer.removeSubrange(0..<totalBytes)

        guard trailer == Self.lineTerminator else {
            return .ignored
        }

        return .message(subject: subject, payload: payload)
    }

    private func readLoop(
        connection nwConnection: NWConnection,
        maxPayloadBytes: Int,
        onMessage: @Sendable @escaping (NATSCellEnvelope) -> Void
    ) async {
        var buffer = Data()
        while !Task.isCancelled {
            guard let chunk = await receiveChunk(from: nwConnection) else {
                return
            }
            guard !chunk.isEmpty else {
                continue
            }

            buffer.append(contentsOf: chunk)
            while true {
                guard let frame = parseFrame(from: &buffer, maxPayloadBytes: maxPayloadBytes) else {
                    break
                }

                switch frame {
                case .ping:
                    _ = await sendFrame("PONG\r\n", over: nwConnection)
                case .message(let subject, let payload):
                    onMessage(NATSCellEnvelope(subject: subject, payload: payload, receivedAt: Date()))
                case .ignored:
                    break
                }
            }
        }
    }

    private enum ParsedFrame {
        case ping
        case message(subject: String, payload: Data)
        case ignored
    }
}
