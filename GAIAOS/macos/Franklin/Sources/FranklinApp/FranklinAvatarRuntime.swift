import AppKit
import Foundation
import Metal
import SceneKit
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
    private var lastFrameTick: CFAbsoluteTime?

    init() {
        bridgeVersion = FranklinRustBridge.shared.version
        assetBinding = FranklinAvatarAssetBinding.load()
        if !assetBinding.passyAssetSetReady {
            lastRefusal = "GW_REFUSE_AVATAR_PASSY_ASSET_SET_MISSING"
        } else if !assetBinding.meshLoaded {
            lastRefusal = "GW_REFUSE_AVATAR_MESH_ASSET_MISSING"
        } else if !assetBinding.meshDetailSufficient {
            lastRefusal = "GW_REFUSE_AVATAR_MESH_DETAIL_INSUFFICIENT"
        } else if assetBinding.visemeCount < 11 {
            lastRefusal = "GW_REFUSE_AVATAR_RIG_VISEME_CARDINALITY"
        } else if assetBinding.expressionCount < 12 {
            lastRefusal = "GW_REFUSE_AVATAR_RIG_EXPRESSION_CARDINALITY"
        } else if assetBinding.postureCount < 6 {
            lastRefusal = "GW_REFUSE_AVATAR_RIG_POSTURE_CARDINALITY"
        }
        // #region agent log
        FranklinDebugLogger.log(
            runId: "pre-fix",
            hypothesisId: "H3",
            location: "FranklinAvatarRuntime.swift:init",
            message: "Avatar runtime initial contract state",
            data: [
                "bridgeVersion": bridgeVersion,
                "meshLoaded": String(assetBinding.meshLoaded),
                "passyAssetSetReady": String(assetBinding.passyAssetSetReady),
                "visemeCount": String(assetBinding.visemeCount),
                "expressionCount": String(assetBinding.expressionCount),
                "postureCount": String(assetBinding.postureCount),
                "lastRefusal": lastRefusal.isEmpty ? "none" : lastRefusal,
            ]
        )
        // #endregion
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
        if !assetBinding.meshDetailSufficient {
            lastRefusal = "GW_REFUSE_AVATAR_MESH_DETAIL_INSUFFICIENT"
            return
        }
        lastFrameMs = frameMs
        if !FranklinRustBridge.shared.validateFrame(frameMs: frameMs, targetHz: targetHz) {
            lastRefusal = "GW_REFUSE_AVATAR_FRAME_BUDGET_OVERRUN"
        } else {
            lastRefusal = ""
        }
    }

    func registerFrameTick(now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) {
        defer { lastFrameTick = now }
        guard let previous = lastFrameTick else { return }
        let frameMs = Float((now - previous) * 1000.0)
        registerFrame(frameMs: frameMs, targetHz: invariants.targetFPS)
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
    let meshDetailSufficient: Bool
    let passyAssetSetReady: Bool
    let missingAssets: [String]

    static let empty = FranklinAvatarAssetBinding(
        meshAssetPath: "",
        visemeCount: 0,
        expressionCount: 0,
        postureCount: 0,
        meshLoaded: false,
        meshDetailSufficient: false,
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
            let meshDetailSufficient = mesh.flatMap { isMeshDetailSufficient(at: $0) } ?? false
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
                    meshDetailSufficient: meshDetailSufficient,
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
            "Franklin_Passy_V2.usdz",
            "Franklin_Passy_V2.usdc",
            "Franklin_Passy_V2.usda",
            "franklin_passy_v1.usdz",
            "franklin_passy_v1.usda",
            "franklin_passy_v1.usdc",
            "franklin_passy_v1.obj",
            "franklin_passy_v1.gltf",
        ]
        for name in candidates {
            let path = meshes.appendingPathComponent(name)
            if fm.fileExists(atPath: path.path) {
                return path
            }
        }
        return nil
    }

    private static func isMeshDetailSufficient(at url: URL) -> Bool {
        guard let bytes = fileSize(path: url.path), bytes >= 5_000_000 else { return false }
        guard let scene = try? SCNScene(url: url, options: nil) else { return false }
        var geometryNodeCount = 0
        scene.rootNode.enumerateChildNodes { node, _ in
            if node.geometry != nil {
                geometryNodeCount += 1
            }
        }
        return geometryNodeCount >= 6
    }
}

struct FranklinPostureTemplate: Decodable {
    let id: String
    let geometry_pin: [Float]
}

final class FranklinSceneRenderer: NSObject {
    private(set) var postureTemplates: [String: FranklinPostureTemplate] = [:]

    func loadPostureTemplates(from binding: FranklinAvatarAssetBinding) {
        guard !binding.meshAssetPath.isEmpty else { return }
        let meshURL = URL(fileURLWithPath: binding.meshAssetPath)
        let postureDir = meshURL.deletingLastPathComponent()
            .appendingPathComponent("../pose_templates/posture")
            .standardizedFileURL
        guard let files = try? FileManager.default.contentsOfDirectory(at: postureDir, includingPropertiesForKeys: nil) else {
            return
        }
        let decoder = JSONDecoder()
        for file in files where file.pathExtension == "json" {
            guard
                let data = try? Data(contentsOf: file),
                let template = try? decoder.decode(FranklinPostureTemplate.self, from: data)
            else { continue }
            let key = file.deletingPathExtension().lastPathComponent
            postureTemplates[key] = template
        }
    }
}

struct FranklinAvatarRuntimeView: NSViewRepresentable {
    @ObservedObject var controller: FranklinAvatarSceneController

    func makeCoordinator() -> FranklinSceneRenderer {
        let renderer = FranklinSceneRenderer()
        renderer.loadPostureTemplates(from: controller.assetBinding)
        return renderer
    }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.preferredFramesPerSecond = Int(controller.invariants.targetFPS)
        view.backgroundColor = NSColor(calibratedRed: 0.12, green: 0.10, blue: 0.08, alpha: 1.0)
        view.rendersContinuously = true
        view.autoenablesDefaultLighting = false
        view.scene = makeScene(context: context)
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        if nsView.scene == nil {
            nsView.scene = makeScene(context: context)
        }
        applyPosture(controller.currentPosture, to: nsView.scene, using: context.coordinator.postureTemplates)
    }

    private func makeScene(context: Context) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor(calibratedRed: 0.12, green: 0.10, blue: 0.08, alpha: 1.0)

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 6.0)
        scene.rootNode.addChildNode(cameraNode)

        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .omni
        keyLight.light?.intensity = 1000
        keyLight.position = SCNVector3(1.5, 1.8, 4.0)
        scene.rootNode.addChildNode(keyLight)

        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .ambient
        fillLight.light?.intensity = 300
        scene.rootNode.addChildNode(fillLight)

        if let avatarRoot = loadAvatarNode() {
            avatarRoot.name = "franklin-avatar-root"
            scene.rootNode.addChildNode(avatarRoot)
        }
        _ = loadPassyMaterialLibrary()
        return scene
    }

    private func applyPosture(
        _ posture: FranklinAvatarPosture,
        to scene: SCNScene?,
        using templates: [String: FranklinPostureTemplate]
    ) {
        guard let node = scene?.rootNode.childNode(withName: "franklin-avatar-root", recursively: true) else { return }
        let templateName = switch posture {
        case .idle: "greet_aside"
        case .listening: "lean_forward_listen"
        case .speaking: "write_quill_pause"
        case .refusing: "refuse_terminal"
        case .recording: "recline_consider"
        }
        guard let template = templates[templateName] else { return }
        let pin = template.geometry_pin
        if pin.count >= 3 {
            node.position = SCNVector3(pin[0], pin[1], pin[2])
        }
        if pin.count >= 4 {
            node.eulerAngles = SCNVector3(0, pin[3], 0)
        }
    }

    private func loadAvatarNode() -> SCNNode? {
        let path = controller.assetBinding.meshAssetPath
        guard !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        if let scene = try? SCNScene(url: url, options: nil) {
            let root = SCNNode()
            for child in scene.rootNode.childNodes {
                root.addChildNode(child)
            }
            applyPassyMaterials(to: root)
            root.scale = SCNVector3(1.2, 1.2, 1.2)
            return root
        }
        return nil
    }

    private func applyPassyMaterials(to root: SCNNode) {
        guard let bundleRoot = URL(fileURLWithPath: controller.assetBinding.meshAssetPath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .standardizedFileURL as URL?
        else { return }
        let capLUT = bundleRoot.appendingPathComponent("spectral_luts/beaver_cap_spectral_lut.exr")
        let flowMap = bundleRoot.appendingPathComponent("spectral_luts/anisotropic_flow_map.exr")
        let silkLUT = bundleRoot.appendingPathComponent("spectral_luts/claret_silk_degradation.exr")
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = NSColor(calibratedRed: 0.40, green: 0.34, blue: 0.28, alpha: 1.0)
        if FileManager.default.fileExists(atPath: capLUT.path) {
            material.metalness.contents = capLUT.path
        }
        if FileManager.default.fileExists(atPath: flowMap.path) {
            material.normal.contents = flowMap.path
        }
        if FileManager.default.fileExists(atPath: silkLUT.path) {
            material.roughness.contents = silkLUT.path
        }
        root.enumerateChildNodes { node, _ in
            guard let geometry = node.geometry else { return }
            geometry.materials = [material]
        }
    }

    private func loadPassyMaterialLibrary() -> MTLLibrary? {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            !controller.assetBinding.meshAssetPath.isEmpty
        else { return nil }
        let bundleRoot = URL(fileURLWithPath: controller.assetBinding.meshAssetPath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .standardizedFileURL
        let libraryURL = bundleRoot.appendingPathComponent("materials/Franklin_Z3_Materials.metallib")
        guard FileManager.default.fileExists(atPath: libraryURL.path) else { return nil }
        return try? device.makeLibrary(URL: libraryURL)
    }
}
