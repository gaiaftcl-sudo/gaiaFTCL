import Foundation
import FusionCore
import GaiaFTCLCore
import GaiaFTCLScene
import VQbitSubstrate

/// Subscribes to the vQbit VM C4 projection stream on port 4222 and updates
/// the UI overlay store. Message consumption runs in a MainActor Task so
/// overlay writes are always on the main actor without cross-actor hops.
final class LocalC4Subscriber: @unchecked Sendable {

    private var nats: NATSClient?
    private var msgTask: Task<Void, Never>?

    @MainActor
    func start(overlay: ManifoldOverlayStore) {
        guard msgTask == nil else { return }
        let urlStr = NATSConfiguration.vqbitNATSURL
        let (host, port) = parseURL(urlStr)
        let client = NATSClient(host: host, port: port)
        nats = client
        client.connect()
        client.subscribe(to: NATSConfiguration.c4ProjectionSubject)

        msgTask = Task { @MainActor in
            for await msg in client.messages {
                guard msg.subject == NATSConfiguration.c4ProjectionSubject,
                      let wire = try? C4ProjectionCodec.decode(msg.payload) else { continue }
                let ts = ISO8601DateFormatter().string(
                    from: Date(timeIntervalSince1970: Double(wire.timestampMs) / 1_000)
                )
                let state = ManifoldState(
                    s1_structural:  0.5,
                    s2_temporal:    0.5,
                    s3_spatial:     0.5,
                    s4_observable:  0.5,
                    c1_trust:       Double(wire.c1Trust),
                    c2_identity:    Double(wire.c2Identity),
                    c3_closure:     Double(wire.c3Closure),
                    c4_consequence: Double(wire.c4Consequence),
                    timestampUTC:   ts,
                    terminalHint:   TerminalWireBridge.terminalState(fromVisualCode: wire.terminal.rawValue)
                )
                C4ManifoldRuntimeBridge.update(primID: wire.primID, state: state)
                overlay.update(state)
            }
        }
    }

    private func parseURL(_ url: String) -> (host: String, port: UInt16) {
        guard let u = URL(string: url), let h = u.host else { return ("127.0.0.1", 4222) }
        return (h, UInt16(u.port ?? 4222))
    }
}
