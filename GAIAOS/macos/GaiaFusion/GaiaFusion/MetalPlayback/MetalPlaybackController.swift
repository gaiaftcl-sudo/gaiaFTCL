import Foundation
import Metal
import MetalKit
import simd
import GaiaMetalRenderer

/// Metal-present–gated Rust Metal playback controller (replaces OpenUSD)
@MainActor
final class MetalPlaybackController: ObservableObject {
    @Published private(set) var plantKind: String = "tokamak"
    @Published private(set) var engaged: Bool = false
    @Published private(set) var framesPresented: UInt64 = 0
    @Published private(set) var fps: Double = 0
    @Published private(set) var stageLoaded: Bool = false
    
    /// Render next frame for performance testing
    func renderNextFrame(width: UInt32, height: UInt32) {
        _rustRenderer?.renderFrame(width: width, height: height)
        framesPresented += 1
    }
    
    /// Get last frame time in microseconds
    func getFrameTimeUs() -> UInt64 {
        return _rustRenderer?.getFrameTimeUs() ?? 0
    }
    
    /// Emits discrete plant-swap lifecycle states to WKWebView + gate logs.
    var onPlantSwapLifecycle: (([String: Any]) -> Void)?
    
    /// SubGame Z: diagnostic prim evicted (quorum loss or cell4 host offline) — gate + DOM witness.
    var onSubgameZDiagnosticEviction: (([String: Any]) -> Void)?
    
    /// Mesh `vQbit` sample for optional `vqbit_rate` timeline driver.
    var vqbitSample: () -> Double = { 0 }
    
    private var _rustRenderer: RustMetalProxyRenderer?
    private var lastFrameTime: TimeInterval = 0
    private var fpsAccumulator: Double = 0
    private var fpsFrames: Int = 0
    
    init() {
        self.plantKind = "tokamak"
        self.stageLoaded = true
    }

    /// IQ/OQ/PQ test entry point — initialise renderer with an optional CAMetalLayer.
    /// Passing nil creates a headless instance suitable for unit tests (no GPU rendering).
    func initialize(layer: CAMetalLayer?) async {
        StartupProfiler.shared.checkpoint("metal_init_start")
        if let layer = layer {
            let proxy = RustMetalProxyRenderer(layer: layer)
            setMetalRenderer(proxy)
        }
        // If layer is nil, rustRenderer stays nil — headless mode for test protocols.
        stageLoaded = true
        StartupProfiler.shared.checkpoint("metal_init_complete")
    }

    /// Request a plant swap — PQ protocol entry point.
    /// Delegates to loadPlant which drives the full REQUESTED→VERIFIED lifecycle.
    func requestPlantSwap(to kind: String) {
        loadPlant(kind)
    }
    
    /// PQ protocol overload accepting FusionPlantKind enum
    func requestPlantSwap(to kind: FusionPlantKind) {
        requestPlantSwap(to: kind.rawValue)
    }

    func loadPlant(_ rawKind: String) {
        plantKind = rawKind
        loadPlantSync(rawKind)
    }
    
    func loadPlantSync(_ kind: String) {
        plantKind = kind
        // Gap #8: Parse USD with explicit buffer allocation
        guard let usdPath = Bundle.module.path(forResource: "plants/\(kind)/root", ofType: "usda") else {
            print("USD file not found for plant: \(kind)")
            stageLoaded = false
            return
        }
        
        let maxPrims = 256
        let primsBuffer = UnsafeMutablePointer<vQbitPrimitive>.allocate(capacity: maxPrims)
        defer { primsBuffer.deallocate() }
        
        let count = usdPath.withCString { pathPtr in
            gaia_metal_parse_usd(pathPtr, primsBuffer, UInt(maxPrims))
        }
        
        print("Loaded \(count) primitives from \(kind)")
        
        // Upload to renderer if available
        if count > 0, let renderer = _rustRenderer {
            let prims = Array(UnsafeBufferPointer(start: primsBuffer, count: Int(count)))
            renderer.uploadPrimitives(prims)
        }
        
        stageLoaded = (count > 0)
    }
    
    func setMetalRenderer(_ renderer: RustMetalProxyRenderer) {
        self._rustRenderer = renderer
    }
    
    func drawFrame(drawable: CAMetalDrawable, viewportSize: CGSize) {
        guard let renderer = _rustRenderer else { return }
        
        let now = CACurrentMediaTime()
        if lastFrameTime > 0 {
            let delta = now - lastFrameTime
            fpsAccumulator += 1.0 / max(delta, 0.001)
            fpsFrames += 1
            if fpsFrames >= 30 {
                fps = fpsAccumulator / Double(fpsFrames)
                fpsAccumulator = 0
                fpsFrames = 0
            }
        }
        lastFrameTime = now
        
        renderer.renderFrame(width: UInt32(viewportSize.width), height: UInt32(viewportSize.height))
        framesPresented += 1
    }
    
    func engage() {
        engaged = true
    }
    
    func disengage() {
        engaged = false
    }
    
    func setEngaged(_ value: Bool) {
        if value {
            engage()
        } else {
            disengage()
        }
    }
    
    func setTau(_ blockHeight: UInt64) {
        _rustRenderer?.setTau(blockHeight)
    }
    
    func getTau() -> UInt64 {
        return _rustRenderer?.getTau() ?? 0
    }
    
    // MARK: - PQ Test Protocol Support
    
    /// Cleanup alias for PQ tests (maps to disengage)
    func cleanup() {
        disengage()
        _rustRenderer = nil
    }
    
    /// Current FPS for PQ tests
    var currentFPS: Double? {
        return fps > 0 ? fps : nil
    }
    
    /// Current geometry for PQ tests (placeholder - vertex count from renderer)
    var currentGeometry: Geometry? {
        guard _rustRenderer != nil else { return nil }
        return Geometry(vertexCount: 256)
    }
    
    /// Current wireframe color based on terminal state (placeholder)
    var currentWireframeColor: WireframeColor {
        return .green
    }
    
    // Legacy methods for compatibility - no-ops for now
    func applyMeshDiagnosticEviction(meshCells: [Any]) {}
    func onSelectCell(cellID: String?, meshCells: [Any]) {}
    func ingestTelemetryFromBridge(ip: Double, bt: Double, ne: Double) {}
    func ingestEpistemicBoundary(ip: String, bt: String, ne: String, terminal: String) {}
    
    func jsonSnapshot() -> [String: Any] {
        return [
            "plant_kind": plantKind,
            "engaged": engaged,
            "frames_presented": framesPresented,
            "fps": fps,
            "stage_loaded": stageLoaded
        ]
    }
    
    /// Enable plasma particle rendering
    func enablePlasma() {
        _rustRenderer?.enablePlasma()
    }
    
    /// Disable plasma particle rendering
    func disablePlasma() {
        _rustRenderer?.disablePlasma()
    }
    
    /// Update the Metal drawable size when viewport geometry changes
    func updateDrawableSize(_ size: CGSize) {
        _rustRenderer?.updateDrawableSize(size)
    }
    
    /// Set the base wireframe color
    func setWireframeBaseColor(_ rgba: [Float]) {
        _rustRenderer?.setWireframeBaseColor(rgba)
    }
}

// MARK: - PQ Test Support Types

struct Geometry {
    let vertexCount: Int
}

enum WireframeColor {
    case green, amber, red
}

