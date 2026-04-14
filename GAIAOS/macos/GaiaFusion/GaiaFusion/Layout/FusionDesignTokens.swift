import SwiftUI

/// Design tokens for visual consistency across GaiaFusion UI
/// Centralizes colors, spacing, typography for maintainability
enum FusionDesignTokens {
    // MARK: - Colors
    
    /// Background colors (dark HUD aesthetic, high contrast basis)
    enum Background {
        /// Primary background gradient colors (neutral dark, not blue-tinted)
        static let gradientTop = Color(red: 0.10, green: 0.11, blue: 0.13)
        static let gradientMid = Color(red: 0.12, green: 0.13, blue: 0.15)
        static let gradientBottom = Color(red: 0.10, green: 0.11, blue: 0.13)
        
        /// Metal viewport clear color (matches gradient for consistency)
        static let metalViewport = MTLClearColor(
            red: 0.10,
            green: 0.11,
            blue: 0.13,
            alpha: 1.0
        )
        
        /// Metal viewport clear color (fallback, no device)
        static let metalViewportFallback = MTLClearColor(
            red: 0.12,
            green: 0.13,
            blue: 0.15,
            alpha: 1.0
        )
        
        /// Overlay backgrounds (darker for better contrast with bright status colors)
        static let hudOverlay = Color.black.opacity(0.90)
        static let modeIndicator = Color.black.opacity(0.80)
    }
    
    /// Foreground colors (high contrast on dark backgrounds)
    enum Foreground {
        static let primary = Color.white
        static let secondary = Color.white.opacity(0.75)  // High contrast labels
        static let divider = Color.white.opacity(0.35)  // Visible dividers
        static let muted = Color.white.opacity(0.85)  // Clear descriptions
    }
    
    /// Status colors (high contrast for dark backgrounds)
    enum Status {
        static let normal = Color(red: 0.3, green: 0.9, blue: 0.4)  // Bright green
        static let warning = Color(red: 1.0, green: 0.8, blue: 0.0)  // Bright yellow
        static let critical = Color(red: 1.0, green: 0.2, blue: 0.2)  // Bright red
        static let info = Color(red: 0.4, green: 0.8, blue: 1.0)  // Bright cyan (NOT dark blue)
        static let inactive = Color(red: 0.6, green: 0.6, blue: 0.6)  // Light gray
    }
    
    // MARK: - Typography
    
    enum Typography {
        /// HUD header text
        static let hudHeader = Font.system(size: 13, weight: .bold, design: .monospaced)
        
        /// HUD body text (labels)
        static let hudLabel = Font.system(size: 11, weight: .medium, design: .monospaced)
        
        /// HUD body text (values)
        static let hudValue = Font.system(size: 11, weight: .bold, design: .monospaced)
        
        /// HUD description text
        static let hudDescription = Font.system(size: 10, design: .monospaced)
        
        /// Layout mode indicator
        static let modeIndicator = Font.system(size: 11, weight: .semibold, design: .monospaced)
        
        /// Loading/status captions
        static let caption = Font.caption
    }
    
    // MARK: - Spacing
    
    enum Spacing {
        /// Tight spacing (4pt)
        static let xxs: CGFloat = 4
        
        /// Extra small spacing (6pt)
        static let xs: CGFloat = 6
        
        /// Small spacing (8pt)
        static let sm: CGFloat = 8
        
        /// Default spacing (10pt)
        static let md: CGFloat = 10
        
        /// Medium spacing (12pt)
        static let base: CGFloat = 12
        
        /// Medium-large spacing (14pt)
        static let lg: CGFloat = 14
        
        /// Large spacing (16pt)
        static let xl: CGFloat = 16
        
        /// Extra large spacing (20pt)
        static let xxl: CGFloat = 20
        
        /// Extra extra large spacing (24pt)
        static let xxxl: CGFloat = 24
        
        /// Edge padding (40pt)
        static let edge: CGFloat = 40
        
        /// Top inset for HUD (60pt, avoids traffic lights)
        static let hudTop: CGFloat = 60
    }
    
    // MARK: - Sizing
    
    enum Size {
        /// Small indicator dot
        static let indicatorSmall: CGFloat = 8
        
        /// Medium indicator dot
        static let indicatorMedium: CGFloat = 10
        
        /// Large indicator dot
        static let indicatorLarge: CGFloat = 12
        
        /// HUD minimum width
        static let hudMinWidth: CGFloat = 280
        
        /// Corner radius for HUD
        static let cornerRadius: CGFloat = 12
    }
    
    // MARK: - Opacity
    
    enum Opacity {
        /// Dashboard focus mode (metal ambient behind webview per spec)
        static let metalDashboard: Double = 0.10
        
        /// Geometry focus mode (metal fully visible)
        static let metalGeometry: Double = 1.0
        
        /// Split view mode (metal fully visible)
        static let metalSplit: Double = 1.0
        
        /// Constitutional alarm mode (metal fully visible)
        static let metalAlarm: Double = 1.0
        
        /// Dashboard focus mode (webview fully visible)
        static let webviewDashboard: Double = 1.0
        
        /// Geometry focus mode (webview hidden)
        static let webviewGeometry: Double = 0.0
        
        /// Split view mode (webview dimmed per spec)
        static let webviewSplit: Double = 0.85
        
        /// Constitutional alarm mode (webview dimmed)
        static let webviewAlarm: Double = 0.85
        
        /// Shadow opacity
        static let shadow: Double = 0.5
    }
    
    // MARK: - Animation
    
    enum Animation {
        /// Layout transition duration
        static let layoutTransition: TimeInterval = 0.35
        
        /// Mode indicator fade duration
        static let modeIndicatorFade: TimeInterval = 0.5
        
        /// Mode indicator display duration
        static let modeIndicatorDisplay: TimeInterval = 2.0
    }
}
