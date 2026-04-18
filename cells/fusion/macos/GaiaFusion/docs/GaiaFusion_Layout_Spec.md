# GaiaFusion Layout Specification — Authoritative UI Contract

**Authority**: GAMP 5, EU Annex 11, FDA 21 CFR Part 11  
**Version**: 1.0  
**Last Updated**: 2026-04-14

---

## Section 1: ZStack Z-Level Architecture

The GaiaFusion composite viewport is a single `ZStack` containing 6 layers. Each layer has a fixed z-index, opacity source, and hit-testing rule.

| Z-Index | Component | Opacity Source | Hit-Testing Rule |
|---------|-----------|----------------|------------------|
| 0 | FusionWebShellBackdrop | 1.0 (always) | false (always) |
| 1 | FusionMetalViewportView | layoutManager.metalOpacity | mode == .geometryFocus |
| 2 | FusionWebView (WKWebView) | layoutManager.webviewOpacity | mode != .geometryFocus |
| 5 | LayoutModeIndicator | conditional (mode != .dashboardFocus ? 1.0 : 0.0) | false (always) |
| 10 | ConstitutionalHUD | layoutManager.constitutionalHudVisible ? 1.0 : 0.0 | true (strip content only) |
| 20 | SplashOverlay | coordinator.splashOverlayVisible ? 1.0 : 0.0 | true (blocks all) |

**Critical rules:**
- Opacity and hit-testing must always be set as a pair
- Z-indices are not negotiable — reordering breaks the visual contract
- Background color for Z=2 (WKWebView) must be `Color.clear` to allow Metal passthrough

---

## Section 2: Window Structure

```
NSWindow
└── VStack (full window)
    ├── TopStatusBar                        (height: 36pt, outside ZStack)
    └── HStack (fills remaining height)
        ├── FusionControlSidebar            (width: 285pt, fixed — LEFT SIBLING)
        └── CompositeViewportStack          ← THIS IS THE ZSTACK
            ├── Z=0  FusionWebShellBackdrop
            ├── Z=1  FusionMetalViewportView (GeometryReader wrapper)
            ├── Z=2  FusionWebView           (WKWebView)
            ├── Z=5  LayoutModeIndicator     (VStack+Spacer wrapper)
            ├── Z=10 ConstitutionalHUD       (VStack+Spacer wrapper)
            └── Z=20 SplashOverlay           (conditional)
```

**Non-negotiable:**
- `FusionControlSidebar` is an HStack sibling of `CompositeViewportStack`
- It is NOT a child of the ZStack
- It is NOT a Z-layer overlay inside the ZStack

---

## Section 3: Layout Modes and Opacity Table

Three valid modes exist. A fourth mode (`splitView`) was permanently removed for regulatory compliance.

| Mode | metalOpacity | webviewOpacity | Description |
|------|--------------|----------------|-------------|
| dashboardFocus | 0.10 | 1.0 | Telemetry monitoring primary, wireframe ambient |
| geometryFocus | 1.0 | 0.0 | 3D wireframe primary, dashboard hidden |
| constitutionalAlarm | 1.0 | 0.85 | Forced by WASM substrate, red wireframe, HUD overlay |

**Deleted mode:**
- `splitView` — removed per 21 CFR Part 11 §11.10(d)(g). Two layers accepting input simultaneously creates unattributable audit trail.

---

## Section 4: GeometryReader Pattern for Metal Viewport

`FusionMetalViewportView` must be wrapped in `GeometryReader` to receive correct viewport dimensions:

```swift
GeometryReader { geometry in
    FusionMetalViewportView(playback: metalPlayback)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .onAppear {
            metalPlayback.updateDrawableSize(geometry.size)
        }
        .onChange(of: geometry.size) { _, newSize in
            metalPlayback.updateDrawableSize(newSize)
        }
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
.opacity(layoutManager.metalOpacity)
.allowsHitTesting(layoutManager.currentMode == .geometryFocus)
.zIndex(1)
```

**Why this is mandatory:**
- GeometryReader gives actual available space after sidebar
- `.onAppear` ensures initial size is sent to Metal renderer
- `.onChange` handles window resize
- SwiftUI is declarative — no manual resize handlers needed

---

## Section 5: VStack+Spacer Pattern for Z=5 and Z=10

**Problem:** A view with `maxHeight: .infinity` claims full viewport height for hit-testing even if it visually occupies only 44pt. This swallows all taps across the entire viewport.

**Solution:** Wrap content in VStack+Spacer:

### Z=5 LayoutModeIndicator (bottom-anchored):
```swift
VStack(spacing: 0) {
    Spacer(minLength: 0)
        .allowsHitTesting(false)
    LayoutModeIndicator(mode: layoutManager.currentMode)
        .frame(maxWidth: .infinity)  // maxWidth only — NOT maxHeight
        .padding(.bottom, 12)
        .allowsHitTesting(false)
        .opacity(layoutManager.currentMode != .dashboardFocus ? 1 : 0)
        .animation(.easeInOut, value: layoutManager.currentMode)
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
.allowsHitTesting(false)
.zIndex(5)
```

### Z=10 ConstitutionalHUD (top-anchored):
```swift
VStack(spacing: 0) {
    ConstitutionalHUD()
        .frame(maxWidth: .infinity)  // maxWidth only — NOT maxHeight
        .allowsHitTesting(true)
    Spacer(minLength: 0)
        .allowsHitTesting(false)
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
.opacity(layoutManager.constitutionalHudVisible ? 1 : 0)
.animation(.easeInOut, value: layoutManager.constitutionalHudVisible)
.zIndex(10)
```

**Key principle:** The Spacer pushes content to its edge. The outer container's `allowsHitTesting(false)` ensures the dead air doesn't intercept taps meant for lower layers.

---

## Section 6: Forbidden Patterns

Every item below has been done by a previous agent and must never be repeated:

1. **DO NOT move FusionControlSidebar inside the ZStack**
   - It belongs in the parent HStack as a sibling
   - This is architecturally non-negotiable

2. **DO NOT add `maxHeight: .infinity` to content views at Z=5 or Z=10**
   - Use VStack+Spacer wrapper instead
   - See Section 5 for correct pattern

3. **DO NOT hardcode pixel widths on ZStack children**
   - No `frame(width: 620)` or similar
   - Use `maxWidth: .infinity` and let SwiftUI calculate actual width

4. **DO NOT write manual resize event handlers**
   - SwiftUI is declarative
   - GeometryReader + `.onChange(of: geometry.size)` handles this

5. **DO NOT set `allowsHitTesting(true)` on a view with `opacity: 0`**
   - These must always move together
   - Invisible views should not intercept taps

6. **DO NOT re-implement splitView under any name**
   - Any mode with two interactive layers at non-zero opacity is prohibited
   - Regulatory requirement, not optional

---

## Section 7: Required Window Structure Code Template

```swift
// In GaiaFusionApp.swift or equivalent top-level view
var body: some View {
    VStack(spacing: 0) {
        // Top status bar (36pt)
        TopStatusBar(...)
            .frame(height: 36)
        
        // Main content area
        HStack(spacing: 0) {
            // Left sidebar (285pt, OUTSIDE ZStack)
            FusionControlSidebar(...)
                .frame(width: 285)
            
            // Composite viewport (ZStack, fills remaining width)
            CompositeViewportStack(
                layoutManager: layoutManager,
                metalPlayback: metalPlayback,
                coordinator: coordinator,
                serverPort: 8910
            )
        }
    }
}
```

---

## Section 8: Compliance Requirements

**GAMP 5 / EU Annex 11 / FDA 21 CFR Part 11:**
- Every operator action must be auditable
- Unambiguous input target required for all interactions
- Authorization checks before state-changing actions
- Audit log entries are write-once, never modified

**Why splitView was removed:**
- Two layers accepting input simultaneously = ambiguous tap target
- Audit log cannot reconstruct which layer was intended target
- Violates §11.10(d) (limiting access) and §11.10(g) (authority checks)

---

## Section 9: Verification Criteria

After implementing this spec, verify:

1. **Structure:** Sidebar is HStack sibling, not ZStack child
2. **Z-levels:** All 6 layers present at correct indices
3. **Opacity:** Matches mode table (Section 3)
4. **Hit-testing:** Matches rules (Section 1)
5. **GeometryReader:** Metal viewport receives correct dimensions
6. **VStack+Spacer:** Z=5 and Z=10 don't swallow taps
7. **Background:** WKWebView is Color.clear
8. **Modes:** Only 3 modes exist (dashboardFocus, geometryFocus, constitutionalAlarm)
9. **Centering:** Metal torus centered at ~505pt from left edge (1011pt window)

---

## Appendix: Historical Context

This spec was created after multiple agent runs produced broken architectures:
- FusionControlSidebar moved inside ZStack (broke sidebar visibility)
- FusionWebView removed (broke dashboard)
- maxHeight: .infinity on Z=5/Z=10 (swallowed all taps)
- splitView kept despite audit trail violations

This document is the authoritative fix. Follow it exactly.
