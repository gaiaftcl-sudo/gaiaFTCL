// MetalHealthView.swift — MacHealth
// NSViewRepresentable wrapping a CAMetalLayer for the health renderer
import SwiftUI
import Metal
import QuartzCore

struct MetalHealthView: NSViewRepresentable {
    @ObservedObject var viewModel: BioStateViewModel

    func makeNSView(context: Context) -> MetalHostView {
        let v = MetalHostView()
        v.wantsLayer = true
        return v
    }

    func updateNSView(_ nsView: MetalHostView, context: Context) {
        nsView.update(epistemicTag: viewModel.epistemicTag, frameCount: viewModel.frameCount)
    }
}

final class MetalHostView: NSView {
    private var metalLayer: CAMetalLayer?
    private var device: MTLDevice?
    private var queue:  MTLCommandQueue?

    override func makeBackingLayer() -> CALayer {
        let ml = CAMetalLayer()
        ml.pixelFormat    = .bgra8Unorm
        ml.framebufferOnly = false
        self.metalLayer    = ml
        self.device        = MTLCreateSystemDefaultDevice()
        self.queue         = device?.makeCommandQueue()
        ml.device          = device
        return ml
    }

    func update(epistemicTag: UInt32, frameCount: UInt64) {
        guard let layer = metalLayer,
              let drawable = layer.nextDrawable(),
              let queue   = queue,
              let cmd     = queue.makeCommandBuffer() else { return }

        // Colour encodes epistemic: M=blue, I=green, A=orange
        let clearColor: MTLClearColor = switch epistemicTag {
            case 0:  MTLClearColor(red: 0.0, green: 0.4, blue: 0.9, alpha: 1.0)   // Measured
            case 1:  MTLClearColor(red: 0.1, green: 0.75, blue: 0.3, alpha: 1.0)  // Inferred
            default: MTLClearColor(red: 0.9, green: 0.5, blue: 0.1, alpha: 1.0)   // Assumed
        }

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture     = drawable.texture
        rpd.colorAttachments[0].loadAction  = .clear
        rpd.colorAttachments[0].clearColor  = clearColor
        rpd.colorAttachments[0].storeAction = .store

        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
}
