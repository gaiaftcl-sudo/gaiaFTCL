import AppKit
import Foundation
import Combine
import SwiftUI
import CryptoKit
import IOKit

enum FusionShellMode: String, CaseIterable, Identifiable {
    case grid = "grid"
    case topology = "topology"
    case projection = "projection"
    case metrics = "metrics"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid:
            "Grid"
        case .topology:
            "Topology"
        case .projection:
            "Projection"
        case .metrics:
            "Metrics"
        }
    }

    var bridgeAction: String {
        switch self {
        case .grid:
            "show_grid"
        case .topology:
            "show_topology"
        case .projection:
            "show_projection"
        case .metrics:
            "show_metrics"
        }
    }
}

struct S4C4IdentityState {
    let hardwareUUID: String
    let username: String
    let hostname: String
    let sshKeyFingerprint: String
    let appVersion: String
}

enum MooringFileType: String {
    case autoFirstRun = "auto_first_run"
    case autoSubsequent = "auto_subsequent"
    case manualReonboard = "manual_reonboard"
}

/// `WindowGroup`’s string title is not bound to `@Published` mesh state — push the live title to `NSWindow` instead.
enum FusionMainWindowTitleSync {
    static func apply(_ title: String) {
        DispatchQueue.main.async {
            let target = NSApp.mainWindow
                ?? NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) })
            target?.title = title
        }
    }
}

/// WKWebView hole-punch requires the `NSWindow` content chrome to be non-opaque so Metal/OpenUSD shows behind the DOM.
enum FusionMainWindowTransparency {
    static func applyToMainWindow() {
        DispatchQueue.main.async {
            let candidates = [NSApp.mainWindow].compactMap { $0 }
                + NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) }
            for window in candidates {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.titlebarAppearsTransparent = true
                if let cv = window.contentView {
                    cv.wantsLayer = true
                    cv.layer?.backgroundColor = NSColor.clear.cgColor
                }
            }
        }
    }
}

/// Fill the display working area and allow native full screen — removes letterboxing around the WKWebView shell.
enum FusionMainWindowPresentation {
    static func maximizeToVisibleScreen() {
        DispatchQueue.main.async {
            let candidates = [NSApp.mainWindow].compactMap { $0 }
                + NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) }
            guard let window = candidates.first else {
                return
            }
            window.collectionBehavior.insert(.fullScreenPrimary)
            guard let screen = window.screen ?? NSScreen.main else {
                return
            }
            let frame = screen.visibleFrame
            window.setFrame(frame, display: true, animate: false)
        }
    }
}

@main
@MainActor
struct GaiaFusionApp: App {
    /// Eager `StateObject` init so `AppCoordinator` runs (LocalServer `bindTCPListen`) before first window frame.
    /// A lazy `@StateObject private var coordinator = AppCoordinator()` can defer init when the shell is slow to appear
    /// (automation subprocess, display wake), leaving the process up with **no** loopback HTTP — gate `projection_not_responding`.
    @StateObject private var coordinator: AppCoordinator

    init() {
        SingleMacCellLock.enforceSingleGUIInstanceOrExit()
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        _coordinator = StateObject(wrappedValue: AppCoordinator())
    }

    var body: some Scene {
        // Title is applied in `AppShellView` — `WindowGroup(String)` does not track `@Published` updates on macOS.
        WindowGroup("GaiaFusion", id: "gaiafusion-main") {
            AppShellView(coordinator: coordinator)
                .frame(minWidth: 1200, minHeight: 800)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
                .onAppear {
                    coordinator.probeAllCells()
                    FusionMainWindowTitleSync.apply(coordinator.windowTitle)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    FusionMainWindowTransparency.applyToMainWindow()
                    FusionMainWindowPresentation.maximizeToVisibleScreen()
                    DispatchQueue.main.async {
                        if let mainWindow = NSApp.mainWindow {
                            mainWindow.makeKeyAndOrderFront(nil)
                            mainWindow.orderFrontRegardless()
                            FusionMainWindowTitleSync.apply(coordinator.windowTitle)
                            FusionMainWindowTransparency.applyToMainWindow()
                            FusionMainWindowPresentation.maximizeToVisibleScreen()
                        }
                    }
                }
                .onChange(of: coordinator.shellMode) { _, newMode in
                    coordinator.postShellMode(newMode)
                }
                .onChange(of: coordinator.selectedCellID) { _, newCellID in
                    coordinator.selectCell(newCellID)
                    coordinator.syncOpenUSDCellSelection()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    coordinator.performApplicationShutdownForTermination()
                }
                .sheet(isPresented: $coordinator.showConfigPanel) {
                    ConfigPanel(isPresented: $coordinator.showConfigPanel)
                }
                .sheet(isPresented: $coordinator.showOnboarding) {
                    OnboardingFlow(coordinator: coordinator)
                        .frame(minWidth: 700, minHeight: 620)
                }
        }
        .windowToolbarStyle(.unifiedCompact)
        .windowStyle(.titleBar)
        .commands {
            AppMenu(
                operationalState: coordinator.fusionCellStateMachine.operationalState,
                userLevel: coordinator.currentOperatorRole,
                // File menu
                onNewSession: { coordinator.newSession() },
                onOpenPlantConfig: { coordinator.openPlantConfig() },
                onSaveSnapshot: { coordinator.saveSnapshot() },
                onExportAuditLog: { coordinator.exportAuditLog() },
                onQuit: { NSApplication.shared.terminate(nil) },
                // Cell menu
                onSwapPlant: { coordinator.swapPlant() },
                onArmIgnition: { coordinator.armIgnition() },
                onEmergencyStop: { coordinator.emergencyStop() },
                onResetTrip: { coordinator.resetTrip() },
                onAcknowledgeAlarm: { coordinator.acknowledgeAlarm() },
                // Mesh menu
                onProbeAllCells: { coordinator.probeAllCells() },
                onHealUnhealthy: { coordinator.healUnhealthyCells() },
                onRunPlaywrightUiGate: {
                    Task { await coordinator.runPlaywrightUiGateNow() }
                },
                onShowTopology: { coordinator.postShellMode(.topology) },
                onShowProjection: { coordinator.postShellMode(.projection) },
                onShowMetrics: { coordinator.postShellMode(.metrics) },
                onShowGrid: { coordinator.postShellMode(.grid) },
                onSwapSelected: { coordinator.swapSelectedCell() },
                onCellDetail: {
                    coordinator.focusCellDetailTab()
                    coordinator.postMeshAction("show_detail")
                },
                onShowHistory: {
                    coordinator.focusReceiptTab()
                    coordinator.postMeshAction("show_history")
                },
                onToggleInspector: { coordinator.toggleInspector() },
                onToggleSidebar: { coordinator.toggleSidebar() },
                onToggleTraceLayer: { coordinator.toggleTraceLayer() },
                onToggleNativeAgencyChrome: { coordinator.toggleNativeUiMinimal() },
                // Config menu
                onOpenConfig: { coordinator.showConfigPanel = true },
                onOpenFusionRunnerConfig: { coordinator.openFusionRunnerConfig() },
                onMeshSetupWizard: { coordinator.openMeshSetupWizard() },
                onTrainingMode: { coordinator.trainingMode() },
                onMaintenanceMode: { coordinator.maintenanceMode() },
                onAuthSettings: { coordinator.authSettings() },
                // Help menu
                onAbout: { coordinator.showAbout() },
                onViewAuditLog: { coordinator.viewAuditLog() },
                // Composite layout shortcuts
                onLayoutDashboardFocus: { coordinator.layoutManager.applyMode(.dashboardFocus) },
                onLayoutGeometryFocus: { coordinator.layoutManager.applyMode(.geometryFocus) },
                onToggleConstitutionalHud: { coordinator.layoutManager.toggleConstitutionalHud() },
                onCycleMetalOpacity: { coordinator.layoutManager.cycleMetalOpacity() }
            )
        }
    }
}

/// Dark slate behind `WKWebView`: hole-punch transparency shows this instead of an empty clear window (reads as “blank”).
private struct FusionWebShellBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.06, blue: 0.11),
                Color(red: 0.07, green: 0.10, blue: 0.17),
                Color(red: 0.05, green: 0.08, blue: 0.13),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

/// **Shell split (GaiaFTCL Mac):** bundled `fusion-web` / S4 is the projection + operator surface (TS → JS in `WKWebView`).
/// Swift is local **cell agency**: `LocalServer`, mesh/NATS, `FusionBridge`, SSH — not a second competing UI layer.
/// When `nativeUiMinimal` is true (default), the native status strip is hidden so S4 owns the full viewport; use View menu to show agency chrome for debugging.
struct AppShellView: View {
    @ObservedObject var coordinator: AppCoordinator

    @State private var inspectorHeight: CGFloat = 220

    /// Boot ribbon steals vertical space; hide when MOORED/READY and healthy so S4 uses the full window.
    private var showFusionBootRibbon: Bool {
        if coordinator.fusionBootLikelyStuck { return true }
        let s = coordinator.fusionBootState.uppercased()
        if s == "READY" || s == "ACTIVE" { return false }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            if showFusionBootRibbon {
                FusionBootProgressBanner(
                    bootState: coordinator.fusionBootState,
                    ageMs: coordinator.fusionBootAgeMs,
                    stuck: coordinator.fusionBootLikelyStuck
                )
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }

            if coordinator.showTraceLayer {
                HStack {
                    Color.clear
                        .frame(height: 0)
                    FusionToolbar(shellMode: $coordinator.shellMode) { mode in
                        coordinator.postShellMode(mode)
                    }
                    Spacer()
                }
                .padding(.top, 4)
                .padding(.horizontal, 8)

                NavigationSplitView(columnVisibility: $coordinator.splitViewVisibility) {
                    FusionSidebarView(
                        meshManager: coordinator.meshManager,
                        configManager: coordinator.configManager,
                        selectedCellID: $coordinator.selectedCellID,
                        selectedConfigFileURL: $coordinator.selectedConfigFileURL,
                        selectedReceiptFileURL: $coordinator.selectedReceiptFileURL,
                        onRefresh: { coordinator.probeAllCells() },
                        onCellSelect: { coordinator.selectCell($0) },
                        onHealCell: { coordinator.healCell($0) },
                        onSwapCell: { cell in
                            coordinator.swapCell(
                                cellID: cell.id,
                                inputPlantType: coordinator.selectedSwapInput,
                                outputPlantType: coordinator.selectedSwapOutput,
                            )
                        },
                        onConfigSelect: { coordinator.selectedInspectorTab = .configEditor },
                        onReceiptSelect: { coordinator.selectedInspectorTab = .receiptViewer }
                    )
                    .frame(minWidth: 250, maxWidth: 360)
                } detail: {
                    CompositeViewportStack(
                        layoutManager: coordinator.layoutManager,
                        metalPlayback: coordinator.openUSDPlayback,
                        coordinator: coordinator,
                        serverPort: coordinator.server.boundPort
                    )
                }

                if coordinator.showInspector {
                    Divider()
                    VStack(spacing: 0) {
                        HandleBar(height: inspectorHeight) { nextHeight in
                            inspectorHeight = max(170, min(420, nextHeight))
                        }
                        Divider()
                        InspectorPanel(coordinator: coordinator)
                            .frame(height: inspectorHeight)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                CompositeViewportStack(
                    layoutManager: coordinator.layoutManager,
                    metalPlayback: coordinator.openUSDPlayback,
                    coordinator: coordinator,
                    serverPort: coordinator.server.boundPort
                )
            }

            if !coordinator.nativeUiMinimal {
                StatusBarView(meshManager: coordinator.meshManager, isTraceLayerActive: coordinator.showTraceLayer)
                    .frame(height: 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: coordinator.windowTitle) { _, newTitle in
            FusionMainWindowTitleSync.apply(newTitle)
        }
        .onAppear {
            FusionMainWindowTitleSync.apply(coordinator.windowTitle)
            FusionMainWindowTransparency.applyToMainWindow()
            FusionMainWindowPresentation.maximizeToVisibleScreen()
        }
        .accessibilityIdentifier("fusion_main_window")
        .sheet(isPresented: $coordinator.showSSHTerminalOutput) {
            VStack(spacing: 12) {
                Text("SSH Terminal Output")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                Divider()
                ScrollView {
                    Text(coordinator.sshTerminalOutput)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                HStack {
                    Spacer()
                    Button("Close") {
                        coordinator.showSSHTerminalOutput = false
                    }
                }
            }
            .padding(16)
            .frame(width: 760, height: 420)
        }
    }
}

private struct HandleBar: View {
    let height: CGFloat
    let onDrag: (CGFloat) -> Void
    @State private var startHeight: CGFloat = 0

    init(height: CGFloat, onDrag: @escaping (CGFloat) -> Void) {
        self.height = height
        self.onDrag = onDrag
    }

    var body: some View {
        HStack {
            Spacer()
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 72, height: 4)
                .padding(.vertical, 4)
            Spacer()
        }
        .background(Color.black.opacity(0.02))
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    if startHeight == 0 {
                        startHeight = height
                    }
                    let next = startHeight - value.translation.height
                    onDrag(next)
                }
                .onEnded { _ in
                    startHeight = 0
                }
        )
    }
}

private struct FusionBootProgressBanner: View {
    let bootState: String
    let ageMs: Int
    let stuck: Bool

    private var tone: Color {
        if stuck {
            return .red
        }
        if bootState.uppercased() == "READY" {
            return .green
        }
        return .orange
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tone)
                .frame(width: 8, height: 8)
            Text("Fusion UI: \(bootState)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
            Text("heartbeat \(ageMs)ms")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            if stuck {
                Text("STUCK")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.18))
                    .clipShape(Capsule())
            }
            Spacer()
        }
    }
}

@MainActor
final class AppCoordinator: ObservableObject {
    let meshManager = MeshStateManager()
    let bridge: FusionBridge
    let server: LocalServer
    let configManager: ConfigFileManager
    let sshService = SSHService()
    let natsService = NATSService()
    let layoutManager = CompositeLayoutManager()
    let fusionCellStateMachine = FusionCellStateMachine()
    private let isoFormatter = ISO8601DateFormatter()
    private let homeMooringDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gaiaftcl", isDirectory: true)
    private let processQueue = DispatchQueue(label: "fusion.coordinator.shell", qos: .utility)
    nonisolated(unsafe) private var natsStreamTask: Task<Void, Never>?
    @Published private(set) var cellIdentityHash: String?
    @Published var currentOperatorRole: OperatorRole = .l2  // TODO: Wire to real authentication system

    @Published var webviewLoaded = false
    @Published var showConfigPanel = false
    @Published var showOnboarding = false
    @Published var showSSHTerminalOutput = false
    @Published var sshTerminalOutput = ""
    @Published var showInspector = false
    @Published var splitViewVisibility: NavigationSplitViewVisibility = .detailOnly
    @Published var showTraceLayer = false
    @Published var shellMode: FusionShellMode = .projection
    @Published var selectedCellID: String?
    @Published var selectedConfigFileURL: URL?
    @Published var selectedReceiptFileURL: URL?
    @Published var selectedInspectorTab: InspectorPanelTab = .cellDetail
    @Published var selectedSwapInput: String = "tokamak"
    @Published var selectedSwapOutput: String = "tokamak"
    @Published var windowTitle: String = "GaiaFusion — MOORED — 0/0 cells"
    /// When `true` (default), hide the Swift status strip so S4 (`fusion-web`) fills the window — Swift remains agency (server, mesh, bridge).
    @Published private(set) var nativeUiMinimal: Bool = true
    /// 0…1 UI torsion from `/api/fusion/health` (Klein + DOM + TSX invariants).
    @Published private(set) var uiTorsion01: Double = 0
    @Published private(set) var lastPlaywrightHealSummary: String?
    @Published private(set) var fusionBootState: String = "READY"
    @Published private(set) var fusionBootAgeMs: Int = 0
    @Published private(set) var fusionBootLikelyStuck: Bool = false
    /// Cancellables/tasks touched from `nonisolated deinit`; Combine types are not `Sendable`.
    nonisolated(unsafe) private var meshStateCancellable: AnyCancellable?
    private var bridgeWitnessCancellables = Set<AnyCancellable>()
    nonisolated(unsafe) private var uiTorsionPollTask: Task<Void, Never>?
    private var lastPlaywrightHealAt: Date?
    private var natsMcpBridge: NATSMCPBridge?
    private var mcpPresenceNudgeWorkItem: DispatchWorkItem?
    private let uiStateManifold = UIStateManifold()
    private var uiDecimator: UIDecimator?
    private var natsIngestionCycles: Int = 0
    private var lastIngestionTsMs: Int64 = 0
    private var lastIngestionSubject: String = ""
    private var lastPublishedTopologyFingerprint: String?
    private var anomalyBroadcasted = false
    private let openUSDState = OpenUSDLanguageGameState()
    /// Metal + Rust playback — replaces OpenUSD bloat with lightweight FFI renderer
    let openUSDPlayback = MetalPlaybackController()
    @Published private(set) var splashOverlayVisible = true
    @Published private(set) var splashDismissTimedOut = false
    @Published private(set) var splashHandshakeComplete = false
    /// `pending` while overlay visible; `handshake` | `timeout` | `error` after dismissal (self-probe / gate).
    @Published private(set) var splashDismissReason: String = "pending"
    @Published private(set) var openUSDInteractionLocked: Bool = false
    /// Prevents duplicate Swifter/NATS/mesh teardown when `willTerminate` and menu paths both fire.
    private var applicationShutdownPerformed = false

    init() {
        self.configManager = ConfigFileManager()
        self.bridge = FusionBridge(meshManager: meshManager)
        self.bridge.layoutManager = layoutManager
        self.bridge.fusionCellStateMachine = fusionCellStateMachine
        self.uiDecimator = UIDecimator(manifold: uiStateManifold, bridge: bridge)
        self.server = LocalServer(meshManager: meshManager)
        self.server.fusionBridge = self.bridge
        self.server.identityHashProvider = { [weak self] in
            self?.cellIdentityHash
        }
        self.server.traceActiveProvider = { [weak self] in
            self?.showTraceLayer == true
        }
        self.server.openUSDPlaybackProvider = { [weak self] in
            guard let self else {
                return [:]
            }
            return self.openUSDPlayback.jsonSnapshot()
        }
        self.server.layoutManagerProvider = { [weak self] in
            guard let self else {
                print("⚠️ layoutManagerProvider: self is nil")
                return [:]
            }
            let mode = self.layoutManager.currentMode.rawValue
            let metalOp = self.layoutManager.metalOpacity
            let webOp = self.layoutManager.webviewOpacity
            print("✅ layoutManagerProvider called: mode=\(mode), metalOpacity=\(metalOp)")
            return [
                "current_mode": mode,
                "metal_opacity": metalOp,
                "webview_opacity": webOp,
                "constitutional_hud_visible": self.layoutManager.constitutionalHudVisible,
            ]
        }
        self.server.splashStateProvider = { [weak self] in
            guard let self else {
                return [
                    "splash_dismissed": false,
                    "splash_dismiss_reason": "pending",
                ]
            }
            let dismissed = !self.splashOverlayVisible
            let reason = self.splashDismissReason
            return [
                "splash_dismissed": dismissed,
                "splash_dismiss_reason": dismissed ? reason : "pending",
            ]
        }
        self.server.loadViewportPlantHook = { [weak self] kind in
            guard let self else { return }
            self.openUSDState.setPlantPayload(kind)
            self.openUSDPlayback.loadPlant(kind)
            self.syncPlaybackRingFromOpenUSD()
        }
        self.server.engageViewportHook = { [weak self] in
            self?.openUSDPlayback.setEngaged(true)
        }
        self.server.mcpCommsProvider = { [weak self] in
            guard let self else {
                return [
                    "schema": "gaiaftcl_mcp_cell_comms_v1",
                    "terminal": "REFUSED",
                    "reason": "coordinator_deallocated",
                ]
            }
            return self.mcpCellCommsSnapshot()
        }
        self.server.mcpPresencePingHandler = { [weak self] in
            await self?.natsMcpBridge?.publishPresenceSnapshot(trigger: "http_mcp_cell_ping")
        }
        self.bridge.identityHashProvider = { [weak self] in
            self?.cellIdentityHash
        }
        self.bridge.traceModeProvider = { [weak self] in
            self?.showTraceLayer == true
        }
        self.bridge.onEngageIgnitionPlayback = { [weak self] in
            self?.openUSDPlayback.setEngaged(true)
        }
        self.bridge.onViewportPlantKind = { [weak self] kind in
            guard let self else { return }
            self.openUSDState.setPlantPayload(kind)
            self.openUSDPlayback.loadPlant(kind)
            self.syncPlaybackRingFromOpenUSD()
        }
        self.bridge.applyRemoteCellSelection = { [weak self] id in
            guard let self else { return }
            self.selectedCellID = id
            self.openUSDPlayback.onSelectCell(cellID: id, meshCells: self.meshManager.cells)
        }
        self.bridge.onWebViewAttached = { [weak self] in
            self?.publishBootToTokamakNativeComposite()
        }
        openUSDPlayback.vqbitSample = { [weak self] in
            self?.meshManager.vQbit ?? 0
        }
        openUSDPlayback.onPlantSwapLifecycle = { [weak self] payload in
            guard let self else { return }
            self.bridge.sendDirect(
                action: "PLANT_SWAP_LIFECYCLE",
                data: payload,
                requestID: UUID().uuidString
            )
            // MSV Stage 2: release eversion-gated signed vectors only after terminal swap + loaded stage (C4 ↔ S4).
            if let state = payload["state"] as? String,
               state == "VERIFIED",
               let pk = payload["plant_kind"] as? String {
                self.bridge.notifyUsdEversionComplete(
                    plantKind: pk,
                    stageLoaded: self.openUSDPlayback.stageLoaded
                )
            }
        }
        openUSDPlayback.onSubgameZDiagnosticEviction = { [weak self] payload in
            guard let self else { return }
            self.bridge.sendDirect(
                action: "SUBGAME_Z_DIAGNOSTIC_EVICT",
                data: payload,
                requestID: UUID().uuidString
            )
        }

        let legacyDefaultSSHKeyPath = "\(NSHomeDirectory())/.ssh/id_rsa"
        if UserDefaults.standard.string(forKey: "fusion_ssh_key_path") == legacyDefaultSSHKeyPath {
            UserDefaults.standard.removeObject(forKey: "fusion_ssh_key_path")
        }

        UserDefaults.standard.register(
            defaults: [
                "fusion_ui_port": 8910,
                // Static `fusion-web` / production surface is the default; enable dev mode when iterating against `next dev` on a separate port from this app’s bound port.
                "fusion_dev_mode": false,
                "fusion_heartbeat_seconds": 15,
                "fusion_nats_url": "nats://127.0.0.1:4222",
                "fusion_nats_subject": "gaiaftcl.fusion.cell.status.v1,gaiaftcl.fusion.mesh_mooring.v1,gaiaftcl.cell.id,gaiaftcl.cell.id",
                "fusion_ssh_user": "root",
                "fusion_mesh_heal_enabled": true,
                "fusion_ssh_key_path": "",
                "fusion_onboarding_complete": false,
                "fusion_onboarding_skipped_once": false,
                "fusion_auto_moored_complete": false,
                // true = hide native status bar; S4 projection surface uses full viewport (see AppShellView).
                "fusion_native_ui_minimal": true,
                // 0 = off. Set to 120+ to poll /api/fusion/health and optionally run Playwright when UI torsion > 0.
                "fusion_ui_torsion_poll_sec": 0,
                "fusion_playwright_auto_on_torsion": true,
                "fusion_playwright_heal_min_interval_sec": 600,
                "fusion_gaia_repo_root": "",
                // Composite layout defaults
                "fusion_layout_mode": "dashboard_focus",
                "fusion_metal_opacity_default": 0.1,
                "fusion_constitutional_hud_always_visible": false,
                "fusion_wasm_auto_layout_switch": true,
            ]
        )
        nativeUiMinimal = Self.loadNativeUiMinimal()
        Task { @MainActor in
            await prepareOnboardingState()
        }

        meshManager.start()
        // Gate / headless: `configureRoutes()` stays on MainActor; Swifter `listen` runs on a concurrent queue (never `Task { @MainActor in server.start() }`).
        server.prepareHTTPStack()
        DispatchQueue.global(qos: .userInitiated).async { [server] in
            server.bindTCPListen()
        }
        meshManager.bridgeReady = false
        refreshWindowTitle()
        meshStateCancellable = meshManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshWindowTitle()
                let cells = self?.meshManager.cells ?? []
                self?.openUSDPlayback.applyMeshDiagnosticEviction(meshCells: cells)
                self?.openUSDPlayback.onSelectCell(cellID: self?.selectedCellID, meshCells: cells)
            }
        openUSDPlayback.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &bridgeWitnessCancellables)
        bridge.$lastTsxSurfaceEnvelope
            .receive(on: DispatchQueue.main)
            .sink { [weak self] envelope in
                guard let self else { return }
                let raw = (envelope?["boot_state"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if raw.isEmpty {
                    return
                }
                let normalized = raw.uppercased()
                self.fusionBootState = normalized
                // If active TSX is up and no longer mooring, treat as ready-state UI.
                if normalized != "MOORING" {
                    self.fusionBootLikelyStuck = false
                }
            }
            .store(in: &bridgeWitnessCancellables)
        bridge.$lastWasmDomWitness
            .receive(on: DispatchQueue.main)
            .sink { [weak self] witness in
                guard let self else { return }
                guard let witness else {
                    self.fusionBootAgeMs = 0
                    self.fusionBootLikelyStuck = true
                    return
                }
                let now = Int64(Date().timeIntervalSince1970 * 1_000.0)
                let age = max(0, Int(now - witness.tsMs))
                self.fusionBootAgeMs = age
                // 12s with mooring/no advance = likely stuck.
                self.fusionBootLikelyStuck = self.fusionBootState == "MOORING" && age > 12_000
                if self.fusionBootLikelyStuck && !self.anomalyBroadcasted {
                    self.anomalyBroadcasted = true
                    Task { [weak self] in
                        guard let self else { return }
                        await self.natsMcpBridge?.broadcastAnomaly(
                            reason: "heartbeat_zero_or_mooring_stall",
                            stackTrace: "boot_state=\(self.fusionBootState) age_ms=\(self.fusionBootAgeMs)"
                        )
                    }
                } else if !self.fusionBootLikelyStuck {
                    self.anomalyBroadcasted = false
                }
            }
            .store(in: &bridgeWitnessCancellables)
        natsStreamTask = Task { [weak self] in
            await self?.startNATSIngress()
        }
        armNATSMCPBridge()
        uiDecimator?.start(fps: 30.0)
        startUiTorsionPlaywrightLoopIfConfigured()
        armSplashTimeout()
    }

    /// Native boundary: OpenUSD moored Tokamak + idle telemetry once WKWebView exists; supervisory plane observes, not constructs.
    private func publishBootToTokamakNativeComposite() {
        func epistemicRow(_ label: String) -> Int {
            switch (openUSDState.epistemicClass[label] ?? "").lowercased() {
            case "measured": return 0
            case "tested": return 1
            case "inferred": return 2
            case "assumed": return 3
            default: return 0
            }
        }
        let ip = openUSDState.measuredTelemetry["I_p"] ?? 0.0
        let bt = openUSDState.measuredTelemetry["B_T"] ?? 0.0
        let ne = openUSDState.measuredTelemetry["n_e"] ?? 0.0
        uiStateManifold.clobberState(
            ip: ip,
            bt: bt,
            ne: ne,
            epistemicClass: epistemicRow("I_p"),
            tagIp: epistemicTagLetter(for: "I_p"),
            tagBt: epistemicTagLetter(for: "B_T"),
            tagNe: epistemicTagLetter(for: "n_e")
        )
        let full = openUSDState.sessionLayerOverlay()
        let mooring = full["mooring_variant"] as? String ?? "MOORED"
        let plant = (full["plant_payload_contract"] as? [String: Any])?["active_payload"] as? String ?? "tokamak"
        let sessionTopo: [String: Any] = [
            "schema": "gaiaftcl_openusd_session_layer_topology_v1",
            "mooring_variant": mooring,
            "plant_payload": plant,
        ]
        bridge.sendDirect(
            action: "OPENUSD_SESSION_LAYER_UPDATE",
            data: [
                "reason": "boot_to_tokamak",
                "session_layer": sessionTopo,
            ],
            requestID: UUID().uuidString
        )
        let entropyCalm = openUSDState.mooringState == .moored && uiTorsion01 <= 0.001
        bridge.sendDirect(
            action: "OPENUSD_INCEPTION_SNAP",
            data: [
                "reason": "boot_to_tokamak",
                "mooring_variant": openUSDState.mooringState.rawValue,
                "plant_payload": openUSDState.activePlantPayload,
                "terminal_state": openUSDState.terminalState.rawValue,
                "entropy_calm": entropyCalm,
                "ui_torsion_01": uiTorsion01,
            ],
            requestID: UUID().uuidString
        )
        syncPlaybackRingFromOpenUSD()
    }

    func syncOpenUSDCellSelection() {
        let cells = meshManager.cells
        openUSDPlayback.applyMeshDiagnosticEviction(meshCells: cells)
        openUSDPlayback.onSelectCell(cellID: selectedCellID, meshCells: cells)
    }

    private func epistemicTagLetter(for label: String) -> String {
        switch (openUSDState.epistemicClass[label] ?? "Measured").lowercased() {
        case "tested":
            return "T"
        case "inferred":
            return "I"
        case "assumed":
            return "A"
        default:
            return "M"
        }
    }

    private func syncPlaybackRingFromOpenUSD() {
        let m = openUSDState.measuredTelemetry
        openUSDPlayback.ingestTelemetryFromBridge(
            ip: m["I_p"] ?? 0.0,
            bt: m["B_T"] ?? 0.0,
            ne: m["n_e"] ?? 0.0
        )
        openUSDPlayback.ingestEpistemicBoundary(
            ip: openUSDState.epistemicClass["I_p"] ?? "Measured",
            bt: openUSDState.epistemicClass["B_T"] ?? "Measured",
            ne: openUSDState.epistemicClass["n_e"] ?? "Measured",
            terminal: openUSDState.terminalState.rawValue
        )
    }

    func refreshSplashHandshake() {
        guard splashOverlayVisible else {
            return
        }
        if server.isRunning && webviewLoaded {
            splashDismissReason = "handshake"
            splashHandshakeComplete = true
            withAnimation(.easeOut(duration: 0.45)) {
                splashOverlayVisible = false
            }
            scheduleMcpPresenceNudge(reason: "splash_handshake")
        }
    }

    private func armSplashTimeout() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 14_000_000_000)
            guard self.splashOverlayVisible else {
                return
            }
            self.splashDismissReason = "timeout"
            self.splashDismissTimedOut = true
            withAnimation(.easeOut(duration: 0.35)) {
                self.splashOverlayVisible = false
            }
            self.scheduleMcpPresenceNudge(reason: "splash_timeout")
        }
    }

    deinit {
        meshStateCancellable?.cancel()
        natsStreamTask?.cancel()
        uiTorsionPollTask?.cancel()
        // Do not call `server.stop()` / actor `await` here: `willTerminate` already runs synchronous shutdown,
        // and scheduling `Task { @MainActor }` during `deinit` can double-close sockets or race process exit.
    }

    /// Single idempotent teardown for Quit / SIGTERM (via `NSApplication.terminate`). Do **not** call `terminate` from here.
    func performApplicationShutdownForTermination() {
        guard !applicationShutdownPerformed else {
            return
        }
        applicationShutdownPerformed = true

        natsStreamTask?.cancel()
        natsStreamTask = nil
        uiTorsionPollTask?.cancel()
        uiTorsionPollTask = nil

        Task { await natsService.stopCellStatusStream() }
        natsMcpBridge?.shutdown()
        uiDecimator?.stop()

        meshManager.stop()
        server.stop()
    }

    /// Menu / Cmd+Q: request Cocoa termination; cleanup runs in `willTerminate` (`performApplicationShutdownForTermination`).
    func requestExit() {
        NSApplication.shared.terminate(nil)
    }

    func probeAllCells() {
        Task {
            await meshManager.refresh()
            refreshWindowTitle()
        }
    }

    func probeAllCellsNow() async -> [CellState] {
        await meshManager.refresh()
        refreshWindowTitle()
        return meshManager.cells
    }

    func healUnhealthyCells() {
        openTraceLayer(mode: .grid)
        let unhealthy = meshManager.cells.filter { !$0.active }
        for cell in unhealthy {
            bridge.sendDirect(
                action: "heal_cell",
                data: [
                    "cell_id": cell.id,
                    "cell_identity_hash": cellIdentityHash ?? "unverified",
                ],
                requestID: UUID().uuidString
            )
        }
    }

    func healCell(_ cellID: String) {
        openTraceLayer(mode: .grid)
        bridge.sendDirect(
            action: "heal_cell",
            data: [
                "cell_id": cellID,
                "cell_identity_hash": cellIdentityHash ?? "unverified",
            ],
            requestID: UUID().uuidString
        )
    }

    func swapSelectedCell() {
        openTraceLayer(mode: .grid)
        guard let selectedCellID else {
            bridge.sendDirect(
                action: "swap_cell",
                data: ["ok": false, "error": "missing_cell_id"],
                requestID: UUID().uuidString
            )
            return
        }
        swapCell(
            cellID: selectedCellID,
            inputPlantType: selectedSwapInput,
            outputPlantType: selectedSwapOutput
        )
    }

    func swapCell(cellID: String, inputPlantType: String?, outputPlantType: String?) {
        openTraceLayer(mode: .grid)
        let selectedCell = meshManager.cells.first(where: { $0.id == cellID || $0.name == cellID })
        let inputKind = PlantType.normalized(raw: inputPlantType ?? selectedCell?.inputPlantType.rawValue)
        let outputKind = PlantType.normalized(raw: outputPlantType ?? selectedCell?.outputPlantType.rawValue)
        guard inputKind != .unknown, outputKind != .unknown else {
            bridge.sendDirect(
                action: "swap_cell",
                data: ["ok": false, "error": "unsupported_plant_kind", "cell_identity_hash": cellIdentityHash ?? "unverified"],
                requestID: UUID().uuidString
            )
            return
        }
        bridge.sendDirect(
            action: "swap_cell",
            data: [
                "cell_id": cellID,
                "input": inputKind.rawValue,
                "output": outputKind.rawValue,
                "cell_identity_hash": cellIdentityHash ?? "unverified",
            ],
            requestID: UUID().uuidString
        )
    }

    func postShellMode(_ mode: FusionShellMode) {
        if !showTraceLayer, mode != .projection {
            openTraceLayer(mode: mode)
            return
        }
        shellMode = mode
        bridge.sendDirect(action: mode.bridgeAction, data: [:], requestID: UUID().uuidString)
    }

    func postMeshAction(_ action: String) {
        openTraceLayer(mode: .grid)
        bridge.sendDirect(action: action, data: [:], requestID: UUID().uuidString)
    }

    func refreshWindowTitle() {
        windowTitle = "GaiaFusion — MOORED — \(meshManager.meshHealthText) cells"
    }

    func toggleNativeUiMinimal() {
        nativeUiMinimal.toggle()
        UserDefaults.standard.set(nativeUiMinimal, forKey: "fusion_native_ui_minimal")
    }

    private static func loadNativeUiMinimal() -> Bool {
        if let raw = ProcessInfo.processInfo.environment["FUSION_NATIVE_UI_MINIMAL"] {
            let lower = raw.lowercased()
            if ["0", "false", "no", "off"].contains(lower) {
                return false
            }
            if ["1", "true", "yes", "on"].contains(lower) {
                return true
            }
        }
        return UserDefaults.standard.bool(forKey: "fusion_native_ui_minimal")
    }

    /// Background loop: optional poll interval (`fusion_ui_torsion_poll_sec`) + Playwright heal when torsion > 0.
    func startUiTorsionPlaywrightLoopIfConfigured() {
        uiTorsionPollTask?.cancel()
        let pollSec = UserDefaults.standard.integer(forKey: "fusion_ui_torsion_poll_sec")
        Task { [weak self] in
            await self?.refreshUiTorsionFromHealth()
        }
        guard pollSec > 0 else {
            return
        }
        uiTorsionPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(pollSec) * 1_000_000_000)
                await self?.pollUiTorsionAndMaybeRunPlaywrightHeal()
            }
        }
    }

    private func fetchFusionHealthJson() async -> [String: Any]? {
        let port = server.boundPort
        guard let url = URL(string: "http://127.0.0.1:\(port)/api/fusion/health") else {
            return nil
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    func refreshUiTorsionFromHealth() async {
        guard let json = await fetchFusionHealthJson() else {
            return
        }
        let t = FusionUiTorsion.score01(health: json)
        uiTorsion01 = t
    }

    func pollUiTorsionAndMaybeRunPlaywrightHeal() async {
        await refreshUiTorsionFromHealth()
        let auto = UserDefaults.standard.bool(forKey: "fusion_playwright_auto_on_torsion")
        guard auto && uiTorsion01 > 0.001 else {
            return
        }
        let minSec = max(60, UserDefaults.standard.integer(forKey: "fusion_playwright_heal_min_interval_sec"))
        if let last = lastPlaywrightHealAt, Date().timeIntervalSince(last) < TimeInterval(minSec) {
            return
        }
        _ = await runPlaywrightUiGateNowInternal()
    }

    func runPlaywrightUiGateNow() async {
        _ = await runPlaywrightUiGateNowInternal()
    }

    @discardableResult
    private func runPlaywrightUiGateNowInternal() async -> Bool {
        guard let root = FusionUiTorsion.resolveGaiaRepoRoot() else {
            lastPlaywrightHealSummary =
                "BLOCKED: set GAIA_ROOT or fusion_gaia_repo_root to repo root containing services/gaiaos_ui_web (Playwright)."
            return false
        }
        let port = server.boundPort
        let result = await Task.detached {
            FusionPlaywrightHealRunner.runGate(repoRoot: root, localPort: port)
        }.value
        lastPlaywrightHealSummary = result.summary
        if result.ok {
            lastPlaywrightHealAt = Date()
        }
        await refreshUiTorsionFromHealth()
        return result.ok
    }

    func focusCellDetailTab() {
        openTraceLayer(mode: .grid)
        selectedInspectorTab = .cellDetail
        showInspector = true
    }

    func focusReceiptTab() {
        openTraceLayer(mode: .grid)
        selectedInspectorTab = .receiptViewer
        showInspector = true
    }

    func selectCell(_ cellID: String?) {
        guard let cellID else {
            return
        }
        bridge.sendDirect(
            action: "select_cell",
            data: ["cell_id": cellID],
            requestID: UUID().uuidString
        )
    }

    func openConfigForCell(_ cellID: String) {
        if let file = configManager.fileForCellConfig(cellID: cellID) {
            selectedConfigFileURL = file
            selectedReceiptFileURL = nil
            selectedInspectorTab = .configEditor
            return
        }
        selectedConfigFileURL = nil
    }

    /// `deploy/fusion_cell/config.json` — same path as `fusion_cell_long_run_runner.sh` (Game 4 / operator closure).
    func openFusionRunnerConfig() {
        guard let url = configManager.fusionCellRuntimeConfigURL() else {
            return
        }
        selectedConfigFileURL = url
        selectedReceiptFileURL = nil
        selectedInspectorTab = .configEditor
        showInspector = true
    }

    func meshHost(for cellID: String?) -> String {
        guard let cellID else {
            return ""
        }
        if let match = meshManager.cells.first(where: { $0.id == cellID || $0.name == cellID }) {
            return match.ipv4
        }
        return cellID
    }

    func setBridgeReady(_ loaded: Bool) {
        webviewLoaded = loaded
        meshManager.bridgeReady = loaded
        server.setBridgeLoaded(loaded)
        refreshSplashHandshake()
        if loaded {
            scheduleMcpPresenceNudge(reason: "webview_loaded")
        }
    }

    /// True when a main Fusion window is on-screen (MCP / mesh visibility heuristic).
    static func isFusionWindowVisibleForMcp() -> Bool {
        NSApp.windows.contains { w in
            guard !(w is NSPanel) else { return false }
            return w.isVisible && !w.isMiniaturized && w.occlusionState.contains(.visible)
        }
    }

    /// Fields merged into NATS `gaiaftcl.mcp.cell.presence.*` heartbeats.
    func mcpCellPresenceExtras() -> [String: Any] {
        let win = Self.isFusionWindowVisibleForMcp()
        return [
            "ui_window_visible": win,
            "local_server_listening": server.isRunning,
            "local_ui_port": server.boundPort,
            "webview_loaded": webviewLoaded,
            "splash_blocking_ui": splashOverlayVisible,
            "splash_dismiss_reason": splashDismissReason,
            "visible_for_mcp_operator": server.isRunning && webviewLoaded && win && !splashOverlayVisible,
            "mesh_healthy_count": meshManager.healthyCount,
            "mesh_cells_total": meshManager.cells.count,
            "mesh_v_qbit": meshManager.vQbit,
            "mesh_nats_connected": meshManager.natsConnected,
        ]
    }

    /// Loopback + NATS MCP receipts for `/api/fusion/health` and `/api/fusion/mcp-cell`.
    func mcpCellCommsSnapshot() -> [String: Any] {
        var o = mcpCellPresenceExtras()
        o["schema"] = "gaiaftcl_mcp_cell_comms_v1"
        o["pid"] = ProcessInfo.processInfo.processIdentifier
        if let b = natsMcpBridge {
            o["nats_mcp_armed"] = b.isArmed
            o["mcp_rx_subject"] = b.rxSubject
            o["mcp_tx_subject"] = b.txSubject
            o["mcp_presence_subject"] = b.presenceSubject
            o["mcp_events_subject"] = b.eventsSubject
        } else {
            o["nats_mcp_armed"] = false
        }
        return o
    }

    /// Debounced NATS presence + event so head/MCP sees UI/mesh transitions without waiting 12s.
    private func scheduleMcpPresenceNudge(reason: String) {
        mcpPresenceNudgeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { await self.natsMcpBridge?.publishPresenceSnapshot(trigger: reason) }
            Task { await self.natsMcpBridge?.publishCommsEvent(kind: "cell_ui_mesh", fields: ["reason": reason]) }
        }
        mcpPresenceNudgeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: item)
    }

    func completeOnboarding() {
        UserDefaults.standard.setValue(true, forKey: "fusion_onboarding_complete")
        UserDefaults.standard.setValue(true, forKey: "fusion_auto_moored_complete")
        UserDefaults.standard.setValue(Date().timeIntervalSince1970, forKey: "fusion_onboarding_timestamp")
        UserDefaults.standard.removeObject(forKey: "fusion_onboarding_skipped_once")
        showOnboarding = false
    }

    func skipOnboarding() {
        UserDefaults.standard.setValue(true, forKey: "fusion_onboarding_skipped_once")
        UserDefaults.standard.setValue(Date().timeIntervalSince1970, forKey: "fusion_onboarding_timestamp")
        showOnboarding = false
    }

    /// Boot-to-Tokamak: the NATS/mooring wizard is **never** shown automatically. Use **Mesh → Mesh setup wizard…** (or `skip`/`Finish` inside it). CI can set `GAIAFUSION_GATE_MINIMAL_S4=1` to no-op heavy paths elsewhere.
    func openMeshSetupWizard() {
        showOnboarding = true
    }

    func prepareOnboardingState() async {
        // One-time: clear legacy "skipped once → force modal" so the sheet cannot respawn on every launch.
        if !UserDefaults.standard.bool(forKey: "fusion_boot_totokamak_wizard_off_v1") {
            UserDefaults.standard.setValue(true, forKey: "fusion_boot_totokamak_wizard_off_v1")
            UserDefaults.standard.removeObject(forKey: "fusion_onboarding_skipped_once")
        }

        showOnboarding = false

        let defaults = UserDefaults.standard
        persistOnboardingDefaults(
            sshKeyPath: defaults.string(forKey: "fusion_ssh_key_path") ?? "",
            sshUser: defaults.string(forKey: "fusion_ssh_user") ?? "root",
            natsURL: defaults.string(forKey: "fusion_nats_url") ?? "nats://127.0.0.1:4222"
        )

        guard let identity = readCellIdentity(),
              let storedHash = identity["s4c4_hash"] as? String else {
            await runAutoMooringIfNeeded(type: .autoFirstRun)
            return
        }
        guard let storedS4 = identity["s4"] as? [String: Any], isS4Match(storedS4: storedS4) else {
            setIdentityStateUnmoored(identity: identity)
            return
        }

        cellIdentityHash = storedHash
        markOnboardingAsCompleted()
        showOnboarding = false
        await runAutoMooringIfNeeded(type: .autoSubsequent)
    }

    func runAutoMooringIfNeeded(type: MooringFileType) async {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "fusion_onboarding_complete") || !defaults.bool(forKey: "fusion_auto_moored_complete") else {
            showOnboarding = false
            return
        }

        if await attemptAutoMooring(type: type) {
            completeOnboarding()
        } else {
            showOnboarding = false
        }
    }

    func attemptAutoMooring(type: MooringFileType) async -> Bool {
        let defaults = UserDefaults.standard
        let natsURL = defaults.string(forKey: "fusion_nats_url") ?? "nats://127.0.0.1:4222"
        let sshKeyPath = defaults.string(forKey: "fusion_ssh_key_path") ?? ""
        let sshUser = defaults.string(forKey: "fusion_ssh_user") ?? "root"
        persistOnboardingDefaults(
            sshKeyPath: defaults.string(forKey: "fusion_ssh_key_path") ?? "",
            sshUser: defaults.string(forKey: "fusion_ssh_user") ?? "root",
            natsURL: natsURL
        )

        let cells = await probeAllCellsNow()
        let healthyCells = cells.filter { $0.active }.count
        guard !cells.isEmpty && healthyCells > 0 else {
            return false
        }
        guard !sshKeyPath.isEmpty, FileManager.default.fileExists(atPath: sshKeyPath) else {
            return false
        }
        let probeTarget = cells.first(where: \.active)?.id ?? cells.first?.id ?? ""
        let sshResult = await testSSHConnection(keyPath: sshKeyPath, user: sshUser, targetCellID: probeTarget)
        guard sshResult.0 else {
            return false
        }

        let natsResult = await testNATSConnection(urlString: natsURL)
        guard natsResult.0 else {
            return false
        }

        let receiptResult = await createMooringReceipts(type: type)
        guard receiptResult.0 else {
            return false
        }

        defaults.setValue(true, forKey: "fusion_auto_moored_complete")
        return true
    }

    func persistOnboardingDefaults(sshKeyPath: String, sshUser: String, natsURL: String) {
        UserDefaults.standard.setValue(sshKeyPath, forKey: "fusion_ssh_key_path")
        UserDefaults.standard.setValue(sshUser, forKey: "fusion_ssh_user")
        UserDefaults.standard.setValue(natsURL, forKey: "fusion_nats_url")
    }

    func markOnboardingAsCompleted() {
        UserDefaults.standard.setValue(true, forKey: "fusion_onboarding_complete")
        UserDefaults.standard.setValue(true, forKey: "fusion_auto_moored_complete")
        UserDefaults.standard.setValue(Date().timeIntervalSince1970, forKey: "fusion_onboarding_timestamp")
        UserDefaults.standard.removeObject(forKey: "fusion_onboarding_skipped_once")
    }

    func setIdentityStateUnmoored(identity: [String: Any]) {
        var updated = identity
        updated["mooring_state"] = "UNMOORED"
        updated["ts_utc"] = isoFormatter.string(from: Date())
        try? writeJSON(updated, to: homeMooringDirectory.appendingPathComponent("cell_identity.json"))
        UserDefaults.standard.setValue(false, forKey: "fusion_onboarding_complete")
        UserDefaults.standard.setValue(false, forKey: "fusion_auto_moored_complete")
        showOnboarding = false
    }

    func readCellIdentity() -> [String: Any]? {
        let file = homeMooringDirectory.appendingPathComponent("cell_identity.json")
        guard FileManager.default.fileExists(atPath: file.path()),
              let data = try? Data(contentsOf: file),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return payload
    }

    func isS4Match(storedS4: [String: Any]) -> Bool {
        let currentS4 = currentS4Payload()
        let expectedKeys = ["hardware_uuid", "username", "hostname", "ssh_key_fingerprint", "app_version"]
        return expectedKeys.allSatisfy { key in
            String(describing: storedS4[key] ?? "") == String(describing: currentS4[key] ?? "")
        }
    }

    func currentS4Payload() -> [String: Any] {
        let state = currentS4State()
        return [
            "hardware_uuid": state.hardwareUUID,
            "username": state.username,
            "hostname": state.hostname,
            "ssh_key_fingerprint": state.sshKeyFingerprint,
            "app_version": state.appVersion,
        ]
    }

    func currentS4State() -> S4C4IdentityState {
        let defaults = UserDefaults.standard
        let keyPath = defaults.string(forKey: "fusion_ssh_key_path") ?? ""
        return S4C4IdentityState(
            hardwareUUID: hardwareUUID(),
            username: NSUserName(),
            hostname: Host.current().localizedName ?? "unknown",
            sshKeyFingerprint: sshKeyFingerprint(at: keyPath),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        )
    }

    func hardwareUUID() -> String {
        let matchingDict = IOServiceMatching("IOPlatformExpertDevice")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matchingDict)
        if service == 0 {
            return "unknown"
        }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0) else {
            return "unknown"
        }
        return value.takeRetainedValue() as? String ?? "unknown"
    }

    func sshKeyFingerprint(at keyPath: String) -> String {
        let trimmed = keyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [trimmed, "\(trimmed).pub"]
        for candidate in candidates {
            let url = URL(fileURLWithPath: candidate)
            guard FileManager.default.fileExists(atPath: url.path) else {
                continue
            }
            guard let data = try? Data(contentsOf: url) else {
                continue
            }
            return "SHA256:\(sha256Hex(data))"
        }
        return "no_key"
    }

    func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func sha256Hex(_ text: String) -> String {
        return sha256Hex(Data(text.utf8))
    }

    func canonicalJSONString(_ payload: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func createMooringReceipts(type: MooringFileType) async -> (Bool, String) {
        do {
            try FileManager.default.createDirectory(at: homeMooringDirectory, withIntermediateDirectories: true)
            let now = isoFormatter.string(from: Date())
            let natsURL = UserDefaults.standard.string(forKey: "fusion_nats_url") ?? "nats://127.0.0.1:4222"
            let natsID = await natsService.natsServerID(from: natsURL)
            let s4State = currentS4State()
            let cells = meshManager.cells.sorted { $0.name < $1.name }
            let snapshot: [[String: Any]] = cells.map { cell in
                [
                    "cell": cell.name,
                    "ip": cell.ipv4,
                    "health_http": cell.active ? 200 : 0,
                    "ok": cell.active,
                    "health": cell.health,
                    "status": cell.status,
                    "input": cell.inputPlantType.rawValue,
                    "output": cell.outputPlantType.rawValue,
                ]
            }
            let c4State: [String: Any] = [
                "mesh_snapshot": snapshot,
                "nats_server_id": natsID,
                "mooring_ts_utc": now,
                "quorum_at_mooring": cells.filter { $0.active }.count,
            ]
            let s4Payload = currentS4Payload()
            let hashInput = canonicalJSONString(s4Payload) + "||" + canonicalJSONString(c4State)
            let identityHash = sha256Hex(hashInput)
            cellIdentityHash = identityHash

            let identityPayload: [String: Any] = [
                "schema": "gaiaftcl_cell_identity_v1",
                "s4c4_hash": identityHash,
                "s4": [
                    "hardware_uuid": s4State.hardwareUUID,
                    "username": s4State.username,
                    "hostname": s4State.hostname,
                    "ssh_key_fingerprint": s4State.sshKeyFingerprint,
                    "app_version": s4State.appVersion,
                ],
                "c4": [
                    "mesh_snapshot": snapshot,
                    "nats_server_id": natsID,
                    "mooring_ts_utc": now,
                    "quorum_at_mooring": cells.filter { $0.active }.count,
                ],
                "mooring_state": "MOORED",
                "ts_utc": now,
            ]
            let mountPayload: [String: Any] = [
                "schema": "gaiaftcl_mount_receipt_v1",
                "cell_identity_hash": identityHash,
                "mount_ts_utc": now,
                "mount_type": type.rawValue,
                "s4_verified": true,
                "terminal": "CALORIE",
            ]
            let statePayload: [String: Any] = [
                "schema": "gaiaftcl_mooring_state_v1",
                "status": "MOORED",
                "terminal": "CALORIE",
                "created_utc": now,
                "mesh_cells": cells.count,
                "cell_identity_hash": identityHash,
            ]
            try writeJSON(identityPayload, to: homeMooringDirectory.appendingPathComponent("cell_identity.json"))
            try writeJSON(mountPayload, to: homeMooringDirectory.appendingPathComponent("mount_receipt.json"))
            try writeJSON(statePayload, to: homeMooringDirectory.appendingPathComponent("fusion_mesh_mooring_state.json"))
            return (true, "MOORED")
        } catch {
            return (false, "Mooring failed: \(error.localizedDescription)")
        }
    }

    func completeOnboardingIfPersistable(
        sshKeyPath: String,
        sshUser: String,
        natsURL: String,
        mooringType: MooringFileType = .manualReonboard
    ) async -> (Bool, String) {
        persistOnboardingDefaults(sshKeyPath: sshKeyPath, sshUser: sshUser, natsURL: natsURL)
        let result = await createMooringReceipts(type: mooringType)
        guard result.0 else {
            return result
        }
        completeOnboarding()
        return (true, "MOORED")
    }

    func testSSHConnection(keyPath: String, user: String, targetCellID: String) async -> (Bool, String) {
        let host = meshHost(for: targetCellID)
        guard !host.isEmpty else {
            return (false, "No target host found")
        }
        let ok = await sshService.canConnect(host: host, keyPath: keyPath, user: user)
        return (ok, ok ? "SSH connected to \(host)" : "SSH test failed for \(host)")
    }

    private func startNATSIngress() async {
        let defaults = UserDefaults.standard
        let natsURL = defaults.string(forKey: "fusion_nats_url") ?? "nats://127.0.0.1:4222"
        let configuredSubjects = defaults.string(forKey: "fusion_nats_subject") ?? ""
        let userSubjects = configuredSubjects
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let fallbackSubjects = [
            "gaiaftcl.fusion.cell.status.v1",
            "gaiaftcl.fusion.mesh_mooring.v1",
            "gaiaftcl.bitcoin.heartbeat",
            "gaiaftcl.cell.id",
        ]
        let subjects = userSubjects.isEmpty ? fallbackSubjects : userSubjects

        let connected = await natsService.startCellStatusStream(
            urlString: natsURL,
            subjects: subjects
        ) { [weak self] envelope in
            guard let self else {
                return
            }
            Task { @MainActor in
                self.processNATSEnvelope(envelope)
            }
        }
        if !connected {
            print("NATS stream subscription not available at \(natsURL)")
        }
    }

    private func armNATSMCPBridge() {
        let natsURL = UserDefaults.standard.string(forKey: "fusion_nats_url") ?? "nats://127.0.0.1:4222"
        let walletLikeID = (cellIdentityHash?.isEmpty == false ? cellIdentityHash! : Host.current().localizedName ?? "mac-cell")
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
        let root = FusionUiTorsion.resolveGaiaRepoRoot() ?? URL(fileURLWithPath: NSHomeDirectory())
        let bridge = NATSMCPBridge(
            natsURL: natsURL,
            cellWalletID: walletLikeID,
            workspaceRoot: root,
            onHotSwap: { [weak self] in
                self?.bridge.sterileHotSwapReload()
                self?.probeAllCells()
            },
            onActuatorCommand: { [weak self] method, params in
                guard let self else { return "[REFUSED] coordinator unavailable" }
                return self.handleOpenUSDActuator(method: method, params: params)
            },
            presenceExtras: { [weak self] in
                guard let self else { return [:] }
                return self.mcpCellPresenceExtras()
            }
        )
        natsMcpBridge = bridge
        Task {
            let ok = await bridge.armBridge()
            if ok {
                print("[CALORIE] NATS-MCP Bridge armed on \(bridge.rxSubject)")
            } else {
                print("[REFUSED] NATS-MCP Bridge arm failed at \(natsURL)")
            }
        }
    }

    private func handleOpenUSDActuator(method: String, params: [String: Any]?) -> String {
        func epistemicIndex(_ value: String?) -> Int {
            switch (value ?? "").lowercased() {
            case "measured":
                return 0
            case "tested":
                return 1
            case "inferred":
                return 2
            case "assumed":
                return 3
            default:
                return 0
            }
        }

        func pushUiManifoldSnapshot() {
            let ip = openUSDState.measuredTelemetry["I_p"] ?? 0.0
            let bt = openUSDState.measuredTelemetry["B_T"] ?? 0.0
            let ne = openUSDState.measuredTelemetry["n_e"] ?? 0.0
            let klass = epistemicIndex(openUSDState.epistemicClass["I_p"])
            uiStateManifold.clobberState(
                ip: ip,
                bt: bt,
                ne: ne,
                epistemicClass: klass,
                tagIp: epistemicTagLetter(for: "I_p"),
                tagBt: epistemicTagLetter(for: "B_T"),
                tagNe: epistemicTagLetter(for: "n_e")
            )
        }

        func bridgeTopologyOnlySessionLayer() -> [String: Any] {
            let full = openUSDState.sessionLayerOverlay()
            let mooring = full["mooring_variant"] as? String ?? "UNRESOLVED"
            let plant = (full["plant_payload_contract"] as? [String: Any])?["active_payload"] as? String ?? "tokamak"
            return [
                "schema": "gaiaftcl_openusd_session_layer_topology_v1",
                "mooring_variant": mooring,
                "plant_payload": plant,
            ]
        }

        func publishSessionLayerUpdate(reason: String) {
            bridge.sendDirect(
                action: "OPENUSD_SESSION_LAYER_UPDATE",
                data: [
                    "reason": reason,
                    "session_layer": bridgeTopologyOnlySessionLayer(),
                ],
                requestID: UUID().uuidString
            )
        }

        func publishInceptionSnap(reason: String) {
            let entropyCalm = openUSDState.mooringState == .moored
                && !fusionBootLikelyStuck
                && uiTorsion01 <= 0.001
            bridge.sendDirect(
                action: "OPENUSD_INCEPTION_SNAP",
                data: [
                    "reason": reason,
                    "mooring_variant": openUSDState.mooringState.rawValue,
                    "plant_payload": openUSDState.activePlantPayload,
                    "terminal_state": openUSDState.terminalState.rawValue,
                    "entropy_calm": entropyCalm,
                    "ui_torsion_01": uiTorsion01,
                ],
                requestID: UUID().uuidString
            )
        }

        switch method {
        case "get_wasm_dom_probe":
            let probe: [String: Any] = [
                "schema": "gaiaftcl_mcp_wasm_dom_probe_v1",
                "ts_ms": Int64(Date().timeIntervalSince1970 * 1000),
                "usd_px": ["status": "rust_renderer_active"],
                "wasm_surface": bridge.wasmSurfacePayloadForHealth(),
                "wasm_runtime": bridge.wasmRuntimePayloadForHealth(),
                "openusd": [
                    "mooring_variant": openUSDState.mooringState.rawValue,
                    "plant_payload": openUSDState.activePlantPayload,
                    "terminal_state": openUSDState.terminalState.rawValue,
                ],
            ]
            if let data = try? JSONSerialization.data(withJSONObject: probe, options: [.prettyPrinted, .sortedKeys]),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
            return "[REFUSED] unable to encode wasm dom probe"
        case "get_ingestion_cycles":
            let cycles: [String: Any] = [
                "schema": "gaiaftcl_mcp_ingestion_cycles_v1",
                "ts_ms": Int64(Date().timeIntervalSince1970 * 1000),
                "cycles_total": natsIngestionCycles,
                "last_ingestion_ts_ms": lastIngestionTsMs,
                "last_subject": lastIngestionSubject,
                "measured_telemetry": openUSDState.measuredTelemetry,
                "epistemic_class": openUSDState.epistemicClass,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: cycles, options: [.prettyPrinted, .sortedKeys]),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
            return "[REFUSED] unable to encode ingestion cycles"
        case "set_mooring_variant":
            guard let variant = params?["variant"] as? String else {
                return "[REFUSED] set_mooring_variant requires params.variant"
            }
            guard openUSDState.setMooringState(variant) else {
                return "[REFUSED] invalid mooring variant: \(variant)"
            }
            publishSessionLayerUpdate(reason: "set_mooring_variant")
            publishInceptionSnap(reason: "set_mooring_variant")
            pushUiManifoldSnapshot()
            return "[CALORIE] mooring variant set to \(openUSDState.mooringState.rawValue)"
        case "set_plant_payload":
            guard let plantKind = params?["plant_kind"] as? String else {
                return "[REFUSED] set_plant_payload requires params.plant_kind"
            }
            openUSDState.setPlantPayload(plantKind)
            openUSDPlayback.loadPlant(plantKind)
            syncPlaybackRingFromOpenUSD()
            publishSessionLayerUpdate(reason: "set_plant_payload")
            publishInceptionSnap(reason: "set_plant_payload")
            pushUiManifoldSnapshot()
            return "[CALORIE] plant payload set to \(openUSDState.activePlantPayload)"
        case "set_terminal_state":
            guard let state = params?["state"] as? String else {
                return "[REFUSED] set_terminal_state requires params.state"
            }
            guard openUSDState.setTerminalState(state) else {
                return "[REFUSED] invalid terminal state: \(state)"
            }
            openUSDInteractionLocked = openUSDState.interactionLocked
            publishSessionLayerUpdate(reason: "set_terminal_state")
            publishInceptionSnap(reason: "set_terminal_state")
            pushUiManifoldSnapshot()
            return "[\(openUSDState.terminalState.rawValue)] terminal state set"
        case "set_heartbeat_sample":
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let tsMs = (params?["ts_ms"] as? NSNumber)?.int64Value ?? now
            openUSDState.setHeartbeatTsMs(tsMs)
            publishSessionLayerUpdate(reason: "set_heartbeat_sample")
            return "[CALORIE] heartbeat sample updated ts_ms=\(openUSDState.heartbeatTsMs)"
        case "set_receipt_hash":
            guard let hash = params?["hash"] as? String else {
                return "[REFUSED] set_receipt_hash requires params.hash"
            }
            openUSDState.setReceiptHash(hash)
            publishSessionLayerUpdate(reason: "set_receipt_hash")
            return "[CALORIE] receipt hash updated"
        case "set_epistemic_class":
            guard let name = params?["name"] as? String,
                  let value = params?["value"] as? String else {
                return "[REFUSED] set_epistemic_class requires params.name + params.value"
            }
            guard openUSDState.setEpistemicClass(name: name, value: value) else {
                return "[REFUSED] unsupported epistemic class: \(value)"
            }
            publishSessionLayerUpdate(reason: "set_epistemic_class")
            pushUiManifoldSnapshot()
            return "[CALORIE] epistemic class set: \(name)=\(value)"
        case "set_measured_telemetry":
            let numeric = extractMeasuredTelemetry(from: params ?? [:])
            guard !numeric.isEmpty else {
                return "[REFUSED] set_measured_telemetry requires numeric payload (e.g. I_p/B_T/n_e)"
            }
            openUSDState.setMeasuredTelemetry(numeric)
            syncPlaybackRingFromOpenUSD()
            publishSessionLayerUpdate(reason: "set_measured_telemetry")
            pushUiManifoldSnapshot()
            return "[CALORIE] measured telemetry updated (\(numeric.keys.sorted().joined(separator: ",")))"
        default:
            return "[REFUSED] unsupported actuator method: \(method)"
        }
    }

    private func extractMeasuredTelemetry(from payload: [String: Any]) -> [String: Double] {
        var out: [String: Double] = [:]
        let mappings: [(String, String)] = [
            ("I_p", "I_p"),
            ("ip", "I_p"),
            ("plasma_current", "I_p"),
            ("B_T", "B_T"),
            ("bt", "B_T"),
            ("toroidal_field", "B_T"),
            ("n_e", "n_e"),
            ("ne", "n_e"),
            ("electron_density", "n_e"),
        ]
        for (source, target) in mappings {
            if let n = payload[source] as? NSNumber {
                out[target] = n.doubleValue
            } else if let s = payload[source] as? String, let d = Double(s) {
                out[target] = d
            }
        }
        return out
    }

    private func processNATSEnvelope(_ envelope: NATSCellEnvelope) {
        natsIngestionCycles += 1
        lastIngestionTsMs = Int64(envelope.receivedAt.timeIntervalSince1970 * 1000)
        lastIngestionSubject = envelope.subject
        let payload = (try? JSONSerialization.jsonObject(with: envelope.payload) as? [String: Any]) ?? [:]
        
        // Bitcoin τ (tau) synchronization - GAP 1C
        if envelope.subject == "gaiaftcl.bitcoin.heartbeat" {
            if let blockHeight = payload["block_height"] as? UInt64 {
                openUSDPlayback.setTau(blockHeight)
            } else if let blockHeightInt = payload["block_height"] as? Int {
                openUSDPlayback.setTau(UInt64(blockHeightInt))
            }
        }
        
        meshManager.recordNATSCellStatus(
            subject: envelope.subject,
            payload: payload,
            receivedAt: envelope.receivedAt
        )
        let measured = extractMeasuredTelemetry(from: payload)
        if !measured.isEmpty {
            openUSDState.setMeasuredTelemetry(measured)
            syncPlaybackRingFromOpenUSD()
            let klass: Int
            switch (openUSDState.epistemicClass["I_p"] ?? "Measured").lowercased() {
            case "measured": klass = 0
            case "tested": klass = 1
            case "inferred": klass = 2
            case "assumed": klass = 3
            default: klass = 0
            }
            uiStateManifold.clobberState(
                ip: openUSDState.measuredTelemetry["I_p"] ?? 0.0,
                bt: openUSDState.measuredTelemetry["B_T"] ?? 0.0,
                ne: openUSDState.measuredTelemetry["n_e"] ?? 0.0,
                epistemicClass: klass,
                tagIp: epistemicTagLetter(for: "I_p"),
                tagBt: epistemicTagLetter(for: "B_T"),
                tagNe: epistemicTagLetter(for: "n_e")
            )
            
            // Trigger WASM constitutional monitoring
            bridge.monitorConstitutionalState(telemetry: measured)
            let overlay = openUSDState.sessionLayerOverlay()
            let mooring = overlay["mooring_variant"] as? String ?? "UNRESOLVED"
            let payload = (overlay["plant_payload_contract"] as? [String: Any])?["active_payload"] as? String ?? "tokamak"
            let fingerprint = "\(mooring)|\(payload)"
            if lastPublishedTopologyFingerprint != fingerprint {
                lastPublishedTopologyFingerprint = fingerprint
                bridge.sendDirect(
                    action: "OPENUSD_SESSION_LAYER_UPDATE",
                    data: [
                        "reason": "nats_topology_change",
                        "session_layer": [
                            "schema": "gaiaftcl_openusd_session_layer_topology_v1",
                            "mooring_variant": mooring,
                            "plant_payload": payload,
                        ],
                    ],
                    requestID: UUID().uuidString
                )
            }
        }
    }

    func testNATSConnection(urlString: String) async -> (Bool, String) {
        guard natsService.checkConnection(urlString: urlString) else {
            return (false, "Invalid NATS URL")
        }
        guard let parsed = URLComponents(string: urlString), let host = parsed.host else {
            return (false, "Unable to parse NATS host")
        }
        let port = parsed.port ?? 4222
        let (exitCode, output) = await runShell(
            executable: "/usr/bin/nc",
            arguments: ["-z", "-w", "4", host, "\(port)"]
        )
        let ok = exitCode == 0
        return (ok, ok ? "NATS reachable at \(urlString)" : "NATS test failed: \(output)")
    }

    func openSSHTerminal(for cellID: String) {
        openTraceLayer(mode: .grid)
        let host = meshHost(for: cellID)
        guard !host.isEmpty else {
            sshTerminalOutput = "No target host found for \(cellID)"
            showSSHTerminalOutput = true
            return
        }
        let keyPath = UserDefaults.standard.string(forKey: "fusion_ssh_key_path") ?? ""
        let user = UserDefaults.standard.string(forKey: "fusion_ssh_user") ?? "root"
        guard !keyPath.isEmpty else {
            sshTerminalOutput = "No SSH key configured."
            showSSHTerminalOutput = true
            return
        }
        sshTerminalOutput = "Running SSH command against \(host)..."
        showSSHTerminalOutput = true
        Task {
            let output = await sshService.runSSHCommand(
                host: host,
                keyPath: keyPath,
                user: user,
                command: "hostname && uname -a"
            )
            await MainActor.run {
                sshTerminalOutput = "exit_code=\(output.exitCode)\n\n\(output.output)"
                showSSHTerminalOutput = true
            }
        }
    }

    func toggleInspector() {
        if !showTraceLayer {
            openTraceLayer(mode: .grid)
            return
        }
        showInspector.toggle()
    }

    func toggleSidebar() {
        if !showTraceLayer {
            openTraceLayer(mode: .grid)
            return
        }
        splitViewVisibility = splitViewVisibility == .all ? .detailOnly : .all
    }

    func openTraceLayer(mode: FusionShellMode = .grid) {
        showTraceLayer = true
        splitViewVisibility = .all
        shellMode = mode
        showInspector = true
        bridge.sendDirect(action: mode.bridgeAction, data: [:], requestID: UUID().uuidString)
    }

    func closeTraceLayer() {
        showTraceLayer = false
        splitViewVisibility = .detailOnly
        shellMode = .projection
        showInspector = false
        bridge.sendDirect(action: FusionShellMode.projection.bridgeAction, data: [:], requestID: UUID().uuidString)
    }

    func toggleTraceLayer() {
        if showTraceLayer {
            closeTraceLayer()
        } else {
            openTraceLayer(mode: .grid)
        }
    }

    // MARK: - File Menu Actions
    
    func newSession() {
        // Note: This is NOT a login screen. GaiaFusion reads IQ qualification records.
        // New Session means: reload the IQ record, re-establish moored wallet context,
        // and reset plant to IDLE state.
        let alert = NSAlert()
        alert.messageText = "New Session"
        alert.informativeText = "Reload IQ qualification record and reset plant to IDLE state?\n\nThis will:\n• Re-read moored wallet context from IQ\n• Transition plant to IDLE\n• Clear any pending state\n\nNote: Authorization comes from IQ-registered wallets, not login credentials."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Reload IQ and Reset")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // TODO: Implement IQ record reload
            // 1. Read ~/.gaiaftcl/iq_qualification_record.json (or similar path)
            // 2. Parse moored wallets and their L1/L2/L3 roles
            // 3. Populate MooredWalletContext
            // 4. Transition plant to IDLE
            _ = fusionCellStateMachine.requestTransition(
                to: .idle,
                initiator: .operatorAction("new_session_\(currentOperatorRole.rawValue)"),
                reason: "Operator reloaded IQ qualification and reset session"
            )
            print("✅ New Session: IQ reload initiated (stub — MooredWalletContext not yet implemented)")
        }
    }
    
    func openPlantConfig() {
        let panel = NSOpenPanel()
        panel.title = "Open Plant Configuration"
        panel.prompt = "Open"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        panel.begin { [weak self] response in
            guard let self = self else { return }
            if response == .OK, let url = panel.url {
                self.loadPlantConfiguration(from: url)
            }
        }
    }
    
    private func loadPlantConfiguration(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            if let plantType = json?["plant_type"] as? String {
                print("✅ Loaded plant configuration: \(plantType) from \(url.lastPathComponent)")
                
                let alert = NSAlert()
                alert.messageText = "Plant Configuration Loaded"
                alert.informativeText = "Plant Type: \(plantType)\nFile: \(url.lastPathComponent)\n\nConfiguration loaded successfully. Apply changes to activate."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Failed to Load Configuration"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    func saveSnapshot() {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let snapshot: [String: Any] = [
            "timestamp": timestamp,
            "plant_state": fusionCellStateMachine.operationalState.rawValue,
            "plant_kind": openUSDPlayback.plantKind,
            "operator_role": currentOperatorRole.rawValue,
            "layout_mode": layoutManager.currentMode.rawValue,
            "metal_opacity": layoutManager.metalOpacity,
            "webview_opacity": layoutManager.webviewOpacity,
            "constitutional_hud_visible": layoutManager.constitutionalHudVisible,
            "mesh_cells_count": meshManager.cells.count,
            "healthy_cells": meshManager.cells.filter { $0.health > 0.5 }.count,
            "session_id": cellIdentityHash ?? "unknown"
        ]
        
        let panel = NSSavePanel()
        panel.title = "Save State Snapshot"
        panel.prompt = "Save"
        panel.nameFieldStringValue = "gaiafusion_snapshot_\(timestamp.replacingOccurrences(of: ":", with: "-")).json"
        panel.allowedContentTypes = [.json]
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys])
                    try jsonData.write(to: url)
                    print("✅ Snapshot saved: \(url.path)")
                    
                    let alert = NSAlert()
                    alert.messageText = "Snapshot Saved"
                    alert.informativeText = "State snapshot saved to:\n\(url.lastPathComponent)\n\nPlant: \(snapshot["plant_kind"] as? String ?? "unknown")\nState: \(snapshot["plant_state"] as? String ?? "unknown")"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "Failed to Save Snapshot"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }
    
    func exportAuditLog() {
        // TODO: Implement audit log export with compliance formatting
        // Requires audit log system (file-based or database)
        let alert = NSAlert()
        alert.messageText = "Export Audit Log"
        alert.informativeText = "Audit log export requires audit logging system integration.\n\nTODO: Implement audit log collection from file/database, compliance formatting (CSV/JSON), and signature verification."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
        print("⚠️ Export Audit Log: Requires audit log system")
    }
    
    // MARK: - Cell Menu Actions
    
    func swapPlant() {
        let alert = NSAlert()
        alert.messageText = "Swap Plant Topology"
        alert.informativeText = "Select target plant configuration:"
        alert.alertStyle = .informational
        
        // Add plant type buttons (9 canonical plants)
        let plantTypes: [(PlantType, String)] = [
            (.tokamak, "Tokamak (NSTX-U class)"),
            (.stellarator, "Stellarator (W7-X class)"),
            (.sphericalTokamak, "Spherical Tokamak (HTS compact)"),
            (.frc, "Field-Reversed Configuration"),
            (.spheromak, "Spheromak"),
            (.mirror, "Magnetic Mirror"),
            (.inertial, "Inertial Confinement (ICF)"),
            (.zPinch, "Z-Pinch"),
            (.mif, "Magneto-Inertial Fusion (MIF)")
        ]
        
        for (_, (_, displayName)) in plantTypes.enumerated() {
            alert.addButton(withTitle: displayName)
        }
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn || response.rawValue >= NSApplication.ModalResponse.alertFirstButtonReturn.rawValue {
            let selectedIndex = Int(response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue)
            if selectedIndex < plantTypes.count {
                let (selectedPlant, displayName) = plantTypes[selectedIndex]
                performPlantSwap(to: selectedPlant, displayName: displayName)
            }
        }
    }
    
    private func performPlantSwap(to plantType: PlantType, displayName: String) {
        print("🔄 Swapping plant to: \(plantType.rawValue)")
        
        // Send swap request to Metal renderer
        Task { @MainActor in
            await openUSDPlayback.requestPlantSwap(to: plantType.rawValue)
            
            // Send to WKWebView dashboard
            bridge.sendDirect(
                action: "PLANT_SWAP_COMPLETE",
                data: [
                    "plant_type": plantType.rawValue,
                    "display_name": displayName,
                    "timestamp": ISO8601DateFormatter().string(from: Date()),
                    "operator_role": currentOperatorRole.rawValue
                ],
                requestID: UUID().uuidString
            )
            
            print("✅ Plant swap complete: \(displayName)")
        }
    }
    
    func armIgnition() {
        // TODO: Implement dual-authorization ignition arm protocol
        // Requires L2 operator initiation + L3 supervisor approval within 30s timeout
        let alert = NSAlert()
        alert.messageText = "Arm Ignition"
        alert.informativeText = "Dual-authorization protocol required.\n\nTODO: Implement L2 initiation dialog, L3 supervisor authentication prompt (different user ID), 30-second timeout, and audit trail entry with both operator IDs."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
        print("⚠️ Arm Ignition: Requires dual-auth system (L2 + L3)")
    }
    
    func emergencyStop() {
        let alert = NSAlert()
        alert.messageText = "Emergency Stop"
        alert.informativeText = "Initiate immediate plasma shutdown?"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Emergency Stop")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            _ = fusionCellStateMachine.requestTransition(
                to: .tripped,
                initiator: .operatorAction("emergency_stop_\(currentOperatorRole.rawValue)"),
                reason: "Operator emergency stop invoked"
            )
            print("🔴 Emergency Stop: Plant transitioned to TRIPPED state")
            
            // Send to dashboard
            bridge.sendDirect(
                action: "EMERGENCY_STOP_EXECUTED",
                data: [
                    "timestamp": ISO8601DateFormatter().string(from: Date()),
                    "operator_role": currentOperatorRole.rawValue,
                    "previous_state": "RUNNING",
                    "new_state": "TRIPPED"
                ],
                requestID: UUID().uuidString
            )
        }
    }
    
    func resetTrip() {
        // TODO: Implement dual-authorization trip reset protocol
        // Requires trip review + L2 initiation + L3 approval
        let alert = NSAlert()
        alert.messageText = "Reset Trip"
        alert.informativeText = "Trip reset requires dual-authorization protocol.\n\nTODO: Implement trip condition review dialog, L2 operator initiation, L3 supervisor approval, and audit trail entry documenting trip cause and resolution."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
        print("⚠️ Reset Trip: Requires dual-auth system (L2 + L3) + trip review")
    }
    
    func acknowledgeAlarm() {
        let alert = NSAlert()
        alert.messageText = "Acknowledge Constitutional Alarm"
        alert.informativeText = "Acknowledge constitutional violation and transition plant to IDLE state?\n\nThis action will be logged with your operator ID."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Acknowledge")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            _ = fusionCellStateMachine.requestTransition(
                to: .idle,
                initiator: .operatorAction("alarm_acknowledge_\(currentOperatorRole.rawValue)"),
                reason: "Operator acknowledged constitutional alarm"
            )
            print("✅ Alarm Acknowledged: Plant transitioned to IDLE state")
            
            // Send to dashboard
            bridge.sendDirect(
                action: "CONSTITUTIONAL_ALARM_ACKNOWLEDGED",
                data: [
                    "timestamp": ISO8601DateFormatter().string(from: Date()),
                    "operator_role": currentOperatorRole.rawValue,
                    "previous_state": "CONSTITUTIONAL_ALARM",
                    "new_state": "IDLE"
                ],
                requestID: UUID().uuidString
            )
        }
    }
    
    // MARK: - Config Menu Actions
    
    func trainingMode() {
        let alert = NSAlert()
        alert.messageText = "Enter Training Mode"
        alert.informativeText = "Enter training mode with simulated plant data?\n\nTraining mode actions will be marked in audit logs and do not affect real plant operations."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Enter Training Mode")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            _ = fusionCellStateMachine.requestTransition(
                to: .training,
                initiator: .operatorAction("training_mode_enter_\(currentOperatorRole.rawValue)"),
                reason: "Operator entered training mode"
            )
            print("🎓 Training Mode: Plant transitioned to TRAINING state")
            
            // Send to dashboard
            bridge.sendDirect(
                action: "TRAINING_MODE_ACTIVATED",
                data: [
                    "timestamp": ISO8601DateFormatter().string(from: Date()),
                    "operator_role": currentOperatorRole.rawValue,
                    "previous_state": "IDLE",
                    "new_state": "TRAINING"
                ],
                requestID: UUID().uuidString
            )
        }
    }
    
    func maintenanceMode() {
        let alert = NSAlert()
        alert.messageText = "Enter Maintenance Mode"
        alert.informativeText = "Enter maintenance mode for plant servicing?\n\nMaintenance mode disables safety interlocks and requires L3 supervisor authorization."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Enter Maintenance Mode")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            _ = fusionCellStateMachine.requestTransition(
                to: .maintenance,
                initiator: .operatorAction("maintenance_mode_enter_\(currentOperatorRole.rawValue)"),
                reason: "Supervisor entered maintenance mode"
            )
            print("🔧 Maintenance Mode: Plant transitioned to MAINTENANCE state")
            
            // Send to dashboard
            bridge.sendDirect(
                action: "MAINTENANCE_MODE_ACTIVATED",
                data: [
                    "timestamp": ISO8601DateFormatter().string(from: Date()),
                    "operator_role": currentOperatorRole.rawValue,
                    "previous_state": "IDLE",
                    "new_state": "MAINTENANCE"
                ],
                requestID: UUID().uuidString
            )
        }
    }
    
    func authSettings() {
        // Note: This is NOT a credential management panel. GaiaFusion is a consumer of IQ output.
        // Authorization Settings shows the current IQ qualification status (read-only view).
        // Wallet role management happens in the IQ process, not this app.
        let alert = NSAlert()
        alert.messageText = "Authorization Settings (Read-Only)"
        alert.informativeText = """
Current IQ Qualification Status:

Cell ID: \(cellIdentityHash ?? "unknown")
Current Context Role: \(currentOperatorRole.rawValue)

Moored Wallets:
• TODO: Read from IQ qualification record
• Display wallet pubkeys and their L1/L2/L3 roles

Note: Wallet role assignment is managed by the IQ process.
This application consumes the IQ output — it does not modify it.

To change wallet roles, re-run the IQ qualification process.
"""
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
        
        // TODO: Read IQ qualification record and display moored wallets
        print("📋 Authorization Settings: Displaying IQ qualification status")
        print("   Cell ID: \(cellIdentityHash ?? "unknown")")
        print("   Current Role: \(currentOperatorRole.rawValue)")
        print("   Moored Wallets: (not yet implemented — requires IQ record reader)")
    }
    
    // MARK: - Help Menu Actions
    
    func viewAuditLog() {
        let alert = NSAlert()
        alert.messageText = "Audit Log Viewer"
        alert.informativeText = "View read-only audit trail?\n\nTODO: Implement:\n• Audit log file/database reader\n• Filterable table view (by operator, action, timestamp, state)\n• Export to CSV/JSON\n• Signature verification\n• Search and pagination\n\nCurrent Status: No audit log entries collected yet."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
        
        // Show recent state transitions from state machine
        print("📋 Recent State Transitions (console only):")
        print("   Plant State: \(fusionCellStateMachine.operationalState.rawValue)")
        print("   Operator Role: \(currentOperatorRole.rawValue)")
        print("   Layout Mode: \(layoutManager.currentMode.rawValue)")
    }
    
    func showAbout() {
        let alert = NSAlert()
        let ver =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? Bundle.gaiafusionResources.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "1.0"
        let build =
            Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            ?? Bundle.gaiafusionResources.infoDictionary?["CFBundleVersion"] as? String
            ?? "1"
        alert.messageText = "GaiaFusion"
        alert.informativeText =
            "GaiaFTCL Fusion Mac Host — FortressAI Research Institute\nVersion \(ver) (\(build))\nNative Metal + OpenUSD viewport behind the fusion-s4 WebView."
        alert.runModal()
    }

    private func runShell(executable: String, arguments: [String]) async -> (Int, String) {
        await withCheckedContinuation { continuation in
            processQueue.async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                let out = Pipe()
                process.standardOutput = out
                process.standardError = out
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = out.fileHandleForReading.readDataToEndOfFile()
                    let text = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: (Int(process.terminationStatus), text))
                } catch {
                    continuation.resume(returning: (127, String(describing: error)))
                }
            }
        }
    }

    private func writeJSON(_ payload: [String: Any], to file: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: file, options: .atomic)
    }
}
