# Fusion Mac App — Production Plan

## Terminal Condition

The Fusion Mac App is production-ready when:

1. Every swap action resolves to a canonical plant kind from `spec/native_fusion/plant_adapters.json`.
2. No hardcoded swap defaults exist in native or web paths.
3. Every plant kind terminates as **MEETS** (receipt exists) or **REFUSED** (reason receipted). No gap state survives.
4. Invariant tests produce terminal-state receipts for all swap paths.
5. Watchdog baseline (`scripts/fusion_playwright_watch.sh`) remains healthy.

---

## External Dependency Posture

The following are **not blockers**. They are REFUSED states with known reasons. The app handles them deterministically:

| Dependency | State | Reason |
|---|---|---|
| Live tokamak ingress | REFUSED | No site-specific PCS endpoint bound |
| Live stellarator command | REFUSED | No site-specific PCS endpoint bound |
| Live FRC command | REFUSED | No site-specific PCS endpoint bound |
| Pulsed-MIF timing | REFUSED | No site-specific timing runbook bound |
| Laser-ICF timing/IO | REFUSED | No site-specific timing runbook bound |
| Other-driver ICF command | REFUSED | No site-specific command runbook bound |

The app's responsibility: when a plant kind lacks a bound site runbook, the app emits a REFUSED receipt with the missing-field reason. That receipt **closes** the row. The row does not remain open.

---

## What Is Currently Broken

These are the actual code-level problems. All are app-owned. All close with Games 1–5.

### 1. Hardcoded swap defaults

- `GaiaFusionApp.swift` sends `input: "real", output: "virtual"` in `swapWithDefaults`.
- `FusionBridge.swift` defaults to `currentCell?.inputPlantType` with fallback to `"real"/"virtual"`.

### 2. Plant-type vocabulary is fractured

| Layer | Values |
|---|---|
| Swift model (`CellState.swift`) | `real` · `virtual` · `hybrid` · `mirror` · `unknown` |
| Web model (`fusion-s4/page.tsx`) | `Tokamak` · `Stellarator` · `Inertial` |
| Contract schema (`spec/cell_plant_state.schema.json`) | `virtual_x` · `virtual_y` · `real_x` · `real_y` · `hybrid` |
| Canonical source (`spec/native_fusion/plant_adapters.json`) | `tokamak` · `stellarator` · `frc` · `spheromak` · `mirror` · `inertial` |

Only the canonical source is authoritative. Everything else must resolve to it.

### 3. Config discoverability is weak

- `ConfigFileManager.fileForCellConfig` searches `config/` by default.
- Does not prioritize `deploy/fusion_cell/config.json` (the actual runtime config consumed by `fusion_cell_long_run_runner.sh`).

### 4. Native swap controls bypass selection

- Sidebar/inspector actions call `coordinator.swapWithDefaults(...)` with no user-selected plant kinds.
- Web UI sends chosen values only through direct SWAP control; native menu/context swaps bypass selection entirely.

---

## Execution — Five Games

### Game 1: Unify Plant-Type Vocabulary, Kill Hardcoded Defaults

**Goal:** One canonical plant-type source. No hardcoded swap values.

**Files:**

| File | Change |
|---|---|
| `Models/CellState.swift` | Read canonical kinds from `spec/native_fusion/plant_adapters.json` via native resolver |
| `MeshStateManager.swift` | Resolve all plant-type references through canonical resolver |
| `FusionBridge.swift` | Require explicit `input`/`output` when present. Fallback to defaults only if absent. Log when fallback fires. |
| `GaiaFusionApp.swift` | Replace `swapWithDefaults` with `swapCell(cellID:input:output:)`. Remove hardcoded `"real"/"virtual"`. |

**Backward compatibility:** Add a small compatibility map: `virtual` → `tokamak`, `real` → `tokamak`, `unknown` → refuse with reason. Legacy tokens from external payloads resolve through the map. Map is explicit, finite, and logged.

**Acceptance:** A native-triggered swap sends `tokamak|stellarator|frc|spheromak|mirror|inertial`. Bridge does not inject `real/virtual` unless no value was supplied, and that case is logged.

---

### Game 2: Native UI Explicit Swap Selection

**Goal:** Per-action plant-kind selection from native interface. No more default-only swaps.

**Files:**

| File | Change |
|---|---|
| `AppMenu.swift` | Keep action intents, route through explicit swap payload |
| `GaiaFusionApp.swift` | Coordinator APIs accept explicit swap payload |
| `Sidebar/FusionSidebarView.swift` | Route swap intent through prompt payload, not defaults |
| `Sidebar/MeshCellListView.swift` | Same — explicit payload routing |
| `Inspector/InspectorPanel.swift` | Swap control calls explicit-input-output method |
| `Inspector/CellDetailTab.swift` | Same — no `swapWithDefaults` |

**Add:** Simple swap panel state container in coordinator: last selected swap input/output + helper method to execute with values.

**Acceptance:** Native "swap selected" path supports explicit user-selected input/output per action. No path calls `swapWithDefaults`.

---

### Game 3: API Boundary Normalization

**Goal:** Web, native bridge, and local API on one plant-type list.

**Files:**

| File | Change |
|---|---|
| `LocalServer.swift` | Add `GET /api/fusion/plant-kinds` sourced from `spec/native_fusion/plant_adapters.json` |
| `LocalServer.swift` | Update `POST /api/fusion/swap` to validate values against canonical kinds. Return `missing_fields` / `unsupported_plant_kind` reason on failure. |
| `fusion-s4/page.tsx` | Build swap select options from `/api/fusion/plant-kinds` endpoint, not fixed literals |

**Required:** Shared normalizer for labels (`Tokamak` display → `tokamak` payload). Three lines of code. Not optional.

**Acceptance:** Every swap action traces to one canonical type from `spec/native_fusion/plant_adapters.json` and is validated at `/api/fusion/swap`.

---

### Game 4: Config Discoverability

**Goal:** Operators can find and edit the actual runtime config.

**Files:**

| File | Change |
|---|---|
| `Services/ConfigFileManager.swift` | Add `deploy/fusion_cell` to root candidates. Prioritize it when runner config fields are present. |
| `AppCoordinator.swift` | "Open config" resolves to effective runtime config path |
| `Inspector/CellDetailTab.swift` | Config button opens the path the runner actually reads |
| `Inspector/ConfigEditorTab.swift` | Same — effective path, not default search |

**Validate:** Config write semantics match fields consumed by `fusion_cell_long_run_runner.sh`: `real.command`, `virtual.binary_relative`, `tokamak_mode`, `timeout_sec`.

**Acceptance:** Operator selects and edits the active cell config path from inspector. Changes reflect in local state discovery.

---

### Game 5: Tests, Evidence, Terminal-State Receipts

**Goal:** Lock the contract. No silent drift.

**Files:**

| File | Change |
|---|---|
| `Tests/LocalServerAPITests.swift` | Test supported/unsupported plant kinds at `/api/fusion/plant-kinds` and `/api/fusion/swap` |
| `Tests/SwapLifecycleTests.swift` | Test explicit type values across full lifecycle |
| `tests/fusion/fusion_s4_console.spec.ts` | Confirm `#fusion-swap-panel` uses non-default payload and preserves selected input/output |
| `scripts/run_native_rust_fusion_invariant.py` | Include explicit witness fields for chosen plant kinds |
| `evidence/native_fusion/` | New witness files report swap-kind and per-cell config intent |

**Receipt requirements:** Every concept row terminates as:

- **MEETS**: Receipt exists at `evidence/fusion_control/` with concept ID, command vector hash, timing fields, terminal state.
- **REFUSED**: Receipt exists at `evidence/fusion_control/` with concept ID, missing-field reason, terminal state = REFUSED.

No row remains in gap state.

**Acceptance:** `scripts/test_fusion_plant_stack_all.sh` exits green only when all concept rows are receipted (MEETS or REFUSED). Output artifact lists exact evidence files used.

---

## Execution Order

```
Game 1 → Game 2 → Game 3 → Game 4 → Game 5
```

Game 1 unblocks 2 and 3. Game 4 is independent but benefits from 1. Game 5 seals everything.

---

## Site Runbook Model (Future C4 Gate — Not a Blocker)

When a site-specific PCS becomes available, the app supports binding:

- Runbook templates per concept under `deploy/fusion_cell/runbooks/`.
- Each runbook declares: endpoint, safety prerequisites, timing envelope, operator attestations.
- Execution refuses when required runbook fields are missing (REFUSED receipt with reason).
- Binding a runbook flips a concept row from REFUSED to MEETS.

This is infrastructure for future C4 closure. It is not blocking the current build. The app ships with REFUSED receipts for unbound concepts and deterministic handling of the absent-runbook state.

---

## Completion Criteria

All must hold simultaneously:

1. Native swap from menu/sidebar/inspector sends explicit canonical plant kinds.
2. Web swap panel uses canonical plant kinds from endpoint, not fixed literals.
3. Cell config opens/edits in effective runtime location (`deploy/fusion_cell/config.json`).
4. Invariant tests show swap-path success states for all canonical kinds.
5. Every concept row has a receipt: MEETS or REFUSED. Zero gap rows.
6. Watchdog baseline healthy. CURE cycle behavior unchanged.

---

## Source Files Referenced

```
spec/native_fusion/plant_adapters.json
spec/cell_plant_state.schema.json
spec/native_rust_fusion_invariant_contract.json
deploy/fusion_cell/config.json
deploy/fusion_mesh/fusion_projection.json
deploy/mac_cell_mount/MAC_FUSION_MESH_CELL_PORTS.md
services/fusion_control_mac/docs/VIRTUAL_TOKAMAK_C4_SOURCE.md
services/fusion_control_mac/docs/FUSION_ENTROPY_TAX_AND_VALIDATION.md
services/gaiaos_ui_web/app/fusion-s4/page.tsx
services/gaiaos_ui_web/app/api/fusion/s4-projection/route.ts
scripts/fusion_cell_long_run_runner.sh
scripts/fusion_playwright_watch.sh
scripts/test_fusion_plant_stack_all.sh
scripts/run_native_rust_fusion_invariant.py
```


# Fusion Mac App — Remaining Game Specs for Cursor

These are exact edit specifications. No planning. No replanning. Read each game, edit the files, compile, move to the next.

Alias map is correct. Build passes. Playwright passes. Games 1 and 3 are MEETS. Execute Games 2, 4, 5 in order.

---

## Game 2 — Native Swap Picker UI

### Problem

Native swap paths now accept explicit plant kinds (Game 1 closed this) but the UI never lets the operator **choose** a kind. Every native swap still sends whatever the current cell already has. The operator needs a picker.

### File 1: New file — `cells/fusion/macos/GaiaFusion/GaiaFusion/Views/PlantKindPicker.swift`

Create a reusable SwiftUI picker that reads canonical kinds from `PlantKindsCatalog`.

```swift
import SwiftUI

struct PlantKindPicker: View {
    let label: String
    @Binding var selection: String

    private var kinds: [String] {
        PlantKindsCatalog.canonicalKinds.sorted()
    }

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(kinds, id: \.self) { kind in
                Text(kind.capitalized).tag(kind)
            }
        }
        .pickerStyle(.menu)
    }
}
```

### File 2: `cells/fusion/macos/GaiaFusion/GaiaFusion/GaiaFusionApp.swift`

Add swap selection state to the coordinator scope. Find the coordinator or app-level state container and add:

```swift
// Swap selection state — persists across picker interactions within a session
@Published var selectedSwapInput: String = "tokamak"
@Published var selectedSwapOutput: String = "tokamak"
```

Update `swapSelectedCell()` to read from these properties:

```swift
func swapSelectedCell() {
    guard let cellID = selectedCellID else { return }
    swapCell(cellID: cellID, inputPlantType: selectedSwapInput, outputPlantType: selectedSwapOutput)
}
```

### File 3: `cells/fusion/macos/GaiaFusion/GaiaFusion/Inspector/CellDetailTab.swift`

Find the existing swap button/control. Replace or augment with:

```swift
// Before the swap button, add pickers
PlantKindPicker(label: "Input", selection: $coordinator.selectedSwapInput)
PlantKindPicker(label: "Output", selection: $coordinator.selectedSwapOutput)

// Swap button calls explicit path
Button("Swap") {
    coordinator.swapSelectedCell()
}
```

If `coordinator` is not directly accessible as an `@EnvironmentObject` or `@ObservedObject` here, pass the bindings through from the parent view that already holds the coordinator reference.

### File 4: `cells/fusion/macos/GaiaFusion/GaiaFusion/Inspector/InspectorPanel.swift`

If InspectorPanel wraps CellDetailTab and has its own swap button, apply the same pattern: add `PlantKindPicker` for input/output above the swap action, wire to coordinator state.

### File 5: `cells/fusion/macos/GaiaFusion/GaiaFusion/Sidebar/FusionSidebarView.swift`

If sidebar has a swap action (context menu or button), it must also use coordinator's `selectedSwapInput`/`selectedSwapOutput`. For context menus where a full picker is awkward, the sidebar swap can use the coordinator's current selections (set from inspector). The key constraint: **no path calls swap without the coordinator's explicit kind values**.

### File 6: `cells/fusion/macos/GaiaFusion/GaiaFusion/Sidebar/MeshCellListView.swift`

Same as FusionSidebarView. Context menu swap action reads from coordinator state, not from cell defaults.

### File 7: `cells/fusion/macos/GaiaFusion/GaiaFusion/AppMenu.swift`

Menu swap action reads from coordinator state. If the menu triggers a swap, it uses `coordinator.swapSelectedCell()` which already reads the explicit kind values.

### Game 2 Acceptance — Verify All of These

1. Open inspector for any cell. Two pickers appear (Input/Output) with all nine canonical kinds.
2. Select `stellarator` input, `frc` output. Hit Swap. Bridge receives `stellarator`/`frc`, not `real`/`virtual`.
3. Sidebar context menu swap uses the same coordinator selections.
4. Menu bar swap uses the same coordinator selections.
5. `xcodebuild -scheme GaiaFusion -destination 'platform=macOS' build` exits 0.
6. No call to `swapWithDefaults` exists anywhere. Verify: `rg "swapWithDefaults" cells/fusion/macos/` returns zero results.

---

## Game 4 — Config Discoverability

### Problem

`ConfigFileManager.fileForCellConfig` searches `config/` by default. The actual runtime config consumed by `fusion_cell_long_run_runner.sh` lives at `deploy/fusion_cell/config.json`. Operators cannot find or edit the effective config.

### File 1: `cells/fusion/macos/GaiaFusion/GaiaFusion/Services/ConfigFileManager.swift`

Find the method that resolves config file paths (likely `fileForCellConfig` or similar). Add `deploy/fusion_cell` as the **first** candidate in the search order.

```swift
// Before (example — adapt to actual code structure):
private let configSearchRoots = ["config/"]

// After:
private let configSearchRoots = [
    "deploy/fusion_cell/",   // Runtime config consumed by runner — highest priority
    "config/",               // Legacy fallback
]
```

If the method searches by filename pattern, ensure it matches `config.json` at the `deploy/fusion_cell/` root.

### File 2: `cells/fusion/macos/GaiaFusion/GaiaFusion/AppCoordinator.swift`

Find `openConfigForCell` or equivalent. Ensure it calls `ConfigFileManager` with the updated search order so it opens the runtime config first.

If there's a hardcoded path like `"config/\(cellID).json"`, replace with `ConfigFileManager.fileForCellConfig(cellID:)` which now prioritizes the deploy path.

### File 3: `cells/fusion/macos/GaiaFusion/GaiaFusion/Inspector/CellDetailTab.swift`

Find the "View Config" or "Edit Config" button action. Ensure it routes through `AppCoordinator.openConfigForCell` (which now uses updated ConfigFileManager).

### File 4: `cells/fusion/macos/GaiaFusion/GaiaFusion/Inspector/ConfigEditorTab.swift`

If this tab loads a config file path independently (not through ConfigFileManager), update it to use ConfigFileManager's resolution. No independent path resolution.

### Validate Field Contract

After editing, confirm the config file at `deploy/fusion_cell/config.json` contains these fields (used by `fusion_cell_long_run_runner.sh`):

- `real.command`
- `virtual.binary_relative`
- `tokamak_mode`
- `timeout_sec`

If the editor has field validation or schema checks, ensure these fields are recognized as valid.

### Game 4 Acceptance — Verify All of These

1. Open inspector for a cell. Click "View Config" or equivalent. It opens `deploy/fusion_cell/config.json`, not `config/something.json`.
2. Edit `timeout_sec` in the editor. Save. Confirm the file at `deploy/fusion_cell/config.json` is modified.
3. `rg "config/" cells/fusion/macos/GaiaFusion/GaiaFusion/Services/ConfigFileManager.swift` shows `deploy/fusion_cell/` appears before `config/` in search order.
4. `xcodebuild -scheme GaiaFusion -destination 'platform=macOS' build` exits 0.

---

## Game 5 — Evidence Closure + Receipt Artifacts

### Problem

Games are closing but no machine-readable receipt artifacts exist. The matrix checker has nothing to validate against.

### Task 1: Write Per-Game Receipt Artifacts

Create one JSON receipt file per completed game in `evidence/fusion_control/`. Do this **after** each game's acceptance checks pass.

#### `evidence/fusion_control/game_1_receipt.json`

```json
{
    "game": "game_1_unify_plant_vocabulary",
    "terminal_state": "MEETS",
    "timestamp": "<ISO 8601 at time of verification>",
    "verification": {
        "xcodebuild_exit": 0,
        "playwright_watchdog": "CURE",
        "watchdog_witness": "evidence/fusion_control/playwright_watch/playwright_watch_last_witness.json"
    },
    "files_changed": [
        "macos/GaiaFusion/GaiaFusion/Models/PlantKindsCatalog.swift",
        "macos/GaiaFusion/GaiaFusion/Models/CellState.swift",
        "macos/GaiaFusion/GaiaFusion/MeshStateManager.swift",
        "macos/GaiaFusion/GaiaFusion/FusionBridge.swift",
        "macos/GaiaFusion/GaiaFusion/GaiaFusionApp.swift"
    ],
    "assertions": [
        "PlantKindsCatalog.legacyAliases: virtual->tokamak, real->tokamak",
        "hybrid resolves to nil (REFUSED)",
        "unknown resolves to nil (REFUSED)",
        "No hardcoded real/virtual in swap payloads"
    ]
}
```

#### `evidence/fusion_control/game_2_receipt.json`

```json
{
    "game": "game_2_native_swap_picker",
    "terminal_state": "MEETS",
    "timestamp": "<ISO 8601 at time of verification>",
    "verification": {
        "xcodebuild_exit": 0,
        "swapWithDefaults_grep_count": 0
    },
    "files_changed": [
        "macos/GaiaFusion/GaiaFusion/Views/PlantKindPicker.swift",
        "macos/GaiaFusion/GaiaFusion/GaiaFusionApp.swift",
        "macos/GaiaFusion/GaiaFusion/Inspector/CellDetailTab.swift",
        "macos/GaiaFusion/GaiaFusion/Inspector/InspectorPanel.swift",
        "macos/GaiaFusion/GaiaFusion/Sidebar/FusionSidebarView.swift",
        "macos/GaiaFusion/GaiaFusion/Sidebar/MeshCellListView.swift",
        "macos/GaiaFusion/GaiaFusion/AppMenu.swift"
    ],
    "assertions": [
        "Inspector shows Input/Output pickers with 6 canonical kinds",
        "Sidebar/menu swap reads coordinator.selectedSwapInput/Output",
        "Zero results for rg swapWithDefaults"
    ]
}
```

#### `evidence/fusion_control/game_3_receipt.json`

```json
{
    "game": "game_3_api_boundary_normalization",
    "terminal_state": "MEETS",
    "timestamp": "<ISO 8601 at time of verification>",
    "verification": {
        "xcodebuild_exit": 0,
        "playwright_watchdog": "CURE"
    },
    "files_changed": [
        "macos/GaiaFusion/GaiaFusion/LocalServer.swift",
        "spec/cell_plant_state.schema.json",
        "services/gaiaos_ui_web/app/fusion-s4/page.tsx"
    ],
    "assertions": [
        "GET /api/fusion/plant-kinds returns 6 canonical kinds",
        "POST /api/fusion/swap rejects unsupported_plant_kind",
        "Web UI fetches kinds dynamically, no fixed literals"
    ]
}
```

#### `evidence/fusion_control/game_4_receipt.json`

```json
{
    "game": "game_4_config_discoverability",
    "terminal_state": "MEETS",
    "timestamp": "<ISO 8601 at time of verification>",
    "verification": {
        "xcodebuild_exit": 0
    },
    "files_changed": [
        "macos/GaiaFusion/GaiaFusion/Services/ConfigFileManager.swift",
        "macos/GaiaFusion/GaiaFusion/AppCoordinator.swift",
        "macos/GaiaFusion/GaiaFusion/Inspector/CellDetailTab.swift",
        "macos/GaiaFusion/GaiaFusion/Inspector/ConfigEditorTab.swift"
    ],
    "assertions": [
        "ConfigFileManager searches deploy/fusion_cell/ before config/",
        "Inspector opens deploy/fusion_cell/config.json",
        "Runner fields (real.command, virtual.binary_relative, tokamak_mode, timeout_sec) editable"
    ]
}
```

### Task 2: Update Test Fixtures for Game 2

#### `cells/fusion/macos/GaiaFusion/Tests/SwapLifecycleTests.swift`

Add a test that verifies the full picker-to-bridge path:

```swift
func testExplicitSwapKindPassthrough() {
    // Setup: coordinator with selectedSwapInput = "frc", selectedSwapOutput = "mirror"
    let coordinator = AppCoordinator()
    coordinator.selectedSwapInput = "frc"
    coordinator.selectedSwapOutput = "mirror"

    // Act: trigger swap through coordinator
    // Assert: bridge receives "frc" and "mirror", not "real"/"virtual"
    // Adapt to actual bridge mock/capture pattern in test suite
}
```

#### `cells/fusion/macos/GaiaFusion/Tests/LocalServerAPITests.swift`

Add test for unsupported kind rejection:

```swift
func testSwapRejectsUnsupportedPlantKind() {
    // POST /api/fusion/swap with input_plant_type: "hybrid"
    // Assert: response contains "unsupported_plant_kind" reason
    // Assert: response status is 400 or equivalent error
}

func testSwapRejectsUnknownPlantKind() {
    // POST /api/fusion/swap with input_plant_type: "unknown"
    // Assert: same rejection pattern
}
```

### Task 3: Run Playwright Watchdog After All Games

After Games 2 and 4 are complete and xcodebuild passes:

```bash
cd GAIAOS && FUSION_PLAYWRIGHT_MAX_CYCLES=10 bash scripts/fusion_playwright_watch.sh
```

Confirm terminal state is CURE. Update `playwright_watch_last_witness.json`.

### Task 4: Write Final Closure Artifact

After all five game receipts exist:

#### `evidence/fusion_control/production_closure.json`

```json
{
    "closure": "fusion_mac_app_production",
    "terminal_state": "MEETS",
    "timestamp": "<ISO 8601>",
    "games": {
        "game_1": "MEETS",
        "game_2": "MEETS",
        "game_3": "MEETS",
        "game_4": "MEETS",
        "game_5": "MEETS"
    },
    "verification": {
        "xcodebuild_exit": 0,
        "playwright_terminal": "CURE",
        "swapWithDefaults_grep": 0,
        "hardcoded_real_virtual_grep": 0
    },
    "receipts": [
        "evidence/fusion_control/game_1_receipt.json",
        "evidence/fusion_control/game_2_receipt.json",
        "evidence/fusion_control/game_3_receipt.json",
        "evidence/fusion_control/game_4_receipt.json",
        "evidence/fusion_control/playwright_watch/playwright_watch_last_witness.json"
    ]
}
```

### Game 5 Acceptance — Verify All of These

1. All four game receipt files exist and contain valid JSON.
2. `production_closure.json` exists with all games = MEETS.
3. `xcodebuild` exit 0.
4. Playwright watchdog CURE.
5. `rg "swapWithDefaults" cells/fusion/macos/` returns zero.
6. `rg '"real"' cells/fusion/macos/GaiaFusion/GaiaFusion/GaiaFusionApp.swift` returns zero hardcoded swap values (string literals in non-alias-map context).

---

## Execution Sequence for Cursor

```
1. Execute Game 2 edits (7 files)
2. xcodebuild — must exit 0
3. Execute Game 4 edits (4 files)
4. xcodebuild — must exit 0
5. Run Playwright watchdog (FUSION_PLAYWRIGHT_MAX_CYCLES=10)
6. Write all 5 receipt JSONs + production_closure.json
7. Final xcodebuild + final Playwright run
8. Report terminal state
```

Do not replan. Do not restate the plan. Open the first file, make the edit, compile, move to the next.

---

## Terminal state matrix (closure pass 2026-04-09)

| Topic | State | Closure artifact |
|-------|--------|------------------|
| Games 1 & 3 (canonical plant kinds, API `/api/fusion/plant-kinds`, `/api/fusion/swap` validation) | **MEETS** | Swift tests + gate: `swift test` in `macos/GaiaFusion`; `scripts/run_fusion_mac_app_gate.py` |
| Game 2 (native swap picker UI) | **MEETS** | `PlantKindPicker` + `selectedSwapInput` / `selectedSwapOutput` on coordinator; `swapCell` / `swapSelectedCell` use picker values (`Inspector` / `GaiaFusionApp`) |
| Game 4 (config discoverability to `deploy/fusion_cell/config.json`) | **MEETS** | `ConfigFileManager.fusionCellRuntimeConfigURL()` + **Config → Open fusion_cell config (runner)** (`⌘⇧O`); same path as `fusion_cell_long_run_runner.sh`; test `testFusionCellRuntimeConfigURLMatchesRunnerPath` |
| Game 5 (invariant receipts) | **PARTIAL** | **GaiaFusion app slice MEETS:** `bash scripts/run_gaiafusion_release_smoke.sh` → `evidence/fusion_control/gaiafusion_release_smoke_receipt.json` (CURE). **Full plant + Docker tier:** `scripts/test_fusion_plant_stack_all.sh` (optional compose) + `evidence/native_fusion/` — separate spine. |
| Site PCS / live plant | **REFUSED** | No site endpoint in repo; deterministic REFUSED receipts until runbook bound |
| Mac cell mooring PUB / vQbit matrix | **MEETS** (mooring script + docs) | `deploy/mac_cell_mount/MAC_CELL_MOORING_AND_VQBIT.md`, `launchd/README.md` |
| Substrate-sealed vQbit (Arango) from Mac limb | **OPEN** | Gateway ingest + `vqbit_measurements` / claims id in `evidence/` receipt — see same doc |