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
    let invariants = FranklinInvariants()

    init() {
        bridgeVersion = FranklinRustBridge.shared.version
        assetBinding = FranklinAvatarAssetBinding.load()
        if !assetBinding.passyAssetSetReady {
            lastRefusal = "GW_REFUSE_AVATAR_PASSY_ASSET_SET_MISSING"
        } else if !assetBinding.meshLoaded {
            lastRefusal = "GW_REFUSE_AVATAR_MESH_ASSET_MISSING"
        } else if assetBinding.visemeCount < 11 {
            lastRefusal = "GW_REFUSE_AVATAR_RIG_VISEME_CARDINALITY"
        } else if assetBinding.expressionCount < 12 {
            lastRefusal = "GW_REFUSE_AVATAR_RIG_EXPRESSION_CARDINALITY"
        } else if assetBinding.postureCount < 6 {
            lastRefusal = "GW_REFUSE_AVATAR_RIG_POSTURE_CARDINALITY"
        }
    }

    func apply(posture: FranklinAvatarPosture) {
        currentPosture = posture
    }

    func updateSpeech(text: String) {
        guard assetBinding.meshLoaded else { return }
        guard lastRefusal.isEmpty || !lastRefusal.hasPrefix("GW_REFUSE_AVATAR_RIG_") else { return }
        let entropy = Float(abs(text.hashValue % 10_000)) / 10_000.0
        guard invariants.allowStateTransition(currentVQbit: entropy) else { return }
        activeViseme = FranklinRustBridge.shared.firstViseme(for: text)
    }

    func registerFrame(frameMs: Float, targetHz: UInt16) {
        if !assetBinding.passyAssetSetReady {
            lastRefusal = "GW_REFUSE_AVATAR_PASSY_ASSET_SET_MISSING"
            return
        }
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
    struct RequiredAsset {
        let label: String
        let relativePath: String
        let minBytes: UInt64
    }

    let meshAssetPath: String
    let visemeCount: Int
    let expressionCount: Int
    let postureCount: Int
    let meshLoaded: Bool
    let passyAssetSetReady: Bool
    let missingAssets: [String]

    static let empty = FranklinAvatarAssetBinding(
        meshAssetPath: "",
        visemeCount: 0,
        expressionCount: 0,
        postureCount: 0,
        meshLoaded: false,
        passyAssetSetReady: false,
        missingAssets: []
    )

    static func load() -> FranklinAvatarAssetBinding {
        let fm = FileManager.default
        var cursor = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        for _ in 0..<10 {
            let bundlePath = cursor.appendingPathComponent("cells/franklin/avatar/bundle_assets")
            let visemePath = bundlePath.appendingPathComponent("pose_templates/viseme")
            let expressionPath = bundlePath.appendingPathComponent("pose_templates/expression")
            let posturePath = bundlePath.appendingPathComponent("pose_templates/posture")
            let visemes = (try? fm.contentsOfDirectory(atPath: visemePath.path).filter { $0.hasSuffix(".json") }.count) ?? 0
            let expressions = (try? fm.contentsOfDirectory(atPath: expressionPath.path).filter { $0.hasSuffix(".json") }.count) ?? 0
            let postures = (try? fm.contentsOfDirectory(atPath: posturePath.path).filter { $0.hasSuffix(".json") }.count) ?? 0
            let mesh = resolveMeshAsset(in: bundlePath)
            let required = requiredAssets()
            let missing = required.compactMap { asset in
                let file = cursor.appendingPathComponent(asset.relativePath)
                guard let size = fileSize(path: file.path) else {
                    return "\(asset.label): missing (\(asset.relativePath))"
                }
                guard size >= asset.minBytes else {
                    return "\(asset.label): too small \(size)B < \(asset.minBytes)B (\(asset.relativePath))"
                }
                return nil
            }

            if mesh != nil || !missing.isEmpty || visemes > 0 || expressions > 0 || postures > 0 {
                return FranklinAvatarAssetBinding(
                    meshAssetPath: mesh?.path ?? "",
                    visemeCount: visemes,
                    expressionCount: expressions,
                    postureCount: postures,
                    meshLoaded: mesh != nil && missing.isEmpty,
                    passyAssetSetReady: missing.isEmpty,
                    missingAssets: missing
                )
            }
            cursor.deleteLastPathComponent()
        }
        return .empty
    }

    private static func requiredAssets() -> [RequiredAsset] {
        [
            RequiredAsset(
                label: "Passy master geometry blob",
                relativePath: "cells/franklin/avatar/bundle_assets/meshes/Franklin_Passy_V2.fblob",
                minBytes: 1_000_000
            ),
            RequiredAsset(
                label: "Z3 material library",
                relativePath: "cells/franklin/avatar/bundle_assets/materials/Franklin_Z3_Materials.metallib",
                minBytes: 50_000
            ),
            RequiredAsset(
                label: "Beaver cap spectral LUT",
                relativePath: "cells/franklin/avatar/bundle_assets/spectral_luts/beaver_cap_spectral_lut.exr",
                minBytes: 10_000
            ),
            RequiredAsset(
                label: "Anisotropic flow map",
                relativePath: "cells/franklin/avatar/bundle_assets/spectral_luts/anisotropic_flow_map.exr",
                minBytes: 10_000
            ),
            RequiredAsset(
                label: "Claret silk degradation map",
                relativePath: "cells/franklin/avatar/bundle_assets/spectral_luts/claret_silk_degradation.exr",
                minBytes: 10_000
            ),
            RequiredAsset(
                label: "StyleTTS2 ANE manifest",
                relativePath: "cells/franklin/avatar/bundle_assets/voice/styletts2_franklin_v1.coreml.mlmodelc/Manifest.json",
                minBytes: 100
            ),
        ]
    }

    private static func fileSize(path: String) -> UInt64? {
        guard
            let attrs = try? FileManager.default.attributesOfItem(atPath: path),
            let size = attrs[.size] as? UInt64
        else { return nil }
        return size
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
        controller.registerFrame(frameMs: elapsed, targetHz: controller.invariants.targetFPS)
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
        view.preferredFramesPerSecond = Int(controller.invariants.targetFPS)
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
