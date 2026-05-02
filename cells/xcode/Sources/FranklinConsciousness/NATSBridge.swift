import Foundation
import FusionCore

public actor NATSBridge {
    public static let shared = NATSBridge()

    private let client: NATSClient
    private var hasConnected = false
    private var routerStarted = false
    private var continuations: [String: [UUID: AsyncStream<NATSMessage>.Continuation]] = [:]
    private var requestedSubjects: Set<String> = []
    private var lastState: NATSClient.ConnectionState = .disconnected
    private var stateWatcherStarted = false

    public init(urlString: String? = ProcessInfo.processInfo.environment["GAIAFTCL_NATS_URL"]) {
        let (host, port) = NATSBridge.parse(urlString: urlString)
        self.client = NATSClient(host: host, port: port)
    }

    public func connectAndSubscribe(_ subjects: [String]) async {
        guard !hasConnected else { return }
        hasConnected = true
        for subject in subjects { requestedSubjects.insert(subject) }
        startStateWatcherIfNeeded()
        client.connect()
        startRouterIfNeeded()
    }

    public func publishJSON<T: Encodable>(subject: String, payload: T) async {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        client.publish(subject: subject, payload: data)
    }

    public func publishText(subject: String, text: String) async {
        client.publish(subject: subject, payload: Data(text.utf8))
    }

    /// Binary substrate frames (**S⁴**, **C⁴**, **stage.altered**).
    public func publishWire(subject: String, payload: Data) async {
        client.publish(subject: subject, payload: payload)
    }

    public func subscribe(subject: String) -> AsyncStream<NATSMessage> {
        startRouterIfNeeded()
        requestedSubjects.insert(subject)
        if case .connected = lastState {
            client.subscribe(to: subject)
        }
        let id = UUID()
        return AsyncStream { cont in
            if self.continuations[subject] == nil { self.continuations[subject] = [:] }
            self.continuations[subject]?[id] = cont
            cont.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(subject: subject, id: id) }
            }
        }
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
            for await msg in self.client.messages {
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

    private func startStateWatcherIfNeeded() {
        guard !stateWatcherStarted else { return }
        stateWatcherStarted = true
        Task { [weak self] in
            guard let self else { return }
            for await state in self.client.stateStream {
                await self.handleState(state)
            }
        }
    }

    private func handleState(_ state: NATSClient.ConnectionState) {
        lastState = state
        if case .connected = state {
            for subject in requestedSubjects {
                client.subscribe(to: subject)
            }
        }
    }

    private static func parse(urlString: String?) -> (String, UInt16) {
        guard let raw = urlString, let url = URL(string: raw), let host = url.host else {
            return (GuestNetworkDefaults.natsGuestPort == 4222 ? "127.0.0.1" : GuestNetworkDefaults.natsMeshHost, GuestNetworkDefaults.natsGuestPort)
        }
        let port = UInt16(url.port ?? Int(GuestNetworkDefaults.natsGuestPort))
        return (host, port)
    }
}
