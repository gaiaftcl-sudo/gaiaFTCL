# GaiaFusion Design System

**Version:** 1.0  
**Last Updated:** 2026-04-12  
**Token File:** `GaiaFusion/Layout/FusionDesignTokens.swift`

---

## Overview

The GaiaFusion design system provides a centralized, semantic token system for all UI styling. This ensures visual consistency, maintainability, and professional polish across the composite Metal + WebView + HUD interface.

---

## Using Design Tokens

### Import
```swift
import SwiftUI
// FusionDesignTokens is automatically available in the GaiaFusion module
```

### Examples

#### Background Colors
```swift
// Backdrop gradient
LinearGradient(
    colors: [
        FusionDesignTokens.Background.gradientTop,
        FusionDesignTokens.Background.gradientMid,
        FusionDesignTokens.Background.gradientBottom
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

// Metal viewport
view.clearColor = FusionDesignTokens.Background.metalViewport

// HUD overlay
.background(FusionDesignTokens.Background.hudOverlay)
```

#### Typography
```swift
// HUD header
Text("CONSTITUTIONAL STATE")
    .font(FusionDesignTokens.Typography.hudHeader)

// Labels and values
Text("Violation:")
    .font(FusionDesignTokens.Typography.hudLabel)
Text("PASS")
    .font(FusionDesignTokens.Typography.hudValue)
```

#### Spacing
```swift
// Standard padding
.padding(FusionDesignTokens.Spacing.xl)

// Vertical stack spacing
VStack(spacing: FusionDesignTokens.Spacing.base) {
    // ...
}

// Safe area padding (avoid window controls)
.padding(.top, FusionDesignTokens.Spacing.hudTop)
```

#### Status Colors
```swift
// Violation severity
Circle()
    .fill(violationLevel < 3 
        ? FusionDesignTokens.Status.normal 
        : FusionDesignTokens.Status.critical)

// Terminal state
.foregroundStyle(state == "CALORIE" 
    ? FusionDesignTokens.Status.normal 
    : FusionDesignTokens.Status.info)
```

---

## Token Reference

### Colors

#### Background
| Token | Value | Usage |
|-------|-------|-------|
| `gradientTop` | RGB(0.12, 0.14, 0.18) | Backdrop gradient start |
| `gradientMid` | RGB(0.14, 0.16, 0.20) | Backdrop gradient middle |
| `gradientBottom` | RGB(0.12, 0.14, 0.18) | Backdrop gradient end |
| `metalViewport` | RGB(0.12, 0.14, 0.18) | Metal layer clear color |
| `metalViewportFallback` | RGB(0.15, 0.17, 0.20) | No-device fallback |
| `hudOverlay` | Black @ 85% | Constitutional HUD |
| `modeIndicator` | Black @ 75% | Layout mode badge |

#### Foreground
| Token | Value | Usage |
|-------|-------|-------|
| `primary` | White | Primary text |
| `secondary` | System secondary | Labels, captions |
| `divider` | White @ 30% | Divider lines |
| `muted` | White @ 80% | Descriptions |

#### Status
| Token | Color | Usage |
|-------|-------|-------|
| `normal` | Green | Pass, healthy, CALORIE |
| `warning` | Yellow | Caution, medium violations |
| `critical` | Red | Alarms, high violations, REFUSED |
| `info` | Blue | Informational, CURE |
| `inactive` | Gray | Disabled, unknown |

---

### Typography

| Token | Spec | Usage |
|-------|------|-------|
| `hudHeader` | 13pt bold mono | HUD section headers |
| `hudLabel` | 11pt medium mono | HUD field labels |
| `hudValue` | 11pt bold mono | HUD data values |
| `hudDescription` | 10pt mono | Violation descriptions |
| `modeIndicator` | 11pt semibold mono | Layout mode badge |
| `caption` | System caption | Loading messages |

---

### Spacing (8pt Grid)

| Token | Value | Usage |
|-------|-------|-------|
| `xxs` | 4pt | Tight inline spacing |
| `xs` | 6pt | Extra-small gaps |
| `sm` | 8pt | Small spacing |
| `md` | 10pt | Default spacing |
| `base` | 12pt | Base vertical rhythm |
| `lg` | 14pt | Medium-large gaps |
| `xl` | 16pt | Large padding |
| `xxl` | 20pt | Extra-large spacing |
| `xxxl` | 24pt | Section padding |
| `edge` | 40pt | Edge safety margin |
| `hudTop` | 60pt | Below traffic lights |

---

### Sizing

| Token | Value | Usage |
|-------|-------|-------|
| `indicatorSmall` | 8pt | Mode indicator dot |
| `indicatorMedium` | 10pt | Wireframe color dot |
| `indicatorLarge` | 12pt | Violation status dot |
| `hudMinWidth` | 280pt | Constitutional HUD |
| `cornerRadius` | 12pt | Rounded corners |

---

### Opacity (Layout Modes)

| Token | Value | Usage |
|-------|-------|-------|
| `metalDashboard` | 0.15 | Metal barely visible |
| `metalGeometry` | 1.0 | Metal fully visible |
| `metalSplit` | 1.0 | Metal fully visible |
| `metalAlarm` | 1.0 | Metal fully visible |
| `webviewDashboard` | 1.0 | Dashboard fully visible |
| `webviewGeometry` | 0.0 | Dashboard hidden |
| `webviewSplit` | 1.0 | Dashboard fully visible |
| `webviewAlarm` | 0.7 | Dashboard dimmed |
| `shadow` | 0.5 | Shadow effects |

---

### Animation

| Token | Value | Usage |
|-------|-------|-------|
| `layoutTransition` | 0.35s | Mode switching |
| `modeIndicatorFade` | 0.5s | Badge fade out |
| `modeIndicatorDisplay` | 2.0s | Badge display time |

---

## Modification Guidelines

### Adding a New Token
1. Add to appropriate enum in `FusionDesignTokens.swift`
2. Use semantic naming (describe purpose, not value)
3. Document usage in comment
4. Update this DESIGN_SYSTEM.md reference

### Changing a Token Value
1. Modify value in `FusionDesignTokens.swift`
2. Rebuild: `swift build`
3. Verify visually in all affected layouts
4. Update this reference if semantics change

### DO NOT
- ❌ Add inline color/spacing values in UI code
- ❌ Create duplicate token systems
- ❌ Use hardcoded magic numbers
- ❌ Mix semantic and literal naming

### DO
- ✅ Use tokens for all colors, spacing, typography
- ✅ Add new tokens when needed
- ✅ Keep semantic naming
- ✅ Document usage

---

## Migration Checklist

When refactoring existing UI code:

- [ ] Replace inline `Color(red: _, green: _, blue: _)` with tokens
- [ ] Replace hardcoded padding values with spacing tokens
- [ ] Replace `.font(.system(size: _, weight: _, design: _))` with typography tokens
- [ ] Replace opacity values with semantic tokens
- [ ] Replace size values (frame widths/heights) with sizing tokens
- [ ] Verify no magic numbers remain in Layout/ directory

---

**File:** `/Users/richardgillespie/Documents/FoT8D/cells/fusion/macos/GaiaFusion/DESIGN_SYSTEM.md`
