# GaiaFusion (macOS)

Native shell for the Fusion S⁴ surface: bundled `fusion-web`, `LocalServer` on loopback, mesh probes, NATS SUB, Klein-bottle health.

**Composite bundle:** `Resources/fusion-sidecar-cell/` pins the **Docker MCP cell** (`docker-compose.fusion-sidecar.yml` + guest bootstrap) for Linux VM / full GAIAOS checkouts — **Fusion itself is native Swift/Metal**, not containerized. Refreshed by `scripts/build_gaiafusion_composite_assets.sh`. **`Resources/gaiafusion_substrate.wasm`** is built or spike-copied via `scripts/build_gaiafusion_wasm_pack.sh`. **`GET /api/fusion/wasm-substrate`** serves it for `WebAssembly.instantiateStreaming` inside WKWebView; `/api/fusion/health` includes separate **`wasm_runtime`** vs DOM **`wasm_surface`**.

## Operator truth (working app)

**`swift test` / XCTest** exercises `LocalServer` without proving **WKWebView**, **`WebAssembly.instantiate`**, **`wasm_runtime.closed`**, or the **bundled Next `/_next/static`** graph. It is compile hygiene only.

**Aqua / WindowServer (XNU):** The package is an **AppKit** host with **Metal** and **WKWebView** surfaces. `swiftpm-xctest-helper` loads real bundles; without a valid **Aqua** session, Mach IPC to **WindowServer** can block indefinitely and leave helpers in **uninterruptible sleep (`STAT UE`)** — especially if `.build` is removed while those threads are parked in the kernel. **Run `bash GAIAOS/scripts/run_gaiafusion_swift_tests.sh` from `Terminal.app` in an interactive user session on the Mac**, not from a headless SSH/bootstrap context or IDE-only agent shell. Operator truth for the full stack remains **`verify_gaiafusion_working_app.sh`** / **`run_operator_fusion_mesh_closure.sh`**.

**Filter hygiene:** `swift test --filter` takes a **regex**. Use **one** `--filter` with alternation (e.g. `PlantKindsCatalogTests|LocalServerAPITests`) to run several test classes. **Multiple** `--filter` arguments combine with **AND** — easy to match **zero** tests and get a confusing stall. Wrapper: `bash GAIAOS/scripts/run_gaiafusion_swift_tests.sh` (preflight **REFUSED** exit **86** if `swiftpm-xctest-helper` / `xctest` rows exist for this package — avoids a silent hang; override only when debugging: `GAIAFUSION_SKIP_STALL_PREFLIGHT=1`). **`rm -rf .build` alone** does not clear **UE** workers from the kernel process table; reboot / session reset is still the reliable fix before expecting `swift test` to complete. If `swift test` hangs after “Build complete”, run `bash GAIAOS/scripts/diagnose_gaiafusion_swift_test_stall.sh` — stuck helpers / `xctest` in **UE** usually needs a **reboot** (or login session reset), not another `swift test` loop.

**Non-interactive sudo (purge):** set `SUDO_PASSWORD` in **`GAIAOS/.env`** (gitignored; see **`GAIAOS/.env.example`**). Then `bash GAIAOS/scripts/gaiafusion_kernel_purge.sh` runs `sudo` via `scripts/lib/sudo_from_env.sh` (best-effort killall / lsof / cache + `.build` rm). If **STAT=UE** rows remain after purge, the Mach/WindowServer boundary still wins — **reboot** or soft-reset GUI as last resort.

**Substrate-only (Docker stack, no Xcode gate):** `bash scripts/fusion_sidecar_stack_smoke.sh` — brings up `docker-compose.fusion-sidecar.yml` and requires `mcp_mac_cell_probe.py` **CURE** (Arango + `/claims` alive).

The **canonical** app + mesh check is:

```bash
cd GAIAOS   # repo root
bash scripts/verify_gaiafusion_working_app.sh
```

For autonomous closure of white-screen/blank-state drift (MCP conversation + healing ladder + final verify), use:

```bash
cd GAIAOS
bash scripts/run_operator_fusion_mesh_closure.sh
```

This now runs `scripts/fusion_ui_self_heal_loop.py` before final working-app verify and writes:
- `evidence/fusion_control/fusion_ui_self_heal_loop_*.jsonl`
- `evidence/fusion_control/fusion_ui_self_heal_loop_receipt_*.json`
- `evidence/fusion_control/operator_fusion_mesh_closure_receipt_*.json`

That script runs, in order: optional composite (`GAIAFUSION_SKIP_COMPOSITE=1` skips rebuild), **`scripts/run_fusion_mac_app_gate.py`** (composite + `xcodebuild` + runtime + Playwright), **`GET /api/fusion/self-probe`** on loopback (in-app WASM + bundled **cell_stack** + WKWebView `evaluateJavaScript` DOM snapshot — same information external Playwright targets, without shipping Node inside the `.app`), **HTTP probes** against `/_next/static/...` on the port from `evidence/fusion_control/fusion_mac_app_gate_receipt.json`, then the **Mac full-cell MCP phase** on **`127.0.0.1:8803`** (same `/health` + `/claims?limit=1` rules as WAN — run `docker compose -f docker-compose.fusion-sidecar.yml up -d` first; `GAIAFUSION_SKIP_MAC_CELL_MCP=1` only for sandbox), then the **WAN mesh phase** against each crystal cell’s **MCP gateway** on **`:8803`** so closure is witnessed **from the same compose stack as production** (`fot-mcp-gateway-mesh` → `gaiaos-mcp-server` per `docker-compose.cell.yml`). Heal steps: `docs/GAIAFUSION_MESH_MAC_CELL_HEAL_RUNBOOK.md`.

### Internal HTTP CLI (loopback)

While GaiaFusion is running, operators and automators can call the same JSON the substrate uses:

| Method | Path | Role |
| ------ | ---- | ---- |
| `GET` | `/api/fusion/health` | Klein bottle, WASM surface/runtime, mesh hooks |
| `GET` | `/api/fusion/self-probe` | **Single envelope:** `wasm_surface`, `wasm_runtime`, `cell_stack` (sidecar/MCP compose witness), `dom_analysis` (fusion-s4 DOM markers via WKWebView) |
| `GET` | `/api/sovereign-mesh` | Native mesh + `wasm_runtime_closed` bit |

Shell wrapper: `bash scripts/gaiafusion_internal_cli.sh [PORT]` (defaults `FUSION_UI_PORT` or `8910`). Broader spot-check (loopback + **Mac :8803** + nine-cell MCP): `bash scripts/verify_gaiafusion_internal_surface_suite.sh`. Skip loopback-only: `GAIAFUSION_INTERNAL_SUITE_SKIP_LOOPBACK=1`. Skip local gateway: `GAIAFUSION_INTERNAL_SUITE_SKIP_MAC_CELL=1`.

**Receipt:** `evidence/fusion_control/gaiafusion_working_app_verify_receipt.json` (plus the gate receipt it references).

**Delivery / quality record (GLP-style traceability, IEEE test-doc alignment, MIL-style CM + V&V cross-reference):** `evidence/fusion_control/GAIAFUSION_VERIFICATION_DELIVERY_CLOSURE.md` and machine-readable `evidence/fusion_control/gaiafusion_verification_delivery_manifest.json` — engineering closure package, not a substitute for accredited regulatory certification.

**Environment (common):**

| Variable | Meaning |
| -------- | ------- |
| `GAIAFUSION_SKIP_COMPOSITE=1` | Use pre-built `Resources`; gate skips `build_gaiafusion_composite_assets.sh` |
| `GAIAFUSION_VERIFY_RETRIES` | Gate retries (default `3`) |
| `GAIAFUSION_SKIP_STATIC_PROBES=1` | Skip bundled `/_next/static` HTTP checks |
| `GAIAFUSION_SKIP_MESH_MCP=1` | Skip nine-cell probes (sandbox); receipt shows `mesh_phase: SKIPPED` |
| `GAIAFUSION_SKIP_SELF_PROBE=1` | Skip `/api/fusion/self-probe` check in verify (not recommended on operator runs) |
| `GAIAFTCL_MESH_HOSTS` | Space-separated `name:ip` list (overrides default nine cells) |
| `GAIAFTCL_VERIFY_CELL` | Single `name:ip` (scoped mesh check) |
| `GAIAFUSION_INCLUDE_XCTEST=1` | After verify succeeds, run `swift test` in this package again |
| `GAIAFUSION_RELEASE_PREFLIGHT_SIDECAR_BUNDLE=1` | Before smoke, run **`verify_fusion_sidecar_bundle.sh`** (compose config + canonical sidecar files) |

**Release smoke** (`scripts/run_gaiafusion_release_smoke.sh`) runs **`swift build && swift test`**, then **`verify_gaiafusion_working_app.sh`**, and writes `evidence/fusion_control/gaiafusion_release_smoke_receipt.json`. Optional **sidecar preflight** env above.

WASM instantiate path (WKWebView + HTTP same-origin): `evidence/fusion_control/wasm_substrate_instantiate_path.md`.

### “White screen” with boot / mooring copy only

If **`/fusion-s4`** shows plain text (e.g. GAIAFTCL S4, boot lines) on a near-white background but **no real layout**, the route loaded but **Next assets may not**: **`/_next/static/chunks/*.js`** or **CSS** returned **404** or wrong origin. `ActiveComposite` now exposes:
- `data-testid="fusion-viewport-heartbeat"` (render heartbeat)
- `data-testid="fusion-viewport-fallback"` (explicit non-ready viewport state)

`verify_gaiafusion_working_app.sh` fails closed when probes against the bundled `fusion-web/index.html` references are not HTTP 2xx. Autonomous C4 repair path is `run_operator_fusion_mesh_closure.sh` (includes self-heal loop). Manual C4 fix remains: rebuild composite (`scripts/build_gaiafusion_composite_assets.sh`), confirm `macos/GaiaFusion/GaiaFusion/Resources/fusion-web/_next/static/` exists and matches hashes in `index.html`, and compare `LocalServer.serveFusionAsset` / `serveStatic` behavior for `/_next/*`.

## Run the app

**From Xcode:** open `GaiaFusion.xcodeproj` (or the Swift package in this directory), select scheme **GaiaFusion**, Run.

**From Terminal (SwiftPM):**

```bash
cd GAIAOS/macos/GaiaFusion
swift run GaiaFusion
```

Optional: `FUSION_UI_PORT=8911 swift run GaiaFusion` if the default port conflicts.

**Release build (Metal + Swift release):** `bash scripts/build_gaiafusion_release.sh` — outputs under `GAIAFUSION_BUILD_PATH` (default `/tmp/gaiafusion-release-build`).

On **macOS**, the full Discord closure battery (`scripts/run_closure_battery.sh`) runs release smoke as step **B7** after the web fusion battery unless `CLOSURE_GAIAFUSION_RELEASE_SMOKE=0`.

## Config menu

- **Config → Open fusion_cell config (runner)** (`⌘⇧O`) opens `deploy/fusion_cell/config.json` when your checkout includes it (same file the long-run runner uses).

Norwich — **S⁴ serves C⁴.**
