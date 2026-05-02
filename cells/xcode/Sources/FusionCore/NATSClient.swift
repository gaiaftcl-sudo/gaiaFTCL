// NATSClient.swift — Native NATS 2.x client for the GaiaFTCL mesh.
// Implements the NATS text protocol over a raw TCP NWConnection.
// All I/O runs on a private DispatchQueue; messages are delivered via
// AsyncStream so callers can consume with `for await` on any actor.
import Foundation
import Network

/// A single NATS message received from the broker.
public struct NATSMessage: Sendable {
    public let subject: String
    public let replyTo: String?
    public let payload: Data
}

/// Minimal NATS 2.x client. @unchecked Sendable — all mutable state is
/// confined to `queue`; external API methods dispatch to `queue` before
/// touching any internal state.
public final class NATSClient: @unchecked Sendable {

    public enum ConnectionState: Sendable, CustomStringConvertible {
        case disconnected
        case connecting
        case connected
        case failed(String)

        public var description: String {
            switch self {
            case .disconnected:    return "disconnected"
            case .connecting:      return "connecting"
            case .connected:       return "connected"
            case .failed(let msg): return "failed(\(msg))"
            }
        }
    }

    // ── AsyncStream outputs ───────────────────────────────────────────────

    public let messages:    AsyncStream<NATSMessage>
    public let stateStream: AsyncStream<ConnectionState>

    private let msgCont:   AsyncStream<NATSMessage>.Continuation
    private let stateCont: AsyncStream<ConnectionState>.Continuation

    // ── Internal state (confined to queue) ───────────────────────────────

    private let queue = DispatchQueue(label: "com.gaiaftcl.nats.io", qos: .userInteractive)
    private var connection: NWConnection?
    private var connectTimeoutItem: DispatchWorkItem?   // guards 75-s NWConnection hang on filtered port
    private var buffer = Data()
    private var nextSID = 1

    public let host: String
    public let port: UInt16

    public init(
        host: String = GuestNetworkDefaults.natsMeshHost,
        port: UInt16 = GuestNetworkDefaults.natsRelayPort
    ) {
        self.host = host
        self.port = port
        (messages,    msgCont)   = AsyncStream.makeStream(of: NATSMessage.self)
        (stateStream, stateCont) = AsyncStream.makeStream(of: ConnectionState.self)
    }

    // ── Public API ────────────────────────────────────────────────────────

    /// Open a TCP connection to the NATS broker and send CONNECT.
    /// A 5-second hard timeout prevents the 75-second NWConnection hang
    /// that occurs when the port is firewall-filtered (packets dropped, not refused).
    public func connect() {
        queue.async { [weak self] in
            guard let self else { return }
            self.connectTimeoutItem?.cancel()
            self.connectTimeoutItem = nil
            self.connection?.cancel()
            guard let port = NWEndpoint.Port(rawValue: self.port) else { return }
            let conn = NWConnection(
                host: NWEndpoint.Host(self.host),
                port: port,
                using: .tcp
            )
            conn.stateUpdateHandler = { [weak self] state in
                self?.handleState(state)
            }
            conn.start(queue: self.queue)
            self.connection = conn
            self.stateCont.yield(.connecting)

            // 5-second hard timeout — fires on queue, so serialized with handleState
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, self.connectTimeoutItem != nil else { return }
                self.connectTimeoutItem = nil
                self.connection?.cancel()
                self.connection = nil
                self.stateCont.yield(.failed("Connect timeout (5s) — no NATS at \(self.host):\(self.port)"))
            }
            self.connectTimeoutItem = timeout
            self.queue.asyncAfter(deadline: .now() + 5, execute: timeout)
        }
    }

    /// Subscribe to a NATS subject (wildcards: `*` single, `>` recursive).
    public func subscribe(to subject: String) {
        queue.async { [weak self] in
            self?.performSubscribe(subject)
        }
    }

    /// Same as **`subscribe`** but completes before returning — ensures **`SUB`** is on the wire before callers publish or attach consumers (**vQbit VM** startup).
    public func subscribeSync(to subject: String) {
        queue.sync { [weak self] in
            self?.performSubscribe(subject)
        }
    }

    private func performSubscribe(_ subject: String) {
        let sid = nextSID
        nextSID += 1
        rawSend("SUB \(subject) \(sid)\r\n")
    }

    /// Publish a message to a subject.
    public func publish(subject: String, payload: Data) {
        queue.async { [weak self] in
            guard let self, let conn = self.connection else { return }
            let header = Data("PUB \(subject) \(payload.count)\r\n".utf8)
            var frame = header
            frame.append(payload)
            frame.append(Data("\r\n".utf8))
            conn.send(content: frame, completion: .contentProcessed { _ in })
        }
    }

    /// Gracefully close the connection and finish all streams.
    public func disconnect() {
        queue.async { [weak self] in
            self?.connection?.cancel()
            self?.connection = nil
            self?.stateCont.yield(.disconnected)
            self?.stateCont.finish()
            self?.msgCont.finish()
        }
    }

    // ── Connection state machine ──────────────────────────────────────────

    private func handleState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            connectTimeoutItem?.cancel()
            connectTimeoutItem = nil
            rawSend("CONNECT {\"verbose\":false,\"pedantic\":false,\"name\":\"gaiaftcl-mac\",\"protocol\":1}\r\n")
            stateCont.yield(.connected)
            receive()
        case .failed(let err):
            connectTimeoutItem?.cancel()
            connectTimeoutItem = nil
            stateCont.yield(.failed(err.localizedDescription))
        case .cancelled:
            connectTimeoutItem?.cancel()
            connectTimeoutItem = nil
            stateCont.yield(.disconnected)
        default:
            break
        }
    }

    // ── I/O ───────────────────────────────────────────────────────────────

    private func rawSend(_ text: String) {
        connection?.send(content: Data(text.utf8), completion: .contentProcessed { _ in })
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 131_072) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.parseBuffer()
            }
            if isComplete || error != nil {
                self.stateCont.yield(.disconnected)
            } else {
                self.receive()
            }
        }
    }

    // ── NATS protocol parser ──────────────────────────────────────────────
    // Lines end in \r\n. MSG lines are followed by `nbytes` of payload + \r\n.

    private func parseBuffer() {
        let crlf = Data("\r\n".utf8)
        while !buffer.isEmpty {
            guard let lineRange = buffer.range(of: crlf) else { break }
            let lineBytes = buffer[buffer.startIndex..<lineRange.lowerBound]
            guard let line = String(data: lineBytes, encoding: .utf8) else {
                buffer.removeSubrange(buffer.startIndex..<lineRange.upperBound)
                continue
            }

            if line == "PING" {
                buffer.removeSubrange(buffer.startIndex..<lineRange.upperBound)
                rawSend("PONG\r\n")

            } else if line.hasPrefix("MSG ") {
                // MSG <subject> <sid> [replyTo] <nbytes>
                let parts = line.dropFirst(4).split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count >= 3 else {
                    buffer.removeSubrange(buffer.startIndex..<lineRange.upperBound)
                    continue
                }
                guard let nbytes = Int(parts.last!) else {
                    buffer.removeSubrange(buffer.startIndex..<lineRange.upperBound)
                    continue
                }
                let subject = String(parts[0])
                let replyTo = parts.count == 4 ? String(parts[2]) : nil
                let payloadStart = lineRange.upperBound
                let needed = nbytes + 2          // payload + trailing \r\n
                guard buffer.endIndex - payloadStart >= needed else { break }
                let payload = Data(buffer[payloadStart..<(payloadStart + nbytes)])
                buffer.removeSubrange(buffer.startIndex..<(payloadStart + needed))
                msgCont.yield(NATSMessage(subject: subject, replyTo: replyTo, payload: payload))

            } else {
                // INFO, +OK, -ERR, PONG — consume and continue
                buffer.removeSubrange(buffer.startIndex..<lineRange.upperBound)
            }
        }
    }
}
