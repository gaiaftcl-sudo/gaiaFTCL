import Foundation
import SwiftUI

#if canImport(RealityKit)
import RealityKit
#endif

enum SubstrateStatus: Equatable {
    case temperate
    case failing(error: String)
}

enum SubstrateError: Error {
    case bridgeRefusal
}

struct RigComponent {
    let v: Int
    let e: Int
    let p: Int
}

@MainActor
final class SovereignBridge {
    static let shared = SovereignBridge()
    private init() {}

    var isConnected: Bool { true }
    var currentDelta: Float { 0.0015 }

    func logReceipt(_ vQbit: Float, fps: Int) {
        _ = (vQbit, fps)
    }
}

@MainActor
final class FranklinRuntime: ObservableObject {
    @Published private(set) var status: SubstrateStatus = .temperate
    private var lastVQbit: Float = 0
    private let rigConfig = RigComponent(v: 11, e: 12, p: 6)
    let targetFPS: Int = 29
    let targetInterval: TimeInterval = 1.0 / 29.0

    private var timer: Timer?

    func initialize() async throws {
        guard BundleAssetLocator.url(
            named: "Franklin_M8",
            ext: "usda",
            fallbackRepoPath: "cells/franklin/avatar/bundle_assets/schemas/Franklin_M8.usda"
        ) != nil else {
            status = .failing(error: "Missing Franklin_M8.usda")
            return
        }
        guard BundleAssetLocator.url(
            named: "Franklin_Data",
            ext: "json",
            fallbackRepoPath: "cells/franklin/avatar/bundle_assets/manifests/Franklin_Data.json"
        ) != nil else {
            status = .failing(error: "Missing Franklin_Data.json")
            return
        }
        if !SovereignBridge.shared.isConnected {
            throw SubstrateError.bridgeRefusal
        }
        status = .temperate
        startLoop()
    }

    private func startLoop() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: targetInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.renderStep() }
        }
    }

    private func renderStep() {
        let vQbit = SovereignBridge.shared.currentDelta
        guard abs(vQbit - lastVQbit) > 0.0001 else { return }
        applyDelta(vQbit)
        SovereignBridge.shared.logReceipt(vQbit, fps: targetFPS)
        lastVQbit = vQbit
    }

    private func applyDelta(_ delta: Float) {
        _ = (delta, rigConfig.v, rigConfig.e, rigConfig.p)
    }
}

enum BundleAssetLocator {
    static func url(named: String, ext: String, fallbackRepoPath: String) -> URL? {
        if let bundled = Bundle.main.url(forResource: named, withExtension: ext) {
            return bundled
        }
        let fm = FileManager.default
        var cursor = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        for _ in 0..<10 {
            let candidate = cursor.appendingPathComponent(fallbackRepoPath)
            if fm.fileExists(atPath: candidate.path) { return candidate }
            cursor.deleteLastPathComponent()
        }
        return nil
    }
}
