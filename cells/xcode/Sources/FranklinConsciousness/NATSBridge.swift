import Foundation
import FusionCore
import GaiaFTCLCore

/// Routes **`gaiaftcl.substrate.*`** to the **C4** broker (**`NATSConfiguration.vqbitNATSURL`**) and **`gaiaftcl.franklin.*`** (+ other non-substrate) to the **S4** broker (**`NATSConfiguration.franklinNATSURL`**).
public actor NATSBridge {
    public static let shared = NATSBridge()

    private let substrateClient: NATSClient
    private let franklinClient: NATSClient

    private var hasConnected = false
    private var routerStarted = false
    private var continuations: [String: [UUID: AsyncStream<NATSMessage>.Continuation]] = [:]
    private var requestedSubjects: Set<String> = []

    private var substrateConnected = false
    private var franklinConnected = false
    private var lastState: NATSClient.ConnectionState = .disconnected
    private var stateWatcherStarted = false

    public init(
        substrateURL: String = NATSConfiguration.vqbitNATSURL,
        franklinURL: String = NATSConfiguration.franklinNATSURL
    ) {
        let s = NATSBridge.parse(urlString: substrateURL)
        let f = NATSBridge.parse(urlString: franklinURL)
        self.substrateClient = NATSClient(host: s.host, port: s.port)
        self.franklinClient = NATSClient(host: f.host, port: f.port)
    }

    public func connectAndSubscribe(_ subjects: [String]) async {
        guard !hasConnected else { return }
        hasConnected = true
        for subject in subjects { requestedSubjects.insert(subject) }
        startStateWatchersIfNeeded()
        substrateClient.connect()
        franklinClient.connect()
        startRouterIfNeeded()
    }

    /// Waits until **both** brokers are connected (TCP + NATS `CONNECT` ack).
    public func waitUntilConnected(timeoutSeconds: UInt64 = 10) async -> Bool {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            if substrateConnected, franklinConnected { return true }
            if case .failed = lastState { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return substrateConnected && franklinConnected
    }

    public func publishJSON<T: Encodable>(subject: String, payload: T) async {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        client(for: subject).publish(subject: subject, payload: data)
    }

    public func publishText(subject: String, text: String) async {
        client(for: subject).publish(subject: subject, payload: Data(text.utf8))
    }

    /// Binary substrate frames (**S⁴**, **C⁴**, **stage.altered**) — always **C4** broker.
    public func publishWire(subject: String, payload: Data) async {
        substrateClient.publish(subject: subject, payload: payload)
    }

    public func subscribe(subject: String) -> AsyncStream<NATSMessage> {
        startRouterIfNeeded()
        requestedSubjects.insert(subject)
        if substrateConnected, Self.isSubstrateSubject(subject) {
            substrateClient.subscribe(to: subject)
        }
        if franklinConnected, !Self.isSubstrateSubject(subject) {
            franklinClient.subscribe(to: subject)
        }
        let id = UUID()
        let (stream, continuation) = AsyncStream<NATSMessage>.makeStream()
        if continuations[subject] == nil { continuations[subject] = [:] }
        continuations[subject]?[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(subject: subject, id: id) }
        }
        return stream
    }

    private func removeContinuation(subject: String, id: UUID) {
        continuations[subject]?[id] = nil
        if continuations[subject]?.isEmpty == true {
            continuations[subject] = nil
        }
    }

    private func startRouterIfNeeded() {
        guard !routerStarted else { return }
        routerStarted = true
        Task { [weak self] in
            guard let self else { return }
            for await msg in self.substrateClient.messages {
                await self.route(msg)
            }
        }
        Task { [weak self] in
            guard let self else { return }
            for await msg in self.franklinClient.messages {
                await self.route(msg)
            }
        }
    }

    private func route(_ message: NATSMessage) {
        guard let subjectMap = continuations[message.subject] else { return }
        for (_, continuation) in subjectMap {
            continuation.yield(message)
        }
    }

    private func startStateWatchersIfNeeded() {
        guard !stateWatcherStarted else { return }
        stateWatcherStarted = true
        Task { [weak self] in
            guard let self else { return }
            for await state in self.substrateClient.stateStream {
                await self.handleSubstrateState(state)
            }
        }
        Task { [weak self] in
            guard let self else { return }
            for await state in self.franklinClient.stateStream {
                await self.handleFranklinState(state)
            }
        }
    }

    private func handleSubstrateState(_ state: NATSClient.ConnectionState) {
        switch state {
        case .connected:
            substrateConnected = true
            resubscribeSubstrate()
            mergeConnectionState()
        case .failed(let msg):
            lastState = .failed(msg)
        case .disconnected:
            substrateConnected = false
            mergeConnectionState()
        default:
            break
        }
    }

    private func handleFranklinState(_ state: NATSClient.ConnectionState) {
        switch state {
        case .connected:
            franklinConnected = true
            resubscribeFranklin()
            mergeConnectionState()
        case .failed(let msg):
            lastState = .failed(msg)
        case .disconnected:
            franklinConnected = false
            mergeConnectionState()
        default:
            break
        }
    }

    private func mergeConnectionState() {
        if substrateConnected, franklinConnected {
            lastState = .connected
        } else if case .failed = lastState {
            return
        } else {
            lastState = .connecting
        }
    }

    private func resubscribeSubstrate() {
        for subject in requestedSubjects where Self.isSubstrateSubject(subject) {
            substrateClient.subscribe(to: subject)
        }
    }

    private func resubscribeFranklin() {
        for subject in requestedSubjects where !Self.isSubstrateSubject(subject) {
            franklinClient.subscribe(to: subject)
        }
    }

    private func client(for subject: String) -> NATSClient {
        Self.isSubstrateSubject(subject) ? substrateClient : franklinClient
    }

    private static func isSubstrateSubject(_ subject: String) -> Bool {
        subject.hasPrefix("gaiaftcl.substrate.")
    }

    private static func parse(urlString: String) -> (host: String, port: UInt16) {
        guard let url = URL(string: urlString), let host = url.host else {
            return ("127.0.0.1", 4222)
        }
        let port = UInt16(url.port ?? 4222)
        return (host, port)
    }
}
