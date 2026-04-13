import AppKit
import MetalKit
import SwiftUI

/// Native Metal layer behind transparent `WKWebView` (hole-punch); `frames_presented` increments on `presentDrawable`.
struct FusionMetalViewportView: NSViewRepresentable {
    @ObservedObject var playback: MetalPlaybackController

    func makeCoordinator() -> FusionMetalViewportCoordinator {
        FusionMetalViewportCoordinator(playback: playback)
    }

    func makeNSView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            let view = MTKView(frame: .zero, device: nil)
            view.clearColor = MTLClearColor(red: 0.08, green: 0.1, blue: 0.14, alpha: 1)
            return view
        }
        let view = MTKView(frame: .zero, device: device)
        view.clearColor = MTLClearColor(red: 0.05, green: 0.07, blue: 0.11, alpha: 1.0)
        view.colorPixelFormat = .bgra8Unorm
        // Wireframe pass has no depth attachment — if a depth buffer were present, untested line depth could blank the pass.
        view.depthStencilPixelFormat = .invalid
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator
        view.layer?.isOpaque = true
        context.coordinator.attach(view: view)
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.playback = playback
    }
}

@MainActor
final class FusionMetalViewportCoordinator: NSObject, MTKViewDelegate {
    var playback: MetalPlaybackController
    private weak var mtkView: MTKView?
    private var commandQueue: MTLCommandQueue?
    private var rustRenderer: RustMetalProxyRenderer?

    init(playback: MetalPlaybackController) {
        self.playback = playback
    }

    func attach(view: MTKView) {
        mtkView = view
        if let d = view.device {
            commandQueue = d.makeCommandQueue()
            // Initialize Rust renderer with the Metal layer
            if let metalLayer = view.layer as? CAMetalLayer {
                rustRenderer = RustMetalProxyRenderer(layer: metalLayer)
                playback.setMetalRenderer(rustRenderer!)
            }
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        rustRenderer?.resize(width: UInt32(size.width), height: UInt32(size.height))
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable else { return }
        let size = view.drawableSize
        playback.drawFrame(drawable: drawable, viewportSize: size)
    }
}
