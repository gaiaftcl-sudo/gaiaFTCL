# Canonical Zsh Scripts — Mac Qualification

**Branch:** `feat/mac-qualification-swift-only`  
**Date:** 2026-04-16  
**Patents:** USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie

---

## ✅ STATE: CALORIE — Modern Zsh (Not 20-Year-Old Bash)

### Why Zsh on macOS

**Licensing:** Zsh is MIT-licensed; Bash 5.x is GPLv3 (Apple cannot ship).  
**macOS ships:** Bash 3.2.x (2007) — lacks associative arrays, recursive globbing, modern UTF-8.  
**Zsh advantages:**
- ✅ Associative arrays (`typeset -A`)
- ✅ Recursive globbing (`**/*.swift`)
- ✅ Advanced parameter expansion (`${var:s/old/new/}`)
- ✅ Asynchronous prompt updates
- ✅ Superior tab completion
- ✅ Global aliases

**Modern pattern:** Use zsh for Mac terminal work. POSIX `sh` or Bash 5.x (Homebrew) for remote mesh nodes.

---

## Canonical Scripts (Zsh, Production-Ready)

### scripts/gamp5_iq.sh (437 lines, zsh)

**Installation Qualification:**
- Shebang: `#!/usr/bin/env zsh`
- macOS dialogs via `osascript`
- Zsh array handling for old wallet detection
- Hardware UUID → secp256k1 wallet
- Trash API via Finder (recoverable)
- Toolchain verification: macOS ≥13, Metal GPU, Swift, Rust, OpenSSL, Python
- Receipt: `evidence/iq/iq_receipt.json`

**Run:**
```zsh
zsh scripts/gamp5_iq.sh --cell both
```

---

### scripts/gamp5_oq.sh (327 lines, zsh)

**Operational Qualification:**
- Shebang: `#!/usr/bin/env zsh`
- Verifies IQ receipt exists and is PASS
- Zsh arrays for test suite management
- Hardcoded long-running test exclusions (24h, 10min tests)
- Receipt: `evidence/oq/oq_receipt.json`

**Run:**
```zsh
zsh scripts/gamp5_oq.sh --cell both
```

---

### scripts/gamp5_pq.sh (395 lines, zsh)

**Performance Qualification:**
- Shebang: `#!/usr/bin/env zsh`
- Verifies OQ receipt first
- Metal GPU hard FAIL if nil
- Calls TestRobot (Swift) for Metal PQ
- FFI stress: 100 frames under GPU
- Build time check: < 180s
- Receipt: `evidence/pq/pq_receipt.json`

**Run:**
```zsh
zsh scripts/gamp5_pq.sh --cell both
```

---

## Swift Executables (New Mac Code)

All NEW Mac code is **Swift executables** that call zsh when needed:

### CleanCloneTest (Swift)

**Location:** `cells/fusion/macos/CleanCloneTest/`

**Build:**
```zsh
cd cells/fusion/macos/CleanCloneTest
swift build
```

**Run:**
```zsh
.build/debug/CleanCloneTest
```

**What it does:**
1. Creates test directory via `FileManager`
2. Clones repo via `Process()` running `git`
3. Builds TestRobot via `Process()` running `swift`
4. Runs IQ via `Process()` running **`zsh`** `scripts/gamp5_iq.sh`
5. Runs OQ via `Process()` running **`zsh`** `scripts/gamp5_oq.sh`
6. Runs PQ via `Process()` running **`zsh`** `scripts/gamp5_pq.sh`
7. Verifies receipts via `FileManager`

**Key:** Swift executable calls **zsh** (not bash) when shelling out.

---

## Cursor Rule

**File:** `cells/fusion/.cursor/rules/mac-qualification-no-bash.mdc`

**Hard rule:**
- All NEW Mac code: Swift executables
- Shell out via `Process()` using **zsh** (not bash)
- Exception: `scripts/gamp5_*.sh` (canonical, already exist, zsh)

---

## No Bash on Mac Terminal

**Forbidden:**
- ❌ New `.sh` scripts with `#!/bin/bash`
- ❌ Calling `bash` in Swift `Process()`
- ❌ "bash" in documentation for Mac work
- ❌ Bash 3.2 patterns (no associative arrays, no `**` glob)

**Required:**
- ✅ Swift executables for new Mac code
- ✅ Call `zsh` when shelling out (e.g., `["zsh", "scripts/gamp5_iq.sh"]`)
- ✅ "zsh" in all Mac documentation
- ✅ Modern zsh features in canonical scripts (associative arrays, recursive globs)

---

## Architecture

```
cells/fusion/macos/
├── GaiaFusion/          ← MacFusion app (Swift)
├── MacHealth/           ← MacHealth app (Swift)
├── TestRobot/           ← PQ Metal GPU tests (Swift)
└── CleanCloneTest/      ← Test orchestrator (Swift, calls zsh)

scripts/
├── gamp5_iq.sh          ← Canonical (zsh, 437 lines)
├── gamp5_oq.sh          ← Canonical (zsh, 327 lines)
└── gamp5_pq.sh          ← Canonical (zsh, 395 lines)
```

---

**Summary:**
- Canonical scripts: **zsh** (modern features)
- New Mac code: **Swift** (calls zsh when needed)
- No bash on Mac terminal
- Remote mesh deploy: POSIX sh or Bash 5.x (SSH remote)

Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie
