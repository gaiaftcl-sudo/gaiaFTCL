# Runtime Verification Protocol — Priority 2

**Date:** 2026-04-15  
**Status:** BLOCKED (Requires Cell-Operator Visual Verification)

## Verification Sequence

Launch the application:
```bash
cd /Users/richardgillespie/Documents/FoT8D/cells/fusion/macos/GaiaFusion
open ./.build/debug/GaiaFusion.app
```

## Check 1: Launch — No Crash ✅ (Completed Yesterday)
**Pass Condition:** App reaches splash screen, Console.app shows zero `dispatch_assert_queue` entries  
**Status:** PASS (confirmed April 14)

## Check 2: Metal Torus Centered
**Pass Condition:** Wireframe torus must be centered in full viewport, not pushed to left half  
**What to Look For:** Torus occupies center of window, not confined to left 60%  
**If FAIL:** Layout issue in `CompositeViewportStack.swift` - GeometryReader not wired correctly or sidebar inside ZStack

## Check 3: Next.js Right Panel Visible
**Pass Condition:** Cell grid, plant controls, and swap panel visible on right side of viewport  
**What to Look For:** Right side shows fusion-s4 dashboard content (not blank/black)  
**If FAIL:** FusionWebView at Z=2 missing or has wrong opacity

## Check 4: Cmd+1 and Cmd+2 Work
**Pass Condition:** 
- Cmd+1: Metal opacity → 10% (dashboard focus)
- Cmd+2: Metal opacity → 100% (geometry focus)  
**What to Look For:** Visible opacity changes when pressing keyboard shortcuts  
**If FAIL:** `FusionLayoutManager` isn't `@Observable` or keyboard shortcuts aren't checking `keyboardShortcutsEnabled`

## Check 5: Force `.tripped` → Shortcuts Lock
**Pass Condition:** In `.tripped` state, Cmd+1/Cmd+2 must do nothing  
**How to Test:**
1. Use debug menu or temporarily hardcode state to `.tripped`
2. Press Cmd+2
3. Mode must NOT change  
**If FAIL:** Defect 1 fix didn't take (`keyboardShortcutsEnabled` logic in `applyForcedMode`)

## Check 6: Force `.constitutionalAlarm` → HUD Appears, Shortcuts Lock
**Pass Condition:**
- ConstitutionalHUD slides in from top
- Cmd+1/Cmd+2 do nothing
- Metal at 100% opacity, WKWebView at 85%  
**How to Test:**
1. Set plant state to `.constitutionalAlarm`
2. Verify HUD visibility
3. Press Cmd+1/Cmd+2 (should be ignored)  
**If FAIL:** `applyForcedMode()` logic or `keyboardShortcutsEnabled` flag issue

## Check 7: Plasma Particles in RUNNING Only
**Pass Condition:**
- State `.running`: 500 plasma particles appear (blue→cyan→yellow→white gradient)
- State `.idle`: Particles disappear (buffer cleared, not just faded)  
**Critical Verification:** Buffer Re-Population
- Test sequence: IDLE → RUNNING (particles appear) → IDLE (buffer cleared) → RUNNING again
- Verify particles reappear from **fresh buffer** (not stale data)  
**What to Look For:**
- Helical trajectories following field lines
- Temperature-driven color gradient
- Clean disappearance/reappearance cycle  
**If FAIL:** `enable_plasma()` doesn't call `init_plasma_particles(500)` or equivalent buffer repopulation

## Screenshot Requirements

For each passing check, capture screenshot and save to:
```
cells/fusion/macos/GaiaFusion/docs/images/runtime_check_N.png
```

Where N = 2-7 for each check.

## Completion Document

After all checks complete, create:
```
cells/fusion/macos/GaiaFusion/RUNTIME_VERIFICATION_COMPLETE_20260415.md
```

With format:
```markdown
# Runtime Verification Complete

**Date:** 2026-04-15  
**Status:** [CALORIE|PARTIAL|REFUSED]

## Results Summary
- Check 1: ✅ PASS
- Check 2: [✅ PASS | ❌ FAIL with details]
- Check 3: [✅ PASS | ❌ FAIL with details]
... etc

## Screenshots
- ![Check 2](docs/images/runtime_check_2.png)
... etc

## Issues Found
[List any failures with diagnostic info]
```

## BLOCKED Status

**Reason:** Visual verification requires Cell-Operator presence at GUI console  
**Missing Capability:** Agent cannot launch GUI apps and capture screenshots  
**Witness:** Application builds successfully (exit 0) but runtime checks require human operator  
**Cell-Operator Action Required:** Run checks 2-7 above and document results

**Norwich. S⁴ serves C⁴.**
