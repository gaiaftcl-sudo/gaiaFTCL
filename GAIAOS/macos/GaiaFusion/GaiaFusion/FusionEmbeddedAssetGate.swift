import Foundation

/// Same contract as `scripts/run_fusion_mac_app_gate.py` composite artifacts: the Mac app is a closed surface (Klein-bottle closure: S⁴ witness must not depend on an external limb for identity of shipped assets).
enum FusionEmbeddedAssetGate {
    private static let fusionWebDirName = "fusion-web"
    private static let embedExpandedDefaultsKey = "gaiaftcl_fusion_web_embed_expanded_v1"

    /// Optional shipped archive in the app bundle; expanded once into Application Support (see `materializeEmbeddedArchiveIfNeeded()`).
    private static let embeddedArchiveBaseName = "fusion_web_embed"

    struct Witness: Sendable {
        let kleinBottleClosed: Bool
        let defaultMetallibPresent: Bool
        let fusionWebRoot: String?
        let requiredPathsOk: [String: Bool]
        let missing: [String]

        var jsonObject: [String: Any] {
            [
                "closed": kleinBottleClosed,
                "default_metallib_present": defaultMetallibPresent,
                "fusion_web_root": fusionWebRoot as Any,
                "required_paths": requiredPathsOk,
                "missing": missing,
            ]
        }
    }

    // MARK: - Public

    /// Full witness for `/api/fusion/health` and invariant parity with the Python gate.
    static func witness() -> Witness {
        materializeEmbeddedArchiveIfNeeded()
        let metallibOk = metallibPresentInResourceBundle()
        let root = resolveFusionWebRootPreferringComplete()
        let fusionEval = root.map { evaluateFusionWeb(at: $0) }
        let fusionOk = fusionEval?.ok ?? false
        var missing = fusionEval?.missing ?? ["fusion-web"]
        if !metallibOk {
            missing.append("default.metallib")
        }
        missing = Array(Set(missing)).sorted()
        let closed = fusionOk && metallibOk
        return Witness(
            kleinBottleClosed: closed,
            defaultMetallibPresent: metallibOk,
            fusionWebRoot: root?.path,
            requiredPathsOk: fusionEval?.required ?? [:],
            missing: closed ? [] : missing
        )
    }

    /// First directory that satisfies the composite `fusion-web` layout (or nil).
    static func resolvedFusionWebRootForServing() -> URL? {
        materializeEmbeddedArchiveIfNeeded()
        return resolveFusionWebRootPreferringComplete()
    }

    /// One-shot: if `fusion_web_embed.tar.gz` or `fusion_web_embed.zip` exists in the resource bundle (`Bundle.module`), extract to Application Support and reuse on subsequent launches.
    static func materializeEmbeddedArchiveIfNeeded() {
        if UserDefaults.standard.bool(forKey: embedExpandedDefaultsKey) {
            return
        }
        let destParent = applicationSupportGaiaFusionDirectory()
        let dest = destParent.appendingPathComponent(fusionWebDirName, isDirectory: true)
        if FileManager.default.fileExists(atPath: dest.appendingPathComponent("index.html").path) {
            UserDefaults.standard.set(true, forKey: embedExpandedDefaultsKey)
            return
        }
        guard let archive =
            Bundle.module.url(forResource: embeddedArchiveBaseName, withExtension: "tar.gz")
            ?? Bundle.module.url(forResource: embeddedArchiveBaseName, withExtension: "zip")
            ?? Bundle.main.url(forResource: embeddedArchiveBaseName, withExtension: "tar.gz")
            ?? Bundle.main.url(forResource: embeddedArchiveBaseName, withExtension: "zip")
        else {
            return
        }
        try? FileManager.default.createDirectory(at: destParent, withIntermediateDirectories: true)
        if archive.pathExtension == "gz" || archive.lastPathComponent.hasSuffix(".tar.gz") {
            runTarExtract(archive: archive, destination: destParent)
        } else {
            runDittoZip(archive: archive, destination: dest)
        }
        if FileManager.default.fileExists(atPath: dest.appendingPathComponent("index.html").path) {
            UserDefaults.standard.set(true, forKey: embedExpandedDefaultsKey)
            print("GaiaFusion: expanded embedded fusion_web archive into Application Support.")
        }
    }

    // MARK: - Evaluation

    private static func metallibPresent(resourcesRoot: URL?) -> Bool {
        guard let resourcesRoot else {
            return false
        }
        let path = resourcesRoot.appendingPathComponent("default.metallib").path
        return FileManager.default.fileExists(atPath: path)
    }

    /// SwiftPM ships processed resources under `GaiaFusion_GaiaFusion.bundle` (`Bundle.module`), not `Bundle.main` when running the `.build` binary.
    private static func metallibPresentInResourceBundle() -> Bool {
        if let u = Bundle.module.url(forResource: "default", withExtension: "metallib") {
            return FileManager.default.fileExists(atPath: u.path)
        }
        return metallibPresent(resourcesRoot: Bundle.module.resourceURL)
    }

    private static func evaluateFusionWeb(at root: URL) -> (ok: Bool, required: [String: Bool], missing: [String]) {
        var required: [String: Bool] = [:]
        var missing: [String] = []
        let pairs: [(String, URL)] = [
            ("index.html", root.appendingPathComponent("index.html")),
            ("substrate.html", root.appendingPathComponent("substrate.html")),
            ("_next/static", root.appendingPathComponent("_next/static")),
        ]
        for (name, url) in pairs {
            let ok: Bool
            if name == "_next/static" {
                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                let kids = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
                ok = exists && isDir.boolValue && !kids.isEmpty
            } else {
                ok = FileManager.default.fileExists(atPath: url.path)
            }
            required[name] = ok
            if !ok {
                missing.append(name)
            }
        }
        return (missing.isEmpty, required, missing)
    }

    private static func resolveFusionWebRootPreferringComplete() -> URL? {
        let candidates: [URL?] = [
            Bundle.module.resourceURL?.appendingPathComponent(fusionWebDirName),
            Bundle.main.resourceURL?.appendingPathComponent(fusionWebDirName),
            applicationSupportFusionWebURL(),
            URL(filePath: "./GaiaFusion/Resources/\(fusionWebDirName)", relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).absoluteURL,
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("GaiaFusion")
                .appendingPathComponent(fusionWebDirName),
        ]
        for c in candidates {
            guard let c else { continue }
            guard (try? c.checkResourceIsReachable()) == true else { continue }
            if evaluateFusionWeb(at: c).ok {
                return c
            }
        }
        for c in candidates {
            guard let c else { continue }
            guard (try? c.checkResourceIsReachable()) == true else { continue }
            return c
        }
        return nil
    }

    private static func applicationSupportGaiaFusionDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GaiaFusion", isDirectory: true)
    }

    private static func applicationSupportFusionWebURL() -> URL {
        applicationSupportGaiaFusionDirectory().appendingPathComponent(fusionWebDirName, isDirectory: true)
    }

    private static func runTarExtract(archive: URL, destination: URL) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        proc.arguments = ["-xzf", archive.path, "-C", destination.path]
        try? proc.run()
        proc.waitUntilExit()
    }

    private static func runDittoZip(archive: URL, destination: URL) {
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-x", "-k", archive.path, destination.path]
        try? proc.run()
        proc.waitUntilExit()
    }
}
