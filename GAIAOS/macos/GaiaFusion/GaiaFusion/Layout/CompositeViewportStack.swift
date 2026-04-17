import SwiftUI

/// Composite viewport stack with Metal wireframe + WKWebView dashboard
/// Supports 4 layout modes with dynamic opacity control
struct CompositeViewportStack: View {
    @ObservedObject var layoutManager: CompositeLayoutManager
    @ObservedObject var metalPlayback: MetalPlaybackController
    @ObservedObject var coordinator: AppCoordinator
    let serverPort: Int
    
    var body: some View {
        // MAIN CONTENT ROW - no mode switcher bar (modes are plant-state driven per PHASE 4)
        HStack(spacing: 0) {
            // LEFT SIDEBAR: 285pt fixed per spec, OUTSIDE ZStack
            FusionControlSidebar(
                plantKind: metalPlayback.plantKind,
                playback: metalPlayback
            )
            .frame(width: 285)
            
            // CENTER + RIGHT: ZStack with Metal + WKWebView
            // Metal viewport uses GeometryReader to get ACTUAL available space
            GeometryReader { viewportGeometry in
                ZStack {
                    // Layer 0: Dark slate backdrop (Z=0)
                    FusionWebShellBackdrop()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .zIndex(0)
                        .allowsHitTesting(false)
                    
                    // Layer 1: Metal wireframe viewport (Z=1)
                    // Centered in viewportGeometry space (the actual available space)
                    if coordinator.shellMode == .phiWitness {
                        PhiWitnessView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .zIndex(1)
                            .accessibilityIdentifier("phi_witness_viewport")
                    } else {
                        FusionMetalViewportView(playback: metalPlayback)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.clear)
                            .opacity(layoutManager.metalOpacity)
                            .allowsHitTesting(layoutManager.currentMode == .geometryFocus)
                            .zIndex(1)
                            .accessibilityIdentifier("metal_wireframe_viewport")
                            .onAppear {
                                print("🎯 Metal viewport space: \(viewportGeometry.size.width)×\(viewportGeometry.size.height)")
                                metalPlayback.updateDrawableSize(viewportGeometry.size)
                            }
                            .onChange(of: viewportGeometry.size) { _, newSize in
                                print("🎯 Metal viewport resize: \(newSize.width)×\(newSize.height)")
                                metalPlayback.updateDrawableSize(newSize)
                            }
                            .onChange(of: layoutManager.wireframeColor) { _, newColor in
                                metalPlayback.setWireframeBaseColor(newColor.rgba)
                            }
                    }
                    
                    // Layer 2: WKWebView dashboard (Z=2) - CRITICAL: This renders Next.js panels
                    if coordinator.server.isRunning {
                        FusionWebView(
                            coordinator: coordinator,
                            onReady: { loaded in
                                coordinator.setBridgeReady(loaded)
                            },
                            onLoadURL: URL(string: "http://127.0.0.1:\(serverPort)/fusion-s4")
                                ?? URL(string: "http://127.0.0.1:8910/fusion-s4")!
                        )
                        .background(Color.clear)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(layoutManager.webviewOpacity)  // ← MUST be bound to live value
                        .allowsHitTesting(layoutManager.currentMode != .geometryFocus)
                        .zIndex(2)
                        .accessibilityIdentifier("fusion_webview_dashboard")
                    } else {
                        VStack(spacing: FusionDesignTokens.Spacing.lg) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Starting Fusion local surface on 127.0.0.1:\(serverPort)…")
                                .font(FusionDesignTokens.Typography.caption)
                                .foregroundStyle(FusionDesignTokens.Foreground.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, FusionDesignTokens.Spacing.xxxl)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .zIndex(2)
                    }
                    
                    // Layer 5: Layout mode indicator (Z=5, bottom-center) - VStack+Spacer pattern
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                            .allowsHitTesting(false)
                        if layoutManager.currentMode != .dashboardFocus {
                            LayoutModeIndicator(mode: layoutManager.currentMode)
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, 12)
                                .allowsHitTesting(false)
                                .opacity(layoutManager.currentMode != .dashboardFocus ? 1 : 0)
                                .animation(.easeInOut, value: layoutManager.currentMode)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .zIndex(5)
                    
                    // Layer 10: Constitutional HUD (Z=10, top-anchored) - VStack+Spacer pattern
                    VStack(spacing: 0) {
                        if layoutManager.constitutionalHudVisible {
                            ConstitutionalHUD(layoutManager: layoutManager)
                                .frame(maxWidth: .infinity)
                                .allowsHitTesting(true)
                                .accessibilityIdentifier("constitutional_hud")
                        }
                        Spacer(minLength: 0)
                            .allowsHitTesting(false)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(layoutManager.constitutionalHudVisible ? 1 : 0)
                    .animation(.easeInOut, value: layoutManager.constitutionalHudVisible)
                    .zIndex(10)
                    
                    // Layer 20: Splash overlay (Z=20, full-screen blocking, conditional)
                    if coordinator.splashOverlayVisible {
                        splashOverlay
                            .transition(.opacity)
                            .zIndex(20)
                            .allowsHitTesting(true)
                    }
                } // End ZStack
            } // End GeometryReader
        } // End HStack for main content
        .onChange(of: coordinator.server.isRunning) { _, _ in
            coordinator.refreshSplashHandshake()
        }
        .onChange(of: coordinator.fusionCellStateMachine.operationalState) {
            let newState = coordinator.fusionCellStateMachine.operationalState
            withAnimation(.easeInOut(duration: 0.2)) {
                layoutManager.applyForcedMode(for: newState)
            }
            
            // Phase 7: Control plasma visibility based on plant state
            switch newState {
            case .running, .constitutionalAlarm:
                // Enable plasma particles
                metalPlayback.enablePlasma()
            case .idle, .moored, .tripped, .maintenance, .training:
                // Disable plasma and clear buffer
                metalPlayback.disablePlasma()
            }
        }
    }
    
    private var splashOverlay: some View {
        ZStack {
            // Check Bundle.main first to avoid Bundle.gaiaFusionResourceBundle crash
            let mainBundle = Bundle.main
            let namedBundleURL = mainBundle.url(forResource: "GaiaFusion_GaiaFusion", withExtension: "bundle")
            let namedBundle = namedBundleURL.flatMap { Bundle(url: $0) }
            
            let splashURL = mainBundle.url(forResource: "splash@1x", withExtension: "png", subdirectory: "Branding/Splash.imageset")
              ?? namedBundle?.url(forResource: "splash@1x", withExtension: "png", subdirectory: "Branding/Splash.imageset")
            
            if let url = splashURL, let img = NSImage(contentsOf: url) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            } else {
                FusionWebShellBackdrop()
            }
            VStack(spacing: FusionDesignTokens.Spacing.md) {
                ProgressView()
                    .controlSize(.large)
                Text("Moored to local Fusion surface…")
                    .font(FusionDesignTokens.Typography.caption)
                    .foregroundStyle(FusionDesignTokens.Foreground.secondary)
            }
            .padding(FusionDesignTokens.Spacing.xxxl)
        }
    }
}

/// Dark slate backdrop gradient (matches Metal viewport clear color)
private struct FusionWebShellBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [
                FusionDesignTokens.Background.gradientTop,
                FusionDesignTokens.Background.gradientMid,
                FusionDesignTokens.Background.gradientBottom,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

/// Transient layout mode indicator (bottom center)
private struct LayoutModeIndicator: View {
    let mode: LayoutMode
    @State private var visible = true
    
    var body: some View {
        VStack {
            Spacer(minLength: 0)
                .allowsHitTesting(false)
            HStack {
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
                HStack(spacing: FusionDesignTokens.Spacing.sm) {
                    Circle()
                        .fill(indicatorColor)
                        .frame(width: FusionDesignTokens.Size.indicatorSmall, height: FusionDesignTokens.Size.indicatorSmall)
                    Text(mode.displayName)
                        .font(FusionDesignTokens.Typography.modeIndicator)
                        .foregroundStyle(FusionDesignTokens.Foreground.primary)
                }
                .padding(.horizontal, FusionDesignTokens.Spacing.xl)
                .padding(.vertical, FusionDesignTokens.Spacing.sm)
                .background(FusionDesignTokens.Background.modeIndicator)
                .clipShape(Capsule())
                .opacity(visible ? 1 : 0)
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
            }
            .padding(.bottom, FusionDesignTokens.Spacing.edge)
        }
        .allowsHitTesting(false)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + FusionDesignTokens.Animation.modeIndicatorDisplay) {
                withAnimation(.easeOut(duration: FusionDesignTokens.Animation.modeIndicatorFade)) {
                    visible = false
                }
            }
        }
    }
    
    private var indicatorColor: Color {
        switch mode {
        case .dashboardFocus:
            return FusionDesignTokens.Status.info
        case .geometryFocus:
            return FusionDesignTokens.Status.normal
        case .constitutionalAlarm:
            return FusionDesignTokens.Status.critical
        }
    }
}
