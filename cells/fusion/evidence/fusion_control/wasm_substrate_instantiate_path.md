# GaiaFusion — WASM substrate instantiate path (C4)

**Date:** 2026-04-09

- **Bundle:** `macos/GaiaFusion/GaiaFusion/Resources/gaiafusion_substrate.wasm` (minimal module or `wasm-pack` output from `services/atc_physics_wasm` via `scripts/build_gaiafusion_wasm_pack.sh`).
- **Same-origin gate (WKWebView):** `GET /api/fusion/wasm-substrate` on [`LocalServer`](../../macos/GaiaFusion/GaiaFusion/LocalServer.swift) serves `Content-Type: application/wasm`. WKWebView `fetch('gaiasubstrate://…')` often returns **Load failed** — the HTTP route is the supported instantiate path.
- **Optional scheme:** `gaiasubstrate://local/gaiafusion_substrate.wasm` — [`WasmSchemeHandler`](../../macos/GaiaFusion/GaiaFusion/FusionWebView.swift) (not used for the default runtime witness).
- **Preferred:** `WebAssembly.instantiateStreaming(fetch(/api/fusion/wasm-substrate))`.
- **Fallback:** second `fetch` → `arrayBuffer()` → `WebAssembly.instantiate` if streaming fails.
- **Witness:** `window.webkit.messageHandlers.wasmRuntime` → [`FusionBridge`](../../macos/GaiaFusion/GaiaFusion/FusionBridge.swift); **`/api/fusion/health`** exposes **`wasm_runtime`** (separate from **`wasm_surface`** DOM witness).

Norwich — **S⁴ serves C⁴.**
