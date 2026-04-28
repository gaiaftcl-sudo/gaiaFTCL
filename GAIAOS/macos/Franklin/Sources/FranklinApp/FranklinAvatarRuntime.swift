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
        if !assetBinding.meshLoaded {
            lastRefusal = "GW_REFUSE_AVATAR_MESH_ASSET_MISSING"
        }
    }

    func apply(posture: FranklinAvatarPosture) {
        currentPosture = posture
    }

    func updateSpeech(text: String) {
        guard assetBinding.meshLoaded else { return }
        activeViseme = FranklinRustBridge.shared.firstViseme(for: text)
    }

    func registerFrame(frameMs: Float, targetHz: UInt16) {
        if !assetBinding.meshLoaded {
            lastRefusal = "GW_REFUSE_AVATAR_MESH_ASSET_MISSING"
            return
        }
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
                let mesh = resolveMeshAsset(in: bundlePath)
                return FranklinAvatarAssetBinding(
                    meshAssetPath: mesh?.path ?? "",
                    visemeCount: visemes,
                    expressionCount: expressions,
                    postureCount: postures,
                    meshLoaded: mesh != nil
                )
            }
            cursor.deleteLastPathComponent()
        }
        return .empty
    }

    private static func resolveMeshAsset(in bundlePath: URL) -> URL? {
        let fm = FileManager.default
        let meshes = bundlePath.appendingPathComponent("meshes", isDirectory: true)
        let candidates = [
            "franklin_passy_v1.usdz",
            "franklin_passy_v1.usda",
            "franklin_passy_v1.usdc",
            "franklin_passy_v1.obj",
            "franklin_passy_v1.gltf",
            "franklin_passy_v1.glb",
        ]
        for name in candidates {
            let path = meshes.appendingPathComponent(name)
            if fm.fileExists(atPath: path.path) {
                return path
            }
        }
        return nil
    }
}

final class FranklinMetalRenderer: NSObject, MTKViewDelegate {
    private weak var controller: FranklinAvatarSceneController?
    private var queue: MTLCommandQueue?
    private var pulse: Double = 0

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
        pulse += 0.04
        let glow = 0.06 * (sin(pulse) + 1.0)
        switch controller.currentPosture {
        case .idle:
            if controller.assetBinding.meshLoaded {
                view.clearColor = MTLClearColor(red: 0.44 + glow, green: 0.40 + glow * 0.6, blue: 0.32 + glow * 0.2, alpha: 1)
            } else {
                view.clearColor = MTLClearColor(red: 0.46, green: 0.14, blue: 0.14, alpha: 1)
            }
        case .listening:
            view.clearColor = MTLClearColor(red: 0.30, green: 0.40 + glow, blue: 0.52, alpha: 1)
        case .speaking:
            view.clearColor = MTLClearColor(red: 0.25, green: 0.44 + glow, blue: 0.44, alpha: 1)
        case .refusing:
            view.clearColor = MTLClearColor(red: 0.56 + glow * 0.3, green: 0.20, blue: 0.20, alpha: 1)
        case .recording:
            view.clearColor = MTLClearColor(red: 0.52 + glow * 0.3, green: 0.36 + glow * 0.4, blue: 0.20, alpha: 1)
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
        view.clearColor = MTLClearColor(red: 0.48, green: 0.42, blue: 0.33, alpha: 1.0)
        view.colorPixelFormat = .bgra8Unorm
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        // MTKView redraws continuously via preferredFramesPerSecond.
    }
}
