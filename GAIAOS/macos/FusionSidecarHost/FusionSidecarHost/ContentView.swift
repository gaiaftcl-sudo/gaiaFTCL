import AppKit
import SwiftUI
import Virtualization
import WebKit

struct ContentView: View {
    @StateObject private var vm = VirtualMachineController()
    @State private var forwarder: TCPPortForwarder?
    @AppStorage("fusionGuestIpv4") private var guestIpv4: String = GuestNetworkDefaults.defaultGuestIpv4
    @AppStorage("fusionKernelPath") private var kernelPath: String = ""
    @AppStorage("fusionInitrdPath") private var initrdPath: String = ""
    @AppStorage("fusionDiskPath") private var diskPath: String = ""
    /// Read-only GAIAOS repo root → guest virtiofs tag `gaiaos` (see fusion_sidecar_guest/README.md).
    @AppStorage("fusionGaiaRootPath") private var gaiaRootPath: String = ""

    @State private var bridgeLog: [String] = []
    @State private var vzSupported: Bool = VZVirtualMachine.isSupported
    @State private var controlSurfaceURL: String = "http://127.0.0.1:8910/fusion-s4"
    @State private var onboardingLastExit: Int32?
    @State private var manifoldPulse = Date()
    @State private var stackLaunchExit: Int32?
    @State private var showAdvanced = false
    @State private var autoBootTriggered = false

    var body: some View {
        ZStack {
            theme.backgroundGradient
                .ignoresSafeArea()
            ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fusion Control Stack Mac Cell App")
                .font(.title2.bold())
                .foregroundStyle(theme.titleGradient)

            Text("Mac Manifold Theme: \(theme.name)")
                .font(.caption)
                .foregroundStyle(.secondary)

            GroupBox("Mac Cell Runtime") {
                HStack {
                    Button("Start Fusion Control Stack") {
                        Task { await startFusionControlStack() }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Run New Operator Walkthrough") {
                        Task { await runPlaywrightOnboarding() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let rc = stackLaunchExit {
                    Text("Stack launch exit: \(rc)")
                        .font(.caption.monospaced())
                        .foregroundStyle(rc == 0 ? .green : .red)
                } else {
                    Text("Auto-booting stack on app launch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("No manual VM/kernel/disk setup required for standard operation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .glassCard()

            DisclosureGroup("Advanced (VM/Bridge controls)", isExpanded: $showAdvanced) {
                if !vzSupported {
                    Text("Virtualization.framework Linux VMs are not supported on this Mac (Apple Silicon + macOS 13+ required).")
                        .foregroundStyle(.red)
                }

                GroupBox("Guest network (VZ NAT)") {
                TextField("Guest IPv4 (for port bridge to :8803)", text: $guestIpv4)
                    .textFieldStyle(.roundedBorder)
                Text(GuestNetworkDefaults.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .glassCard()

                GroupBox("Boot assets (Ubuntu cloud ARM64 — see FUSION_SIDECAR_GUEST_IMAGE.md)") {
                pathRow(title: "Kernel (vmlinuz)", path: $kernelPath)
                pathRow(title: "Initrd", path: $initrdPath)
                pathRow(title: "Root disk (.raw)", path: $diskPath)
                }
                .glassCard()

                GroupBox("Optional: GAIAOS tree (virtiofs read-only, tag gaiaos)") {
                HStack {
                    Text("Repo root").frame(width: 120, alignment: .leading)
                    Text(gaiaRootPath.isEmpty ? "— (optional override)" : gaiaRootPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.caption)
                    Spacer()
                    Button("Choose folder…") { pickGaiaFolder() }
                    if !gaiaRootPath.isEmpty {
                        Button("Clear") { gaiaRootPath = "" }
                    }
                }
                Text("Guest: `sudo mount -t virtiofs gaiaos /opt/gaiaos` — see fusion_sidecar_guest/README.md")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .glassCard()

                HStack {
                Button("Start VM") {
                    Task { await startVm() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!vzSupported || vm.isRunning)

                Button("Stop VM") {
                    Task { await stopAll() }
                }
                .disabled(!vm.isRunning && forwarder == nil)
                }

                HStack {
                Button("Start bridge :8803") {
                    startBridge()
                }
                .buttonStyle(.borderedProminent)
                .disabled(forwarder != nil)

                Button("Stop bridge") {
                    forwarder?.stop()
                    forwarder = nil
                    logBridge("Bridge stopped")
                }
                .disabled(forwarder == nil)
                }

                Text("VM: \(vm.statusLine)")
                if let err = vm.lastError {
                    Text(err).foregroundStyle(.red).font(.caption)
                }

                Text("Verify (host): `curl -sS http://127.0.0.1:8803/health`")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .glassCard()

            GroupBox("Fusion Control Surface (WebKit)") {
                HStack {
                    TextField("Control URL", text: $controlSurfaceURL)
                        .textFieldStyle(.roundedBorder)
                    Button("Reload") {
                        NotificationCenter.default.post(name: .fusionControlSurfaceReload, object: nil)
                    }
                    // DISCORD_DISABLED_FOR_SWIFT_INVARIANT
                    // Button("Push State to Discord") {
                    //     Task { await pushStateToDiscord() }
                    // }
                    // .buttonStyle(.borderedProminent)
                }
                FusionControlSurfaceWebView(urlString: controlSurfaceURL)
                    .frame(minHeight: 560)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text("Live local S4 route witness (must resolve while invariant runs).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .glassCard()

            GroupBox("New User Onboarding (Playwright)") {
                HStack {
                    Button("Run Playwright Walkthrough") {
                        Task { await runPlaywrightOnboarding() }
                    }
                    .buttonStyle(.borderedProminent)
                    if let rc = onboardingLastExit {
                        Text("Last exit: \(rc)")
                            .font(.caption.monospaced())
                            .foregroundStyle(rc == 0 ? .green : .red)
                    } else {
                        Text("No onboarding run yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Runs scripts/run_fusion_new_user_playwright.sh and records witness under evidence/fusion_control/.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .glassCard()

            List(bridgeLog.suffix(40), id: \.self) { line in
                Text(line).font(.system(.caption, design: .monospaced))
            }
            .frame(minHeight: 120)
            .scrollContentBackground(.hidden)
            .glassCard()
        }
        .padding(20)
        .frame(minWidth: 900, minHeight: 900)
        .background(.clear)
        .glassEffectCompat()
        .onReceive(NotificationCenter.default.publisher(for: .fusionStartVM)) { _ in
            Task { await startVm() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fusionStopAll)) { _ in
            Task { await stopAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fusionStartBridge)) { _ in
            startBridge()
        }
        .onReceive(NotificationCenter.default.publisher(for: .fusionStopBridge)) { _ in
            forwarder?.stop()
            forwarder = nil
            logBridge("Bridge stopped")
        }
        .onReceive(NotificationCenter.default.publisher(for: .fusionPushDiscordState)) { _ in
            // DISCORD_DISABLED_FOR_SWIFT_INVARIANT
        }
        .onReceive(NotificationCenter.default.publisher(for: .fusionRunPlaywrightOnboarding)) { _ in
            Task { await runPlaywrightOnboarding() }
        }
        .onAppear {
            // Refresh dynamic manifold tone at launch.
            manifoldPulse = Date()
            if !autoBootTriggered {
                autoBootTriggered = true
                Task { await startFusionControlStack() }
            }
        }
        }
        }
    }

    private func pathRow(title: String, path: Binding<String>) -> some View {
        HStack {
            Text(title).frame(width: 120, alignment: .leading)
            Text(path.wrappedValue.isEmpty ? "—" : path.wrappedValue)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.caption)
            Spacer()
            Button("Choose…") { pickFile(binding: path) }
        }
    }

    private func pickFile(binding: Binding<String>) {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = false
        p.canChooseDirectories = false
        p.canChooseFiles = true
        if p.runModal() == .OK, let url = p.url {
            binding.wrappedValue = url.path
        }
    }

    private func pickGaiaFolder() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = false
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.message = "Select GAIAOS repository root (contains docker-compose.fusion-sidecar.yml)"
        if p.runModal() == .OK, let url = p.url {
            gaiaRootPath = url.path
        }
    }

    private func startVm() async {
        guard !kernelPath.isEmpty, !initrdPath.isEmpty, !diskPath.isEmpty else {
            vm.lastError = "Choose kernel, initrd, and root disk first."
            return
        }
        let k = URL(fileURLWithPath: kernelPath)
        let i = URL(fileURLWithPath: initrdPath)
        let d = URL(fileURLWithPath: diskPath)
        let gaia: URL? = gaiaRootPath.isEmpty ? nil : URL(fileURLWithPath: gaiaRootPath)
        await vm.start(kernelURL: k, initialRamdiskURL: i, rootDiskURL: d, sharedGaiaRootURL: gaia)
    }

    private func stopAll() async {
        forwarder?.stop()
        forwarder = nil
        await vm.stop()
        logBridge("Stopped bridge + VM")
    }

    private func startBridge() {
        forwarder?.stop()
        let f = TCPPortForwarder(
            listenPort: 8803,
            targetHost: guestIpv4.trimmingCharacters(in: .whitespacesAndNewlines),
            targetPort: 8803,
            log: { msg in DispatchQueue.main.async { logBridge(msg) } }
        )
        do {
            try f.start()
            forwarder = f
            logBridge("Bridge 127.0.0.1:8803 → \(guestIpv4):8803")
        } catch {
            logBridge("Bridge REFUSED: \(error.localizedDescription)")
        }
    }

    private func logBridge(_ s: String) {
        bridgeLog.append("[\(ISO8601DateFormatter().string(from: Date()))] \(s)")
    }

    private var theme: FusionManifoldTheme {
        FusionManifoldTheme.make(now: manifoldPulse, vmRunning: vm.isRunning, bridgeRunning: forwarder != nil)
    }

    // DISCORD_DISABLED_FOR_SWIFT_INVARIANT

    private func startFusionControlStack() async {
        let root = (gaiaRootPath.isEmpty ? ProcessInfo.processInfo.environment["GAIA_ROOT"] : gaiaRootPath) ?? ""
        guard !root.isEmpty else {
            logBridge("REFUSED: set GAIA_ROOT or choose repo root before stack launch")
            return
        }
        let script = URL(fileURLWithPath: root).appendingPathComponent("scripts/fusion_stack_launch.sh").path
        guard FileManager.default.fileExists(atPath: script) else {
            logBridge("REFUSED: missing \(script)")
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script, "local"]
        do {
            try p.run()
            p.waitUntilExit()
            stackLaunchExit = p.terminationStatus
            logBridge("Fusion stack launch rc=\(p.terminationStatus)")
        } catch {
            logBridge("Fusion stack launch error: \(error.localizedDescription)")
        }
    }

    private func runPlaywrightOnboarding() async {
        let root = (gaiaRootPath.isEmpty ? ProcessInfo.processInfo.environment["GAIA_ROOT"] : gaiaRootPath) ?? ""
        guard !root.isEmpty else {
            logBridge("REFUSED: set GAIA_ROOT or select repo root before Playwright onboarding")
            return
        }
        let script = URL(fileURLWithPath: root).appendingPathComponent("scripts/run_fusion_new_user_playwright.sh").path
        guard FileManager.default.fileExists(atPath: script) else {
            logBridge("REFUSED: missing \(script)")
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script]
        do {
            try p.run()
            p.waitUntilExit()
            onboardingLastExit = p.terminationStatus
            logBridge("Playwright onboarding rc=\(p.terminationStatus)")
        } catch {
            logBridge("Playwright onboarding error: \(error.localizedDescription)")
        }
    }
}

final class FusionControlNavigationDelegate: NSObject, WKNavigationDelegate {
    let log: (String) -> Void
    init(log: @escaping (String) -> Void) { self.log = log }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        log("WebKit loaded: \(webView.url?.absoluteString ?? "unknown")")
    }
}

struct FusionControlSurfaceWebView: NSViewRepresentable {
    let urlString: String
    func makeCoordinator() -> FusionControlNavigationDelegate {
        FusionControlNavigationDelegate { msg in
            print("[FusionControlSurface] \(msg)")
        }
    }
    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = context.coordinator
        if let u = URL(string: urlString) {
            web.load(URLRequest(url: u))
        }
        NotificationCenter.default.addObserver(forName: .fusionControlSurfaceReload, object: nil, queue: .main) { _ in
            web.reload()
        }
        return web
    }
    func updateNSView(_ webView: WKWebView, context: Context) {
        guard let target = URL(string: urlString) else { return }
        if webView.url?.absoluteString != target.absoluteString {
            webView.load(URLRequest(url: target))
        }
    }
}

extension Notification.Name {
    static let fusionControlSurfaceReload = Notification.Name("fusionControlSurfaceReload")
    static let fusionStartVM = Notification.Name("fusionStartVM")
    static let fusionStopAll = Notification.Name("fusionStopAll")
    static let fusionStartBridge = Notification.Name("fusionStartBridge")
    static let fusionStopBridge = Notification.Name("fusionStopBridge")
    static let fusionPushDiscordState = Notification.Name("fusionPushDiscordState")
    static let fusionRunPlaywrightOnboarding = Notification.Name("fusionRunPlaywrightOnboarding")
}

enum GuestNetworkDefaults {
    /// Configure the guest with this static address on the virtio NIC (cloud-init in guest image doc).
    static let defaultGuestIpv4 = "192.168.64.10"
    static let hint =
        "Set this to the Linux guest’s IP on the VZ NAT (static cloud-init recommended). Default matches deploy/mac_cell_mount/FUSION_SIDECAR_GUEST_IMAGE.md."
}

private struct FusionManifoldTheme {
    let name: String
    let backgroundGradient: LinearGradient
    let titleGradient: LinearGradient

    static func make(now: Date, vmRunning: Bool, bridgeRunning: Bool) -> FusionManifoldTheme {
        let hour = Calendar.current.component(.hour, from: now)
        let brightPhase = hour >= 7 && hour <= 19
        let stateBoost = (vmRunning ? 0.08 : 0.0) + (bridgeRunning ? 0.06 : 0.0)

        let baseBlue = Color(red: 0.56 + stateBoost, green: 0.77 + stateBoost, blue: 0.98)
        let softBlue = brightPhase ? Color(red: 0.84, green: 0.93, blue: 1.00) : Color(red: 0.62, green: 0.77, blue: 0.95)
        let glassEdge = Color.white.opacity(brightPhase ? 0.55 : 0.35)
        return FusionManifoldTheme(
            name: brightPhase ? "Daylight Blue Glass" : "Evening Blue Glass",
            backgroundGradient: LinearGradient(colors: [softBlue, baseBlue.opacity(0.85), glassEdge], startPoint: .topLeading, endPoint: .bottomTrailing),
            titleGradient: LinearGradient(colors: [Color.white, Color(red: 0.68, green: 0.86, blue: 1.0)], startPoint: .leading, endPoint: .trailing)
        )
    }
}

private extension View {
    @ViewBuilder
    func glassEffectCompat() -> some View {
        if #available(macOS 14.0, *) {
            self
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            self
                .padding(8)
                .background(Color.white.opacity(0.20), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    @ViewBuilder
    func glassCard() -> some View {
        if #available(macOS 14.0, *) {
            self
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            self
                .padding(8)
                .background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
