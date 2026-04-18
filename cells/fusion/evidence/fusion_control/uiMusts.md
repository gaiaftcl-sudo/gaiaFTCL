I see the problem. That's the sovereign web UI running in a browser window pretending to be a Mac app. The title bar says "GaiaFusion — MOORED — 0/9" but it's just a web page with browser chrome hidden. All those domain tabs (Atmosphere, Ocean, Biosphere, Molecular, Astro...) are the web dashboard — not the Fusion control app.

Here's what it needs to be:The screenshot shows a web page pretending to be an app. Here's what changes:

**Remove from the WebView:**

- All 20+ domain tabs (Atmosphere, Ocean, Biosphere, Molecular, Astro, Turbulence, Closure Proof, Closure Game, Domain Tubes, Sovereign mesh, Fusion fleet, Substrate console, Type I moor, GATE1)
- The `@xRick_playwright` auth bar + Connect button
- The "GaiaFTCL sovereign UI" header
- ALL navigation — the native shell handles that

**Keep in the WebView:**

- The nine-cell grid (that 3x3 you have is good)
- Plant controls panel (input/output dropdowns + Swap)
- Projection panel
- Swap log

**Add as native Swift (outside the WebView):**


| Component         | What it does                                                    | Why it can't be web                              |
| ----------------- | --------------------------------------------------------------- | ------------------------------------------------ |
| **Sidebar**       | Cell list with health dots, config file tree, evidence browser  | File system access, right-click context menus    |
| **NSToolbar**     | Grid / Topology / Projection / Metrics segments                 | macOS HIG, works when WebView is loading         |
| **Inspector**     | Cell detail, JSON config editor with validation, receipt viewer | Edit and save files to disk, SSH terminal output |
| **Onboarding**    | SSH key setup, NATS test, mesh probe, mooring                   | Must work when web server is down                |
| **Config editor** | Edit plasma parameters, NATS settings, cell configs             | File I/O, JSON validation, Cmd+S save            |


**17 Swift files, 4 test files, 1 stripped React page.** The React page becomes just the plasma grid engine. Everything around it — navigation, file management, config editing, onboarding, evidence browsing — is native macOS.

The WebView is the engine. The native shell is the cockpit. Tomorrow, start with the `NavigationSplitView` shell and the sidebar, then strip the web page down to just the grid.

# GaiaFTCL Fusion Mac — Native Shell Architecture

**What you have:** a web page in a window pretending to be an app.
**What you need:** a real Mac app with native controls wrapping a focused plasma core.

---

## What's Wrong With the Current Screenshot

```
CURRENT (wrong):
┌─────────────────────────────────────────────────────────┐
│ GaiaFusion — MOORED — 0/9                               │  ← fake title bar
├─────────────────────────────────────────────────────────┤
│ @xRick_playwright...  [Connect]                          │  ← web auth (not native)
│ Dashboard Games Atmosphere Ocean Biosphere Molecular ... │  ← 20+ domain tabs (NOT fusion)
│ Closure Game Domain Tubes Sovereign mesh Fusion fleet .. │  ← more unrelated tabs
├─────────────────────────────────────────────────────────┤
│ GaiaFTCL Fusion Control Surface  Quorum 9/9  9/9 healthy│
│                                                         │
│  [cell grid — this part is good]                        │
│                                                         │
│  [plant controls — this part is good]                   │
│                                                         │
├─────────────────────────────────────────────────────────┤
│ Mesh: 9/9 ● NATS: connected ● vQbit: 1.000              │  ← web status bar
└─────────────────────────────────────────────────────────┘

Problems:
  ✗ No native toolbar
  ✗ No native sidebar
  ✗ No native file management
  ✗ 20+ domain tabs that don't belong in this app
  ✗ Web-style auth bar at top
  ✗ No expandable/collapsible panels
  ✗ No native config management
  ✗ Looks like a website, not a Mac app
  ✗ Can't manage local files, save results, validate configs
```

---

## What It Must Look Like

```
CORRECT:
┌─────────────────────────────────────────────────────────────────────┐
│ ● ● ●  GaiaFusion — MOORED — 9/9 cells               ⌃ ⌥ ⌘      │
├──────┬──────────────────────────────────────────────────────────────┤
│ ◀ ▶  │  ⊞ Grid   ⊡ Topology   ⊕ Projection   📊 Metrics          │ ← native NSToolbar
├──────┼──────────────────────────────────────────────────────────────┤
│      │                                                              │
│  S   │              WKWebView (plasma core only)                    │
│  I   │                                                              │
│  D   │    ┌─────┐  ┌─────┐  ┌─────┐                               │
│  E   │    │HEL-1│  │HEL-2│  │HEL-3│    No domain tabs.            │
│  B   │    │ R/R │  │ R/R │  │ V/V │    No auth bar.               │
│  A   │    └─────┘  └─────┘  └─────┘    Just the grid + controls.  │
│  R   │    ┌─────┐  ┌─────┐  ┌─────┐                               │
│      │    │HEL-4│  │HEL-5│  │NBG-1│                               │
│ ──── │    └─────┘  └─────┘  └─────┘                               │
│      │    ┌─────┐  ┌─────┐  ┌─────┐                               │
│ Mesh │    │NBG-2│  │NBG-3│  │NBG-4│                               │
│  9/9 │    └─────┘  └─────┘  └─────┘                               │
│  ●●● │                                                              │
│  ●●● │    SELECTED: HEL-01                                         │
│  ●●● │    Input: real    Output: virtual                            │
│  ●●● │    [Swap] [History] [Detail]                                 │
│  ●●● │                                                              │
│ ──── │    PROJECTION                                                │
│      │    flow_catalog: active    control_matrix: present           │
│Config│    long_run: running (14,302 records)                        │
│ ☐ a  │                                                              │
│ ☐ b  │                                                              │
│ ──── ├──────────────────────────────────────────────────────────────┤
│      │                                                              │
│Files │    INSPECTOR (native, collapsible bottom panel)              │
│ 📄 a │    Cell: gaiaftcl-hcloud-hel1-01                             │
│ 📄 b │    IP: 77.42.85.60   Health: 100%   Uptime: 47h             │
│ 📄 c │    Last swap: 2026-04-07T14:32:01Z  input real→virtual      │
│      │    Last heal: none                                           │
│      │    NATS subjects: gaiaftcl.cell.hel1-01.*                    │
│      │                                                              │
├──────┴──────────────────────────────────────────────────────────────┤
│ Mesh: 9/9 ● NATS: connected ● vQbit: 0.047 ● Build: release       │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Native Components (Swift/AppKit — NOT in WebView)

### 1. NSToolbar (top)

```
┌──────────────────────────────────────────────────────────┐
│ ◀ ▶  │  ⊞ Grid   ⊡ Topology   ⊕ Projection   📊 Metrics │
└──────────────────────────────────────────────────────────┘
```

Native segmented control. Tells the WebView which view to show.
Clicking "Topology" sends `fusionBridge.postMessage({action:"show_topology"})`.
Clicking "Grid" sends `fusionBridge.postMessage({action:"show_grid"})`.

The toolbar is native because:

- It follows macOS HIG (Human Interface Guidelines)
- It works even when the WebView is loading
- It's where Mac users expect navigation controls

### 2. NSSplitView Sidebar (left)

Three collapsible sections:

**Mesh Status**

```
Mesh
  ● gaiaftcl-hcloud-hel1-01    100%  R/R
  ● gaiaftcl-hcloud-hel1-02    100%  R/R
  ● gaiaftcl-hcloud-hel1-03     98%  V/V
  ● gaiaftcl-hcloud-hel1-04    100%  R/R
  ● gaiaftcl-hcloud-hel1-05    100%  H/R
  ○ gaiaftcl-netcup-nbg1-01      0%  ---
  ● gaiaftcl-netcup-nbg1-02    100%  R/M
  ● gaiaftcl-netcup-nbg1-03    100%  R/V
  ● gaiaftcl-netcup-nbg1-04    100%  V/R
```

- Green dot = healthy, red dot = down, amber = degraded
- Click a cell → selects it in the WebView grid AND in the Inspector
- Right-click → context menu: Heal, Swap, Detail, History
- Updates every 15 seconds from MeshStateManager

**Config Files**

```
Config
  📁 cells/
    📄 hel1-01.json
    📄 hel1-02.json
    📄 ...
  📁 nats/
    📄 jetstream.conf
    📄 subjects.json
  📁 plasma/
    📄 confinement.json
    📄 field_strengths.json
    📄 profiles.json
  📄 quorum.json
  📄 mesh_heal.json
```

- Native NSOutlineView (like Finder sidebar)
- Click a file → opens in the Inspector panel (bottom) as editable JSON
- Save with Cmd+S → validates JSON → writes to disk
- Invalid JSON → red border, cannot save

**Saved Results**

```
Results
  📁 evidence/
    📁 mesh/
      📄 C4_MESH_SELF_MOOR.json
      📄 MESH_HEAL_ATTEMPT_1_*.json
    📁 native_fusion/
      📄 LATEST_MAC_FUSION_RESULT.json
      📄 gate_witness_*.json
    📁 fusion_control/
      📄 cell_identity.json
      📄 mount_receipt.json
  📁 receipts/
    📄 swap_receipt_*.json
    📄 heal_receipt_*.json
```

- Browse all evidence and receipt files
- Click → view in Inspector
- Filter by date, gate, terminal state

### 3. Inspector Panel (bottom, collapsible)

```
┌──────────────────────────────────────────────────────────┐
│ INSPECTOR                                          [▼ ▲] │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  Mode: [Cell Detail] [Config Editor] [Receipt Viewer]    │
│                                                          │
│  Cell: gaiaftcl-hcloud-hel1-01                           │
│  IP: 77.42.85.60                                         │
│  Health: 100%    Uptime: 47h 23m                         │
│  Input: real     Output: virtual     Status: active      │
│  Last swap: 2026-04-07T14:32:01Z (real→virtual) CALORIE  │
│  Last heal: none                                         │
│  NATS: gaiaftcl.cell.hel1-01.plant_state (active)        │
│  vQbit delta: 0.047                                      │
│                                                          │
│  [Heal]  [Swap]  [SSH Terminal]  [View Config]           │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

Three modes:

- **Cell Detail** — shows everything about the selected cell
- **Config Editor** — editable JSON viewer for config files (selected from sidebar)
- **Receipt Viewer** — read-only JSON viewer for evidence/receipts

The Inspector is native because:

- Config files must be editable with validation
- SSH terminal output needs native text rendering
- Receipt JSON needs syntax highlighting
- It works when the WebView is down

### 4. Native Status Bar (bottom)

```
┌──────────────────────────────────────────────────────────┐
│ Mesh: 9/9 ● NATS: connected ● vQbit: 0.047 ● Build: rel│
└──────────────────────────────────────────────────────────┘
```

Same as before — native SwiftUI, always visible.

### 5. Onboarding Flow (native)

First launch:

1. **Welcome sheet** — "GaiaFusion Plasma Control" with logo
2. **SSH key setup** — file picker for SSH key (needed for mesh heal)
3. **NATS connection** — enter NATS URL, test connection
4. **Mesh probe** — probe all 9 cells, show results
5. **Mooring** — create cell_identity.json, mount_receipt.json
6. **Done** — sidebar populated, grid loads

All native sheets. No WebView. This runs even when the web server is down.

---

## What Stays in the WebView

ONLY the plasma control core:

```
┌──────────────────────────────────────────────────────────┐
│                                                          │
│  Nine-cell grid (3x3)                                    │
│  with health dots, plant type badges, swap buttons       │
│                                                          │
│  Selected cell detail panel (right side of grid)         │
│  with input/output dropdowns and Swap button             │
│                                                          │
│  Swap lifecycle animation                                │
│  (IDLE → REQUESTED → DRAINING → COMMITTED → VERIFIED)   │
│                                                          │
│  Swap log (bottom of WebView area)                       │
│  last 10 swaps, scrollable                               │
│                                                          │
│  Topology view (D3 force graph — when toolbar selects)   │
│                                                          │
│  Projection view (when toolbar selects)                  │
│  flow_catalog table + control_matrix + long_run          │
│                                                          │
│  Metrics view (when toolbar selects)                     │
│  vQbit chart, throughput chart                           │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

**What is NOT in the WebView:**

- No domain tabs (Atmosphere, Ocean, Biosphere — those are other apps)
- No auth bar (mooring is handled natively in onboarding)
- No navigation chrome
- No file management
- No config editing
- No sidebar

The WebView page at `/fusion-s4` must be stripped to ONLY the plasma grid + controls. No GaiaFTCL sovereign UI header. No domain navigation. Just the core.

---

## Cursor Build Prompts (Updated for Native Shell)

### Prompt 1: App Shell with NSSplitView

Model: **Sonnet 4**

```
Create a macOS SwiftUI app with a three-panel layout using NavigationSplitView.

Target: macOS 14+
Name: GaiaFusion

Layout:
- LEFT: Sidebar (250px default, collapsible with Cmd+Option+S)
  Three sections: "Mesh" (cell list), "Config" (file tree), "Results" (evidence files)
- CENTER: WKWebView loading http://127.0.0.1:8910/fusion-s4 (full bleed, no browser chrome)
- BOTTOM: Inspector panel (200px default, collapsible with Cmd+Option+I)
  Three tabs: Cell Detail, Config Editor, Receipt Viewer

NSToolbar at top with segmented control: Grid | Topology | Projection | Metrics
Clicking a segment sends a message to the WebView via fusionBridge.

Status bar at bottom: "Mesh: 9/9 ● NATS: connected ● vQbit: 0.047"

Window minimum size: 1200x800
Title: "GaiaFusion — MOORED — n/9 cells"
```

### Prompt 2: Sidebar Mesh List

Model: **Sonnet 4**

```
Create a SwiftUI sidebar section showing all nine mesh cells as a List.

Each row shows:
- Colored circle (green/amber/red) for health
- Cell name (truncated: "hel1-01" not full name)
- Health percentage
- Plant type badges: "R/R" or "V/M" etc (input/output, one letter each)

The list observes MeshStateManager and updates every 15 seconds.

Click a cell: selects it, tells the WebView to highlight it, shows detail in Inspector.
Right-click context menu: Heal, Swap Input, Swap Output, View Detail, View History.

Section header: "Mesh" with a refresh button (circular arrow icon).
```

### Prompt 3: Config File Browser

Model: **Sonnet 4**

```
Create a SwiftUI sidebar section that shows config files as an NSOutlineView-style tree.

Root directories:
  cells/ — per-cell JSON configs
  nats/ — NATS JetStream config
  plasma/ — plasma physics parameters

Read file tree from repo_root/config/ directory.
Show file icons (📁 for dirs, 📄 for .json files).
Click a file → loads its contents into the Inspector's Config Editor tab.
Support Cmd+S to save edits (validates JSON first — red border if invalid).
Show file modification date in grey text.
```

### Prompt 4: Inspector Panel

Model: **Sonnet 4**

```
Create a collapsible bottom panel (Inspector) with three tabs:

Tab 1: Cell Detail
  Shows all data for the currently selected cell:
  name, IP, health %, uptime, input/output plant types, status,
  last swap (time + transition + terminal), last heal,
  NATS subjects, vQbit delta.
  Buttons: [Heal] [Swap] [SSH Terminal] [View Config]

Tab 2: Config Editor
  NSTextView with JSON syntax highlighting.
  Editable. Validates on save (Cmd+S).
  Shows file path at top. Red border if invalid JSON.
  Save writes to disk. Shows "Saved ✓" confirmation.

Tab 3: Receipt Viewer
  Read-only JSON viewer with syntax highlighting.
  Shows receipt files selected from the Results sidebar section.
  Highlights "terminal" field: green for CALORIE, red for REFUSED, amber for PARTIAL.

Panel is 200px default height. Toggle with Cmd+Option+I.
Drag handle at top to resize.
```

### Prompt 5: Onboarding Flow

Model: **Sonnet 4**

```
Create a first-launch onboarding flow as a series of native SwiftUI sheets.

Step 1: Welcome
  "GaiaFusion Plasma Control" with app icon
  "Control your nine-cell sovereign mesh" subtitle
  [Get Started] button

Step 2: SSH Key
  "Select your SSH key for mesh healing"
  File picker button (default: ~/.ssh/id_rsa)
  [Test Connection] button that SSHs to the first cell
  Show result: "Connected ✓" or "Failed: reason"
  [Next] button (enabled only after successful test, or [Skip])

Step 3: NATS Connection
  "Enter your NATS server URL"
  Text field (default: nats://127.0.0.1:4222)
  [Test Connection] button
  Show result
  [Next]

Step 4: Mesh Probe
  "Probing nine sovereign cells..."
  Show each cell with a spinner → green check or red X
  Auto-runs on appear. Shows results.
  [Next] (even if some cells are down — the app will heal them)

Step 5: Mooring
  "Creating your cell identity..."
  Auto-generates cell_identity.json, mount_receipt.json
  Shows mooring state: MOORED
  [Finish]

Save all settings to UserDefaults.
Set a flag so onboarding only runs once (unless user resets).
```

### Prompt 6: Strip the WebView Page

Model: **Sonnet 4**

```
Update /fusion-s4 page to remove ALL non-plasma elements:

REMOVE:
- The entire top navigation bar (Dashboard, Games, Atmosphere, Ocean, etc.)
- The @xRick_playwright auth bar and Connect button
- The "GaiaFTCL sovereign UI" header
- The second row of tabs (Closure Game, Domain Tubes, etc.)
- Any sidebar or navigation that is not the cell grid

KEEP:
- The cell grid (3x3 with nine cells)
- The plant controls panel (input/output dropdowns + Swap button)
- The swap lifecycle display
- The projection panel (flow_catalog, control_matrix, long_run)
- The status line (Mesh: 9/9 ● NATS: connected ● vQbit)

The page should render ONLY the plasma control surface.
No header. No navigation. No domain tabs. No auth.
The native Mac app provides all navigation via toolbar and sidebar.

Background: transparent (inherits from the native app's dark theme).
The page must feel like it's part of the native app, not a website.
```

---

## File Structure (Updated)

```
macos/GaiaFusion/
├── Package.swift
├── GaiaFusion/
│   ├── App/
│   │   ├── GaiaFusionApp.swift           ← @main, window, NSSplitView layout
│   │   ├── AppDelegate.swift             ← NSMenu, NSToolbar
│   │   └── OnboardingFlow.swift          ← First-launch sheets
│   ├── Sidebar/
│   │   ├── SidebarView.swift             ← Container for three sections
│   │   ├── MeshCellListView.swift        ← Nine-cell list with health dots
│   │   ├── ConfigFileBrowser.swift       ← File tree for config JSON
│   │   └── ResultsBrowser.swift          ← Evidence/receipt file tree
│   ├── Inspector/
│   │   ├── InspectorPanel.swift          ← Collapsible bottom panel
│   │   ├── CellDetailTab.swift           ← Selected cell info + actions
│   │   ├── ConfigEditorTab.swift         ← Editable JSON with validation
│   │   └── ReceiptViewerTab.swift        ← Read-only JSON with highlighting
│   ├── Toolbar/
│   │   └── FusionToolbar.swift           ← Grid | Topology | Projection | Metrics
│   ├── WebView/
│   │   ├── FusionWebView.swift           ← WKWebView wrapper (center panel)
│   │   └── FusionBridge.swift            ← JS ↔ Swift message bridge
│   ├── Services/
│   │   ├── LocalServer.swift             ← HTTP server on :8910
│   │   ├── MeshStateManager.swift        ← 15s probe timer, ObservableObject
│   │   ├── ConfigFileManager.swift       ← Read/write/validate config JSON
│   │   ├── SSHService.swift              ← SSH to cells for heal
│   │   └── NATSService.swift             ← NATS connection
│   ├── StatusBar/
│   │   └── StatusBarView.swift           ← Bottom bar
│   └── Models/
│       ├── CellState.swift
│       ├── PlantType.swift
│       ├── SwapState.swift
│       └── ProjectionState.swift
├── Resources/
│   └── fusion-web/                       ← Built npm app (production mode)
└── Tests/
    ├── CellStateTests.swift
    ├── SwapLifecycleTests.swift
    ├── ConfigValidationTests.swift
    └── MeshProbeTests.swift
```

**17 Swift files. 4 test files. 1 stripped React page.**

---

## What the Native Shell Gives You (that the web page can't)


| Capability                       | Web page        | Native shell                                 |
| -------------------------------- | --------------- | -------------------------------------------- |
| Edit config JSON with validation | No              | Yes — ConfigEditorTab with save + validate   |
| Browse evidence files            | No              | Yes — ResultsBrowser sidebar                 |
| SSH into cells                   | No (security)   | Yes — SSHService from Inspector              |
| Manage SSH keys                  | No              | Yes — Onboarding + Config                    |
| File system access               | No (sandbox)    | Yes — read/write config and evidence         |
| Native context menus             | No              | Yes — right-click cell → Heal/Swap/Detail    |
| Keyboard shortcuts               | Limited         | Full — Cmd+P probe, Cmd+S swap, Cmd+, config |
| Works when web server is down    | No              | Yes — sidebar, config, onboarding all native |
| Collapsible panels               | CSS only        | Native NSSplitView with drag handles         |
| First-launch onboarding          | Redirect to web | Native sheets with SSH/NATS testing          |
| Save results to disk             | No              | Yes — evidence/ directory management         |
| Looks like a Mac app             | No              | Yes                                          |


---

## Invariant Impact

The AppleScript test suite needs these additional tests:


| Test                     | What                                  | Human reason                                      |
| ------------------------ | ------------------------------------- | ------------------------------------------------- |
| Sidebar exists           | NSSplitView has sidebar column        | Operator needs cell list always visible           |
| Sidebar shows 9 cells    | Nine list items in Mesh section       | Must see all cells without scrolling              |
| Right-click context menu | Context menu on cell in sidebar       | Quick heal/swap without finding buttons           |
| Inspector toggles        | Cmd+Option+I shows/hides bottom panel | Operator needs more screen space sometimes        |
| Toolbar segments         | 4 segments in toolbar                 | Navigate grid/topology/projection/metrics         |
| Config editor saves      | Save a config file via Cmd+S          | Operator must be able to change plasma parameters |
| Onboarding completes     | All 5 steps finish on first launch    | New operator must get moored before anything else |


---

*The WebView is the plasma engine. The native shell is the cockpit. You don't fly a plane from inside the engine — you fly it from the cockpit that wraps around the engine and gives you instruments, controls, file access, and situational awareness.*