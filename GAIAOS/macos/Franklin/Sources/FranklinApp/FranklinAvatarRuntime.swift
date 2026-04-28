import AppKit
import Foundation
import Metal
import MetalKit
import SwiftUI

enum FranklinAvatarPosture {
    case idle
    case listening
    case speaking
    case refusing
    case recording
}

@MainActor
final class FranklinAvatarSceneController: ObservableObject {
    @Published private(set) var currentPosture: FranklinAvatarPosture = .idle
    @Published private(set) var activeViseme: String = "rest"
    @Published private(set) var bridgeVersion: String = "unavailable"
    @Published private(set) var lastFrameMs: Float = 0
    @Published private(set) var lastRefusal: String = ""
    @Published private(set) var assetBinding = FranklinAvatarAssetBinding.empty

    init() {
        bridgeVersion = FranklinRustBridge.shared.version
        assetBinding = FranklinAvatarAssetBinding.load()
    }

    func apply(posture: FranklinAvatarPosture) {
        currentPosture = posture
    }

    func updateSpeech(text: String) {
        activeViseme = FranklinRustBridge.shared.firstViseme(for: text)
    }

    func registerFrame(frameMs: Float, targetHz: UInt16) {
        lastFrameMs = frameMs
        if !FranklinRustBridge.shared.validateFrame(frameMs: frameMs, targetHz: targetHz) {
            lastRefusal = "GW_REFUSE_AVATAR_FRAME_BUDGET_OVERRUN"
        } else {
            lastRefusal = ""
        }
    }
}

struct FranklinAvatarAssetBinding {
    let meshAssetPath: String
    let visemeCount: Int
    let expressionCount: Int
    let postureCount: Int
    let meshLoaded: Bool

    static let empty = FranklinAvatarAssetBinding(
        meshAssetPath: "",
        visemeCount: 0,
        expressionCount: 0,
        postureCount: 0,
        meshLoaded: false
    )

    static func load() -> FranklinAvatarAssetBinding {
        let fm = FileManager.default
        var cursor = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        for _ in 0..<10 {
            let bundlePath = cursor.appendingPathComponent("cells/franklin/avatar/bundle_assets")
            let visemePath = bundlePath.appendingPathComponent("pose_templates/viseme")
            let expressionPath = bundlePath.appendingPathComponent("pose_templates/expression")
            let posturePath = bundlePath.appendingPathComponent("pose_templates/posture")
            if fm.fileExists(atPath: visemePath.path) {
                let visemes = (try? fm.contentsOfDirectory(atPath: visemePath.path).filter { $0.hasSuffix(".json") }.count) ?? 0
                let expressions = (try? fm.contentsOfDirectory(atPath: expressionPath.path).filter { $0.hasSuffix(".json") }.count) ?? 0
                let postures = (try? fm.contentsOfDirectory(atPath: posturePath.path).filter { $0.hasSuffix(".json") }.count) ?? 0
                let mesh = bundlePath.appendingPathComponent("meshes/franklin_passy_v1.usdz")
                return FranklinAvatarAssetBinding(
                    meshAssetPath: mesh.path,
                    visemeCount: visemes,
                    expressionCount: expressions,
                    postureCount: postures,
                    meshLoaded: fm.fileExists(atPath: mesh.path)
                )
            }
            cursor.deleteLastPathComponent()
        }
        return .empty
    }
}

final class FranklinMetalRenderer: NSObject, MTKViewDelegate {
    private weak var controller: FranklinAvatarSceneController?
    private var queue: MTLCommandQueue?

    init(controller: FranklinAvatarSceneController, device: MTLDevice) {
        self.controller = controller
        self.queue = device.makeCommandQueue()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = queue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor),
              let controller
        else { return }

        let start = CFAbsoluteTimeGetCurrent()
        switch controller.currentPosture {
        case .idle:
            view.clearColor = MTLClearColor(red: 0.18, green: 0.22, blue: 0.26, alpha: 1)
        case .listening:
            view.clearColor = MTLClearColor(red: 0.14, green: 0.20, blue: 0.30, alpha: 1)
        case .speaking:
            view.clearColor = MTLClearColor(red: 0.13, green: 0.29, blue: 0.33, alpha: 1)
        case .refusing:
            view.clearColor = MTLClearColor(red: 0.34, green: 0.10, blue: 0.12, alpha: 1)
        case .recording:
            view.clearColor = MTLClearColor(red: 0.32, green: 0.22, blue: 0.12, alpha: 1)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        let elapsed = Float((CFAbsoluteTimeGetCurrent() - start) * 1000)
        controller.registerFrame(frameMs: elapsed, targetHz: 60)
    }
}

struct FranklinAvatarRuntimeView: NSViewRepresentable {
    @ObservedObject var controller: FranklinAvatarSceneController

    func makeCoordinator() -> FranklinMetalRenderer? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return FranklinMetalRenderer(controller: controller, device: device)
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.preferredFramesPerSecond = 60
        view.clearColor = MTLClearColor(red: 0.16, green: 0.18, blue: 0.20, alpha: 1.0)
        view.colorPixelFormat = .bgra8Unorm
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        nsView.setNeedsDisplay(nsView.bounds)
    }
}
