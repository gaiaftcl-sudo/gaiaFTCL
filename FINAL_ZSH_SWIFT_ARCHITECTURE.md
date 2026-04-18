# Mac Qualification — Zsh + Swift Architecture (Final)

**Branch:** `feat/mac-qualification-swift-only`  
**Date:** 2026-04-16  
**Patents:** USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie

---

## ✅ STATE: CALORIE — Modern Zsh + Swift (Not 2007 Bash)

---

## Why Zsh (Not Bash 3.2)

**macOS ships Bash 3.2.x (2007):**
- ❌ No associative arrays (`declare -A`)
- ❌ No recursive globbing (`**/*.swift`)
- ❌ Incomplete UTF-8 support
- ❌ GPLv3 license issue (Apple cannot ship Bash 5.x)
- ❌ 20-year-old patterns

**Zsh (macOS default since Catalina 2019):**
- ✅ Associative arrays (`typeset -A`)
- ✅ Recursive globbing (`**` native)
- ✅ Advanced parameter expansion (`${var:s/old/new/}`)
- ✅ Asynchronous prompt updates
- ✅ Superior tab completion
- ✅ Global aliases
- ✅ MIT-licensed
- ✅ Modern (2026)

**Result:** Use **zsh** for Mac. Bash 3.2 is obsolete.

---

## Architecture

```
cells/fusion/macos/
├── GaiaFusion/          ← MacFusion app (Swift)
├── MacHealth/           ← MacHealth app (Swift)
├── TestRobot/           ← PQ Metal GPU tests (Swift)
├── CleanCloneTest/      ← Test orchestrator (Swift, calls zsh)
└── FusionSidecarHost/   ← Sidecar (Swift)

scripts/
├── gamp5_iq.sh          ← Canonical IQ (zsh, 437 lines)
├── gamp5_oq.sh          ← Canonical OQ (zsh, 327 lines)
└── gamp5_pq.sh          ← Canonical PQ (zsh, 395 lines)
```

---

## Canonical Scripts (Zsh, Production-Ready)

All three scripts use **modern zsh features**:

### scripts/gamp5_iq.sh (437 lines)
- Shebang: `#!/usr/bin/env zsh`
- Zsh arrays for old wallet detection
- Associative arrays for toolchain checks
- macOS dialogs via `osascript`
- Hardware UUID → secp256k1 wallet
- Receipt: `evidence/iq/iq_receipt.json`

### scripts/gamp5_oq.sh (327 lines)
- Shebang: `#!/usr/bin/env zsh`
- Zsh arrays for test suite management
- Hardcoded long-running test exclusions
- Verifies IQ receipt first
- Receipt: `evidence/oq/oq_receipt.json`

### scripts/gamp5_pq.sh (395 lines)
- Shebang: `#!/usr/bin/env zsh`
- Verifies OQ receipt first
- Metal GPU hard FAIL
- Calls TestRobot (Swift)
- FFI stress: 100 frames
- Build time < 180s
- Receipt: `evidence/pq/pq_receipt.json`

**Run:**
```zsh
zsh scripts/gamp5_iq.sh --cell both
zsh scripts/gamp5_oq.sh --cell both
zsh scripts/gamp5_pq.sh --cell both
```

---

## Swift Executables (Call Zsh)

### CleanCloneTest (Swift)

**Location:** `cells/fusion/macos/CleanCloneTest/`

**How it calls zsh:**
```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = ["zsh", "scripts/gamp5_iq.sh", "--cell", "both"]
// NOT ["bash", ...] — always zsh
```

**Build:**
```zsh
cd cells/fusion/macos/CleanCloneTest
swift build
```

**Run:**
```zsh
.build/debug/CleanCloneTest
```

---

### TestRobot (Swift)

**Location:** `cells/fusion/macos/TestRobot/`

**What it does:**
- Metal GPU offscreen render (both apps)
- Pixel hash
- FFI stress (100 frames)
- Unified `TESTROBOT_RECEIPT.json`

**Build:**
```zsh
cd cells/fusion/macos/TestRobot
swift build
```

**Run:**
```zsh
.build/debug/TestRobot
```

---

## Cursor Rule

**File:** `cells/fusion/.cursor/rules/mac-qualification-zsh-swift.mdc`

**Hard rules:**
1. **New Mac code:** Swift executables only
2. **Shell out:** Use **zsh** (not bash) via `Process()`
3. **Documentation:** Say "zsh" not "bash"
4. **Exception:** `scripts/gamp5_*.sh` (canonical, zsh, production-ready)

**Forbidden:**
- ❌ New `.sh` scripts with `#!/bin/bash`
- ❌ Calling `bash` in Swift `Process()`
- ❌ "bash" in Mac documentation
- ❌ Bash 3.2 patterns

**Required:**
- ✅ Swift executables
- ✅ Call `zsh` when shelling out
- ✅ "zsh" in documentation
- ✅ Modern zsh features (associative arrays, `**` glob)

---

## Remote Mesh Exception

**Deploy scripts on remote mesh (Hetzner/Netcup)** may use:
- POSIX `sh` (portable)
- Bash 5.x (if available)
- SSH remote execution

**Deploy ≠ qualification.** Remote nodes don't have zsh guarantees.

---

## Summary

| Context | Tool | Shell | Rationale |
|---------|------|-------|-----------|
| Mac new code | **Swift** | N/A | Type-safe, compiled |
| Mac shell-out | **Swift** | **zsh** | Modern, MIT-licensed |
| Canonical IQ/OQ/PQ | N/A | **zsh** | Production-ready (437+327+395 lines) |
| Remote mesh | N/A | POSIX sh / Bash 5.x | No zsh on remote nodes |

---

## Receipts (7 total)

**MacFusion (3):**
- `cells/fusion/macos/GaiaFusion/evidence/iq/iq_receipt.json`
- `cells/fusion/macos/GaiaFusion/evidence/oq/oq_receipt.json`
- `cells/fusion/macos/GaiaFusion/evidence/pq/pq_receipt.json`

**MacHealth (3):**
- `cells/fusion/macos/MacHealth/evidence/iq/iq_receipt.json`
- `cells/fusion/macos/MacHealth/evidence/oq/oq_receipt.json`
- `cells/fusion/macos/MacHealth/evidence/pq/pq_receipt.json`

**Unified (1):**
- `evidence/TESTROBOT_RECEIPT.json`

---

## Run Clean Clone Test

```zsh
cd cells/fusion/macos/CleanCloneTest
swift build
.build/debug/CleanCloneTest
```

**Expected output:**
```
STATE: CALORIE — Clean Clone Test PASS
  ✅ IQ: PASS (scripts/gamp5_iq.sh - zsh)
  ✅ OQ: PASS (scripts/gamp5_oq.sh - zsh)
  ✅ PQ: PASS (scripts/gamp5_pq.sh + TestRobot)
  ✅ All receipts: Present and valid (7/7)
```

---

**No bash on Mac. Zsh + Swift only. It's 2026, not 2007.**

Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie
