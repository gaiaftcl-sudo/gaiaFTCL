import Foundation

extension RepoRootResolver {
    /// Walks parents from a starting file URL until `cells/health/scripts/health_full_local_iqoqpq_gamp.sh` exists.
    public func discoverWalkingUp(from start: URL) -> URL? {
        var url = start.standardizedFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if !isDir.boolValue { url = url.deletingLastPathComponent() }
        } else {
            return nil
        }
        for _ in 0..<64 {
            let script = url.appendingPathComponent("cells/health/scripts/health_full_local_iqoqpq_gamp.sh")
            if FileManager.default.fileExists(atPath: script.path) { return url }
            let p = url.deletingLastPathComponent()
            if p.path == url.path { break }
            url = p
        }
        return nil
    }
}
