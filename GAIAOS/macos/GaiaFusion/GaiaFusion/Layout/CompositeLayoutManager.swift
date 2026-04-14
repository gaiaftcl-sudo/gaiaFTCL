import Foundation
import SwiftUI

/// Layout modes for GaiaFusion composite viewport
/// Note: splitView removed per 21 CFR Part 11 §11.10(d)(g) - creates unattributable audit trail
enum LayoutMode: String, Codable, CaseIterable, Identifiable {
    case dashboardFocus = "dashboard_focus"
    case geometryFocus = "geometry_focus"
    case constitutionalAlarm = "constitutional_alarm"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .dashboardFocus:
            return "Dashboard Focus"
        case .geometryFocus:
            return "Geometry Focus"
        case .constitutionalAlarm:
            return "Constitutional Alarm"
        }
    }
    
    var description: String {
        switch self {
        case .dashboardFocus:
            return "WKWebView primary (telemetry, mesh), Metal ambient 10%"
        case .geometryFocus:
            return "Metal wireframe primary 100%, WKWebView hidden"
        case .constitutionalAlarm:
            return "Metal 100% RED, constitutional violation HUD overlay"
        }
    }
}

/// Wireframe color states (driven by WASM constitutional checks)
enum WireframeColorState: Equatable {
    case normal      // Blue: PASS (no violations)
    case warning     // Yellow: Bounds warning (C-001 through C-003)
    case critical    // Red: Constitutional violation (C-004 through C-006)
    case custom([Float])  // Custom RGBA
    
    var rgba: [Float] {
        switch self {
        case .normal:
            return [0.0, 1.0, 1.0, 1.0]  // Pure cyan per LAYOUT_SPEC_COMPLIANCE.md (RGB: 0, 255, 255)
        case .warning:
            return [1.0, 0.8, 0.0, 1.0]  // Bright yellow (high contrast)
        case .critical:
            return [1.0, 0.2, 0.2, 1.0]  // Bright red (high contrast)
        case .custom(let values):
            return values
        }
    }
    
    var displayName: String {
        switch self {
        case .normal:
            return "PASS"
        case .warning:
            return "WARNING"
        case .critical:
            return "CRITICAL"
        case .custom:
            return "CUSTOM"
        }
    }
}

/// Manages composite layout state and WASM-driven transitions
@MainActor
final class CompositeLayoutManager: ObservableObject {
    // Layout state
    @Published var currentMode: LayoutMode = .dashboardFocus
    @Published var metalOpacity: Double = FusionDesignTokens.Opacity.metalDashboard
    @Published var webviewOpacity: Double = FusionDesignTokens.Opacity.webviewDashboard
    @Published var constitutionalHudVisible: Bool = false
    @Published var wireframeColor: WireframeColorState = .normal
    
    // Plant state-driven mode control (Phase 4)
    @Published var keyboardShortcutsEnabled: Bool = true
    var operatorPreferredMode: LayoutMode = .dashboardFocus
    
    // WASM state
    @Published var lastViolationCode: UInt8 = 0
    @Published var lastTerminalState: UInt8 = 0
    @Published var lastClosureResidual: Double = 0.0
    
    // Animation
    private let transitionDuration: TimeInterval = FusionDesignTokens.Animation.layoutTransition
    
    init() {
        // ALWAYS start in dashboardFocus to show Next.js panels on launch
        currentMode = .dashboardFocus
        metalOpacity = FusionDesignTokens.Opacity.metalDashboard  // 0.10
        webviewOpacity = FusionDesignTokens.Opacity.webviewDashboard  // 1.0
        print("🔧 CompositeLayoutManager init: mode=dashboardFocus, metal=\(metalOpacity), webview=\(webviewOpacity)")
    }
    
    /// Apply a layout mode with optional animation
    func applyMode(_ mode: LayoutMode, animated: Bool = true) {
        let apply = {
            self.currentMode = mode
            
            switch mode {
            case .dashboardFocus:
                self.metalOpacity = FusionDesignTokens.Opacity.metalDashboard
                self.webviewOpacity = FusionDesignTokens.Opacity.webviewDashboard
                self.constitutionalHudVisible = false
                
            case .geometryFocus:
                self.metalOpacity = FusionDesignTokens.Opacity.metalGeometry
                self.webviewOpacity = FusionDesignTokens.Opacity.webviewGeometry
                self.constitutionalHudVisible = false
                
            case .constitutionalAlarm:
                self.metalOpacity = FusionDesignTokens.Opacity.metalAlarm
                self.webviewOpacity = FusionDesignTokens.Opacity.webviewAlarm
                self.constitutionalHudVisible = true
                self.wireframeColor = .critical
                
            }
            
            // Persist mode
            UserDefaults.standard.set(mode.rawValue, forKey: "fusion_layout_mode")
        }
        
        if animated {
            withAnimation(.easeInOut(duration: transitionDuration)) {
                apply()
            }
        } else {
            apply()
        }
    }
    
    /// Update layout from WASM constitutional check results
    /// violationCode: 0=PASS, 1-3=bounds, 4-6=critical
    /// terminalState: 0=CALORIE, 1=CURE, 2=REFUSED
    func updateFromWasm(violationCode: UInt8, terminalState: UInt8, closureResidual: Double = 0.0) {
        lastViolationCode = violationCode
        lastTerminalState = terminalState
        lastClosureResidual = closureResidual
        
        // Auto-switch mode enabled?
        let autoSwitch = UserDefaults.standard.bool(forKey: "fusion_wasm_auto_layout_switch")
        guard autoSwitch else {
            // Manual mode: only update color, not layout
            updateWireframeColor(violationCode)
            return
        }
        
        // WASM-driven layout logic
        if violationCode > 0 {
            // Constitutional violation detected
            if violationCode >= 4 {
                // Critical violation (C-004 through C-006)
                applyMode(.constitutionalAlarm)
            } else {
                // Bounds warning (C-001 through C-003)
                wireframeColor = .warning
                // Keep current mode but show warning color
            }
        } else {
            // No violations - use terminal state
            switch terminalState {
            case 0: // CALORIE
                if currentMode == .constitutionalAlarm {
                    applyMode(.dashboardFocus)
                }
            case 1: // CURE
                if currentMode == .constitutionalAlarm {
                    applyMode(.dashboardFocus)
                }
            case 2: // REFUSED
                applyMode(.constitutionalAlarm)
            default:
                break
            }
        }
        
        updateWireframeColor(violationCode)
    }
    
    /// Update wireframe color based on violation code
    private func updateWireframeColor(_ violationCode: UInt8) {
        switch violationCode {
        case 0:
            wireframeColor = .normal
        case 1...3:
            wireframeColor = .warning
        case 4...6:
            wireframeColor = .critical
        default:
            break
        }
    }
    
    /// Toggle between modes (for keyboard shortcuts)
    func cycleMode() {
        let modes: [LayoutMode] = [.dashboardFocus, .geometryFocus]
        guard let currentIndex = modes.firstIndex(of: currentMode) else {
            applyMode(.dashboardFocus)
            return
        }
        let nextIndex = (currentIndex + 1) % modes.count
        applyMode(modes[nextIndex])
    }
    
    /// Cycle Metal opacity (0% / 50% / 100%)
    func cycleMetalOpacity() {
        let opacities: [Double] = [0.0, 0.5, 1.0]
        let current = metalOpacity
        var closest = opacities[0]
        var minDiff = abs(current - closest)
        
        for opacity in opacities {
            let diff = abs(current - opacity)
            if diff < minDiff {
                minDiff = diff
                closest = opacity
            }
        }
        
        guard let currentIndex = opacities.firstIndex(of: closest) else {
            metalOpacity = 1.0
            return
        }
        
        let nextIndex = (currentIndex + 1) % opacities.count
        withAnimation(.easeInOut(duration: 0.25)) {
            metalOpacity = opacities[nextIndex]
        }
    }
    
    /// Toggle constitutional HUD overlay
    func toggleConstitutionalHud() {
        withAnimation(.easeInOut(duration: 0.25)) {
            constitutionalHudVisible.toggle()
        }
    }
    
    /// Apply forced mode based on plant operational state (Phase 4)
    func applyForcedMode(for state: PlantOperationalState) {
        switch state {
        case .tripped:
            // Force dashboard, lock shortcuts
            applyMode(.dashboardFocus)
            keyboardShortcutsEnabled = false
            
        case .constitutionalAlarm:
            // Force constitutional alarm mode, show HUD, lock shortcuts
            applyMode(.constitutionalAlarm)
            constitutionalHudVisible = true
            keyboardShortcutsEnabled = false
            
        case .maintenance:
            // Allow geometry mode in maintenance, enable shortcuts
            if operatorPreferredMode == .geometryFocus {
                applyMode(.geometryFocus)
            } else {
                applyMode(operatorPreferredMode)
            }
            keyboardShortcutsEnabled = true
            
        case .idle, .moored, .training:
            // Honor operator preference, enable shortcuts
            applyMode(operatorPreferredMode)
            keyboardShortcutsEnabled = true
            
        case .running:
            // Allow mode switching during plasma operation (operator may inspect geometry)
            keyboardShortcutsEnabled = true
        }
    }
    
    /// Request mode change from operator (respects plant state)
    func requestMode(_ mode: LayoutMode, plantState: PlantOperationalState) {
        guard plantState.allowsLayoutModeOverride else {
            print("⚠️ Layout mode override blocked by plant state: \(plantState.rawValue)")
            return
        }
        
        operatorPreferredMode = mode
        applyMode(mode)
    }
}
