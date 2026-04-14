import SwiftUI

/// Constitutional state HUD overlay - displays WASM violations and closure residuals
struct ConstitutionalHUD: View {
    @ObservedObject var layoutManager: CompositeLayoutManager
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                    .allowsHitTesting(false)
                hudContent
                    .padding(FusionDesignTokens.Spacing.xl)
                    .background(FusionDesignTokens.Background.hudOverlay)
                    .clipShape(RoundedRectangle(cornerRadius: FusionDesignTokens.Size.cornerRadius))
                    .shadow(color: violationColor.opacity(FusionDesignTokens.Opacity.shadow), radius: FusionDesignTokens.Size.cornerRadius)
                    .padding(.top, FusionDesignTokens.Spacing.hudTop)
                    .padding(.trailing, FusionDesignTokens.Spacing.xxl)
            }
            Spacer(minLength: 0)
                .allowsHitTesting(false)
        }
    }
    
    private var hudContent: some View {
        VStack(alignment: .leading, spacing: FusionDesignTokens.Spacing.base) {
            // Header
            HStack(spacing: FusionDesignTokens.Spacing.sm) {
                Circle()
                    .fill(violationColor)
                    .frame(width: FusionDesignTokens.Size.indicatorLarge, height: FusionDesignTokens.Size.indicatorLarge)
                Text("CONSTITUTIONAL STATE")
                    .font(FusionDesignTokens.Typography.hudHeader)
                    .foregroundStyle(FusionDesignTokens.Foreground.primary)
            }
            
            Divider()
                .background(FusionDesignTokens.Foreground.divider)
            
            // Violation code
            HStack {
                Text("Violation:")
                    .font(FusionDesignTokens.Typography.hudLabel)
                    .foregroundStyle(FusionDesignTokens.Foreground.secondary)
                Spacer()
                Text(violationCodeDisplay)
                    .font(FusionDesignTokens.Typography.hudValue)
                    .foregroundStyle(violationColor)
            }
            
            // Terminal state
            HStack {
                Text("Terminal:")
                    .font(FusionDesignTokens.Typography.hudLabel)
                    .foregroundStyle(FusionDesignTokens.Foreground.secondary)
                Spacer()
                Text(terminalStateDisplay)
                    .font(FusionDesignTokens.Typography.hudValue)
                    .foregroundStyle(terminalStateColor)
            }
            
            // Closure residual
            HStack {
                Text("Residual:")
                    .font(FusionDesignTokens.Typography.hudLabel)
                    .foregroundStyle(FusionDesignTokens.Foreground.secondary)
                Spacer()
                Text(String(format: "%.6f", layoutManager.lastClosureResidual))
                    .font(FusionDesignTokens.Typography.hudValue)
                    .foregroundStyle(residualColor)
            }
            
            // Wireframe color state
            HStack {
                Text("Wireframe:")
                    .font(FusionDesignTokens.Typography.hudLabel)
                    .foregroundStyle(FusionDesignTokens.Foreground.secondary)
                Spacer()
                HStack(spacing: FusionDesignTokens.Spacing.xs) {
                    Circle()
                        .fill(wireframeDisplayColor)
                        .frame(width: FusionDesignTokens.Size.indicatorMedium, height: FusionDesignTokens.Size.indicatorMedium)
                    Text(layoutManager.wireframeColor.displayName)
                        .font(FusionDesignTokens.Typography.hudValue)
                        .foregroundStyle(FusionDesignTokens.Foreground.primary)
                }
            }
            
            // Description
            if layoutManager.lastViolationCode > 0 {
                Divider()
                    .background(FusionDesignTokens.Foreground.divider)
                
                Text(violationDescription)
                    .font(FusionDesignTokens.Typography.hudDescription)
                    .foregroundStyle(FusionDesignTokens.Foreground.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minWidth: FusionDesignTokens.Size.hudMinWidth)
    }
    
    private var violationColor: Color {
        switch layoutManager.lastViolationCode {
        case 0:
            return FusionDesignTokens.Status.normal
        case 1...3:
            return FusionDesignTokens.Status.warning
        case 4...6:
            return FusionDesignTokens.Status.critical
        default:
            return FusionDesignTokens.Status.inactive
        }
    }
    
    private var violationCodeDisplay: String {
        if layoutManager.lastViolationCode == 0 {
            return "PASS"
        } else {
            return "C-\(String(format: "%03d", layoutManager.lastViolationCode))"
        }
    }
    
    private var terminalStateDisplay: String {
        switch layoutManager.lastTerminalState {
        case 0:
            return "CALORIE"
        case 1:
            return "CURE"
        case 2:
            return "REFUSED"
        default:
            return "UNKNOWN"
        }
    }
    
    private var terminalStateColor: Color {
        switch layoutManager.lastTerminalState {
        case 0:
            return FusionDesignTokens.Status.normal
        case 1:
            return FusionDesignTokens.Status.info
        case 2:
            return FusionDesignTokens.Status.critical
        default:
            return FusionDesignTokens.Status.inactive
        }
    }
    
    private var residualColor: Color {
        let residual = layoutManager.lastClosureResidual
        if residual < 0.1 {
            return FusionDesignTokens.Status.normal
        } else if residual < 1.0 {
            return FusionDesignTokens.Status.warning
        } else {
            return FusionDesignTokens.Status.critical
        }
    }
    
    private var wireframeDisplayColor: Color {
        let rgba = layoutManager.wireframeColor.rgba
        return Color(
            red: Double(rgba[0]),
            green: Double(rgba[1]),
            blue: Double(rgba[2]),
            opacity: Double(rgba[3])
        )
    }
    
    private var violationDescription: String {
        switch layoutManager.lastViolationCode {
        case 1:
            return "C-001: Plasma current exceeds constitutional limit (>20 MA)"
        case 2:
            return "C-002: Magnetic field exceeds constitutional limit (>15 T)"
        case 3:
            return "C-003: Electron density exceeds constitutional limit (>5×10²⁰ m⁻³)"
        case 4:
            return "C-004: NaN detected in telemetry (unsafe state)"
        case 5:
            return "C-005: Negative value detected (unphysical state)"
        case 6:
            return "C-006: Combined constraint violation (stress >2.5)"
        default:
            return ""
        }
    }
}

#Preview {
    ZStack {
        Color.black
        ConstitutionalHUD(layoutManager: {
            let manager = CompositeLayoutManager()
            manager.lastViolationCode = 4
            manager.lastTerminalState = 2
            manager.lastClosureResidual = 1.234567
            manager.wireframeColor = .critical
            return manager
        }())
    }
}
