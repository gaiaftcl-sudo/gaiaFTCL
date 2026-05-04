import Foundation
import Observation
import FusionCore
import GaiaFTCLCore
import GaiaFTCLScene

// Starts the full sovereign M⁸ stack inside the app process:
//   1. SwiftNATSServer on port 4222 (pure Swift — no Go binary)
//   2. VQbitVM subprocess (our Swift binary)
//   3. FranklinConsciousnessService subprocess (our Swift binary)
//   4. LocalC4Subscriber — feeds UI overlay from C4 projections
//
// Both child processes use port 4222 for ALL NATS traffic so that
// Franklin's stage.moored message crosses to VQbitVM on the same bus.

@Observable
@MainActor
final class SovereignStackLauncher {

    enum Phase: Equatable {
        case idle
        case launching(String)
        case ready
        case failed(String)
    }

    var phase: Phase = .idle

    private let messageBus = SwiftNATSServer(port: 4222)
    private var vmProcess:       Process?
    private var franklinProcess: Process?
    private var c4Sub:           LocalC4Subscriber?

    func launch(overlay: ManifoldOverlayStore) async {
        guard phase == .idle else { return }

        // ── 1. Swift NATS message bus (replaces external nats-server Go binary) ──
        phase = .launching("Starting sovereign NATS bus…")
        messageBus.start()
        try? await Task.sleep(for: .milliseconds(200))   // let NWListener bind

        // ── 2. VQbitVM ──
        phase = .launching("Starting VQbitVM…")
        guard let vmPath = sovereignBinaryPath("VQbitVM") else {
            phase = .failed("VQbitVM binary not found — run: swift build --product VQbitVM")
            return
        }
        var env = ProcessInfo.processInfo.environment
        env["GAIAFTCL_TENSOR_N"]          = env["GAIAFTCL_TENSOR_N"] ?? "64"
        // Route both vQbit and Franklin traffic through the single Swift NATS bus
        env["GAIAFTCL_VQBIT_NATS_URL"]    = "nats://127.0.0.1:4222"
        env["GAIAFTCL_FRANKLIN_NATS_URL"] = "nats://127.0.0.1:4222"
        vmProcess = spawnProcess(path: vmPath, args: [], env: env)

        // ── 3. FranklinConsciousnessService ──
        phase = .launching("Starting Franklin Consciousness…")
        guard let franklinPath = sovereignBinaryPath("FranklinConsciousnessService") else {
            phase = .failed("FranklinConsciousnessService binary not found")
            return
        }
        franklinProcess = spawnProcess(path: franklinPath, args: [], env: env)

        // ── 4. Wait for vm.ready (max 90 s) ──
        phase = .launching("Waiting for vm.ready…")
        let ready = await waitForVMReady(timeoutSeconds: 90)
        guard ready else {
            phase = .failed("vm.ready not received — check VQbitVM output")
            return
        }

        // ── 5. Start C4 → UI bridge ──
        let sub = LocalC4Subscriber()
        sub.start(overlay: overlay)
        c4Sub = sub
        phase = .ready
    }

    func teardown() {
        vmProcess?.terminate()
        franklinProcess?.terminate()
        messageBus.stop()
    }

    // MARK: - Helpers

    @discardableResult
    private func spawnProcess(path: String, args: [String], env: [String: String]) -> Process {
        let p = Process()
        p.executableURL  = URL(fileURLWithPath: path)
        p.arguments      = args
        p.environment    = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice
        try? p.run()
        return p
    }

    /// Finds our own Swift binaries. Checks:
    ///   1. Same dir as this executable (.build/debug/ when using swift run)
    ///   2. App bundle Contents/Resources/bin/ (DMG install)
    private func sovereignBinaryPath(_ name: String) -> String? {
        if let exe = Bundle.main.executableURL {
            let sibling = exe.deletingLastPathComponent().appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: sibling.path) { return sibling.path }
        }
        let bundled = Bundle.main.bundlePath + "/Contents/Resources/bin/\(name)"
        if FileManager.default.fileExists(atPath: bundled) { return bundled }
        return nil
    }

    /// Subscribes to gaiaftcl.vm.ready on the message bus and waits.
    private func waitForVMReady(timeoutSeconds: Double) async -> Bool {
        let (stream, continuation) = AsyncStream.makeStream(of: Bool.self)

        // Timeout signal
        Task.detached {
            try? await Task.sleep(for: .seconds(timeoutSeconds))
            continuation.finish()
        }

        // NATS listener
        Task.detached {
            let client = NATSClient(host: "127.0.0.1", port: 4222)
            client.connect()
            for await state in client.stateStream {
                if case .connected = state { break }
                if case .failed    = state { continuation.finish(); client.disconnect(); return }
            }
            client.subscribeSync(to: NATSConfiguration.vmReadySubject)
            client.subscribeSync(to: NATSConfiguration.vmHeartbeatSubject)
            for await msg in client.messages {
                if msg.subject == NATSConfiguration.vmReadySubject ||
                   msg.subject == NATSConfiguration.vmHeartbeatSubject {
                    continuation.yield(true)
                    continuation.finish()
                    client.disconnect()
                    return
                }
            }
            continuation.finish()
        }

        for await result in stream { return result }
        return false
    }
}
