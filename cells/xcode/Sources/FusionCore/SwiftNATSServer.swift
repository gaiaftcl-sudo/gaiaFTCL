// SwiftNATSServer.swift — Pure-Swift NATS 2.x text-protocol server.
// Replaces the external Go nats-server binary entirely.
// Uses only Apple Network.framework (NWListener / NWConnection).
// Handles SUB, PUB, CONNECT, PING/PONG, UNSUB, and subject wildcards (* and >).
import Foundation
import Network

public final class SwiftNATSServer: @unchecked Sendable {

    public let port: UInt16

    private let queue = DispatchQueue(label: "com.gaiaftcl.nats-server.io", qos: .userInteractive)
    private var listener: NWListener?

    // Per-connection state, keyed by connection object identity.
    private var connections: [Int: NWConnection] = [:]
    private var buffers: [Int: Data] = [:]
    // (connKey, subject pattern, sid) tuples
    private var subscriptions: [(key: Int, pattern: String, sid: String)] = []

    private nonisolated(unsafe) static var nextKey = 0
    private var connectionKeys: [ObjectIdentifier: Int] = [:]

    public init(port: UInt16) {
        self.port = port
    }

    public func start() {
        queue.async { self.startListener() }
    }

    public func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            self.connections.values.forEach { $0.cancel() }
            self.connections.removeAll()
            self.buffers.removeAll()
            self.subscriptions.removeAll()
            self.connectionKeys.removeAll()
        }
    }

    // MARK: - Listener

    private func startListener() {
        do {
            let l = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
            l.newConnectionHandler = { [weak self] conn in
                self?.queue.async { self?.accept(conn) }
            }
            l.stateUpdateHandler = { state in
                if case .failed(let err) = state {
                    fputs("SwiftNATSServer port \(self.port): listener failed: \(err)\n", stderr)
                }
            }
            l.start(queue: queue)
            listener = l
        } catch {
            fputs("SwiftNATSServer port \(self.port): bind error: \(error)\n", stderr)
        }
    }

    // MARK: - Connection lifecycle

    private func accept(_ conn: NWConnection) {
        let key = nextConnectionKey()
        connectionKeys[ObjectIdentifier(conn)] = key
        connections[key] = conn
        buffers[key] = Data()

        let info = "INFO {\"server_id\":\"gaia-swift\",\"version\":\"2.10.0\",\"proto\":1,\"max_payload\":1048576}\r\n"
        conn.send(content: Data(info.utf8), completion: .contentProcessed { _ in })

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed, .cancelled:
                self.queue.async { self.drop(key: key) }
            default:
                break
            }
        }
        conn.start(queue: queue)
        receive(key: key, conn: conn)
    }

    private func drop(key: Int) {
        connections[key]?.cancel()
        connections.removeValue(forKey: key)
        buffers.removeValue(forKey: key)
        subscriptions.removeAll { $0.key == key }
    }

    private func nextConnectionKey() -> Int {
        SwiftNATSServer.nextKey += 1
        return SwiftNATSServer.nextKey
    }

    // MARK: - Receive loop

    private func receive(key: Int, conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 131_072) { [weak self] data, _, isDone, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffers[key, default: Data()].append(data)
                self.parse(key: key, conn: conn)
            }
            if isDone || error != nil {
                self.drop(key: key)
            } else {
                self.receive(key: key, conn: conn)
            }
        }
    }

    // MARK: - NATS text-protocol parser

    private func parse(key: Int, conn: NWConnection) {
        let crlf = Data("\r\n".utf8)
        while var buf = buffers[key], !buf.isEmpty {
            guard let lineEnd = buf.range(of: crlf) else { break }
            guard let line = String(data: buf[buf.startIndex..<lineEnd.lowerBound], encoding: .utf8) else {
                buf.removeSubrange(buf.startIndex..<lineEnd.upperBound)
                buffers[key] = buf
                continue
            }

            if line == "PING" {
                conn.send(content: Data("PONG\r\n".utf8), completion: .contentProcessed { _ in })
                buf.removeSubrange(buf.startIndex..<lineEnd.upperBound)
                buffers[key] = buf

            } else if line == "PONG" || line.hasPrefix("CONNECT ") {
                buf.removeSubrange(buf.startIndex..<lineEnd.upperBound)
                buffers[key] = buf

            } else if line.hasPrefix("SUB ") {
                let parts = line.dropFirst(4).split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 2 {
                    let pattern = String(parts[0])
                    let sid     = String(parts[parts.count - 1])
                    subscriptions.append((key: key, pattern: pattern, sid: sid))
                }
                buf.removeSubrange(buf.startIndex..<lineEnd.upperBound)
                buffers[key] = buf

            } else if line.hasPrefix("UNSUB ") {
                let parts = line.dropFirst(6).split(separator: " ", omittingEmptySubsequences: true)
                if let sid = parts.first.map(String.init) {
                    subscriptions.removeAll { $0.key == key && $0.sid == sid }
                }
                buf.removeSubrange(buf.startIndex..<lineEnd.upperBound)
                buffers[key] = buf

            } else if line.hasPrefix("PUB ") {
                let parts = line.dropFirst(4).split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count >= 2, let nbytes = Int(parts.last!) else {
                    buf.removeSubrange(buf.startIndex..<lineEnd.upperBound)
                    buffers[key] = buf
                    continue
                }
                let subject    = String(parts[0])
                let payloadStart = lineEnd.upperBound
                let needed = nbytes + 2
                guard buf.endIndex - payloadStart >= needed else { break }  // wait for more data
                let payload = Data(buf[payloadStart..<(payloadStart + nbytes)])
                buf.removeSubrange(buf.startIndex..<(payloadStart + needed))
                buffers[key] = buf
                route(from: key, subject: subject, payload: payload)

            } else {
                buf.removeSubrange(buf.startIndex..<lineEnd.upperBound)
                buffers[key] = buf
            }
        }
    }

    // MARK: - Message routing

    private func route(from senderKey: Int, subject: String, payload: Data) {
        for sub in subscriptions {
            guard matches(pattern: sub.pattern, subject: subject) else { continue }
            guard let conn = connections[sub.key] else { continue }
            let header = "MSG \(subject) \(sub.sid) \(payload.count)\r\n"
            var frame = Data(header.utf8)
            frame.append(payload)
            frame.append(Data("\r\n".utf8))
            conn.send(content: frame, completion: .contentProcessed { _ in })
        }
    }

    private func matches(pattern: String, subject: String) -> Bool {
        if pattern == subject { return true }
        if pattern == ">" { return true }
        if pattern.hasSuffix(".>") {
            return subject.hasPrefix(String(pattern.dropLast(2)))
        }
        let pp = pattern.split(separator: ".", omittingEmptySubsequences: false)
        let sp = subject.split(separator: ".", omittingEmptySubsequences: false)
        guard pp.count == sp.count else { return false }
        return zip(pp, sp).allSatisfy { p, s in p == "*" || p == s }
    }
}
