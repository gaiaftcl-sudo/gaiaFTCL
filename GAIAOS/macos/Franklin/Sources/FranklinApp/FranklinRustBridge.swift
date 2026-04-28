import Darwin
import Foundation

typealias FranklinBridgeVersionFn = @convention(c) () -> UnsafePointer<CChar>?
typealias FranklinBridgeValidateFrameFn = @convention(c) (Float, UInt16) -> Bool
typealias FranklinBridgeVisemeFn = @convention(c) (UnsafePointer<CChar>?) -> UnsafePointer<CChar>?

@MainActor
final class FranklinRustBridge {
    static let shared = FranklinRustBridge()

    private var handle: UnsafeMutableRawPointer?
    private var versionFn: FranklinBridgeVersionFn?
    private var validateFrameFn: FranklinBridgeValidateFrameFn?
    private var visemeFn: FranklinBridgeVisemeFn?

    private init() {
        load()
    }

    var isLoaded: Bool { handle != nil }

    var version: String {
        guard let fn = versionFn, let ptr = fn() else { return "unavailable" }
        return String(cString: ptr)
    }

    func validateFrame(frameMs: Float, targetHz: UInt16) -> Bool {
        guard let fn = validateFrameFn else { return false }
        return fn(frameMs, targetHz)
    }

    func firstViseme(for text: String) -> String {
        guard let fn = visemeFn else { return "rest" }
        return text.withCString { cStr in
            guard let ptr = fn(cStr) else { return "rest" }
            return String(cString: ptr)
        }
    }

    private func load() {
        guard let dylib = resolveBridgeDylibPath() else { return }
        handle = dlopen(dylib.path, RTLD_NOW)
        guard let handle else { return }
        versionFn = loadSymbol("franklin_avatar_bridge_version", as: FranklinBridgeVersionFn.self)
        validateFrameFn = loadSymbol("franklin_avatar_validate_frame", as: FranklinBridgeValidateFrameFn.self)
        visemeFn = loadSymbol("franklin_avatar_first_viseme", as: FranklinBridgeVisemeFn.self)
    }

    private func resolveBridgeDylibPath() -> URL? {
        var cursor = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        for _ in 0..<10 {
            let candidate = cursor
                .appendingPathComponent("cells/franklin/avatar/target/release/libavatar_bridge.dylib")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            cursor.deleteLastPathComponent()
        }
        return nil
    }

    private func loadSymbol<T>(_ name: String, as: T.Type) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }
}
