import Foundation
import Network

/// Listens on `listenHost:listenPort` and forwards each TCP connection to `targetHost:targetPort`
/// (guest gateway inside the VZ NAT). Uses Network.framework for concurrent connections.
final class TCPPortForwarder {
    private let queue = DispatchQueue(label: "com.gaiaftcl.fusion-sidecar.forwarder", qos: .userInitiated)
    private var listener: NWListener?
    private let listenHostLabel: String
    private let listenPort: UInt16
    private let targetHost: NWEndpoint.Host
    private let targetPort: UInt16
    private let log: (String) -> Void

    init(
        listenHost: String = "127.0.0.1",
        listenPort: UInt16 = 8803,
        targetHost: String,
        targetPort: UInt16 = 8803,
        log: @escaping (String) -> Void = { _ in }
    ) {
        self.listenHostLabel = listenHost
        self.listenPort = listenPort
        self.targetHost = NWEndpoint.Host(targetHost)
        self.targetPort = targetPort
        self.log = log
    }

    func start() throws {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let port = NWEndpoint.Port(rawValue: listenPort) else {
            throw NSError(domain: "FusionSidecarHost", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid listen port"])
        }
        let listener = try NWListener(using: params, on: port)
        listener.newConnectionHandler = { [weak self] incoming in
            self?.handleIncoming(incoming)
        }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.log("Port forward listening on \(self?.listenHostLabel ?? ""):\(self?.listenPort ?? 0) → guest")
            case .failed(let err):
                self?.log("Listener failed: \(err)")
            default:
                break
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleIncoming(_ incoming: NWConnection) {
        incoming.start(queue: queue)
        let outgoing = NWConnection(host: targetHost, port: NWEndpoint.Port(rawValue: targetPort)!, using: .tcp)
        outgoing.start(queue: queue)

        relay(a: incoming, b: outgoing)
        relay(a: outgoing, b: incoming)
    }

    private func relay(a: NWConnection, b: NWConnection) {
        func recv() {
            a.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { data, _, isComplete, error in
                if error != nil {
                    a.cancel()
                    b.cancel()
                    return
                }
                if let data, !data.isEmpty {
                    b.send(content: data, completion: .contentProcessed { err in
                        if err != nil {
                            a.cancel()
                            b.cancel()
                            return
                        }
                        recv()
                    })
                } else if isComplete {
                    b.cancel()
                    a.cancel()
                } else {
                    recv()
                }
            }
        }
        recv()
    }
}
