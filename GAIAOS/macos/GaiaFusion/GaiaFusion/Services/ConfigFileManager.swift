import Foundation

struct FileTreeNode: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let isDirectory: Bool
    let children: [FileTreeNode]?

    init(name: String, url: URL, isDirectory: Bool, children: [FileTreeNode]? = nil) {
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.children = children
        self.id = url.path
    }
}

struct ConfigFileManager {
    private let repositoryRoot: URL
    private let fm = FileManager.default
    private let configSearchRoots = [
        "deploy/fusion_cell/",
        "config/"
    ]

    init(repositoryRoot: URL = ConfigFileManager.discoverRepositoryRoot()) {
        self.repositoryRoot = repositoryRoot
    }

    func fileTree(for relativeRoot: String, maxDepth: Int = 6) -> [FileTreeNode] {
        guard let root = directoryURL(for: relativeRoot) else {
            return []
        }
        return treeNodes(for: root, depth: maxDepth)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func readText(from fileURL: URL) -> String? {
        guard fileURL.isFileURL, fm.fileExists(atPath: fileURL.path) else {
            return nil
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func write(text: String, to fileURL: URL) throws {
        guard let data = text.data(using: .utf8) else {
            throw NSError(
                domain: "ConfigFileManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to encode text"]
            )
        }
        try data.write(to: fileURL, options: .atomic)
    }

    func isValidJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            return false
        }
        do {
            _ = try JSONSerialization.jsonObject(with: data)
            return true
        } catch {
            return false
        }
    }

    /// Same file consumed by `scripts/fusion_cell_long_run_runner.sh` when present in the repo checkout.
    func fusionCellRuntimeConfigURL() -> URL? {
        let url = repositoryRoot.appendingPathComponent("deploy/fusion_cell/config.json")
        guard fm.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    func fileForCellConfig(cellID: String, relativeRoot: String? = nil) -> URL? {
        let roots = configRoots(override: relativeRoot)
        for root in roots {
            if root == "deploy/fusion_cell/" || root == "deploy/fusion_cell" {
                let runtimeRoot = directoryURL(for: root)
                let runtimeConfig = runtimeRoot?.appendingPathComponent("config.json")
                if let runtimeConfig, fm.fileExists(atPath: runtimeConfig.path) {
                    return runtimeConfig
                }
            }

            let nodes = fileTree(for: root)
            var queue = nodes
            let search = cellID.lowercased()
            while let node = queue.popLast() {
                if node.isDirectory, let children = node.children {
                    queue.append(contentsOf: children)
                    continue
                }
                let nameMatch = node.name.lowercased().contains(search)
                let pathMatch = node.url.lastPathComponent.lowercased().contains(search)
                if (nameMatch || pathMatch) && ["json", "toml", "yaml", "yml", "conf"].contains(node.url.pathExtension.lowercased()) {
                    return node.url
                }
            }
        }
        return nil
    }

    private func configRoots(override: String?) -> [String] {
        if let override {
            return [override]
        }
        return configSearchRoots
    }

    func modificationLabel(for fileURL: URL) -> String {
        guard let attr = try? fm.attributesOfItem(atPath: fileURL.path),
              let date = attr[.modificationDate] as? Date else {
            return ""
        }
        let formatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func directoryURL(for relativeRoot: String) -> URL? {
        let candidate = repositoryRoot.appendingPathComponent(relativeRoot)
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return candidate
    }

    private func treeNodes(for directoryURL: URL, depth: Int) -> [FileTreeNode] {
        guard depth > 0 else { return [] }
        guard let urls = try? fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let nodes = urls.compactMap { url -> FileTreeNode? in
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = resourceValues?.isDirectory ?? false
            if isDirectory {
                let children = treeNodes(for: url, depth: depth - 1)
                return FileTreeNode(
                    name: url.lastPathComponent,
                    url: url,
                    isDirectory: true,
                    children: children
                )
            }
            guard ["json", "txt", "toml", "yaml", "yml", "conf"].contains(url.pathExtension.lowercased()) else {
                return nil
            }
            return FileTreeNode(name: url.lastPathComponent, url: url, isDirectory: false)
        }

        return nodes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func discoverRepositoryRoot() -> URL {
        let fm = FileManager.default
        var current = URL(fileURLWithPath: fm.currentDirectoryPath)
        for _ in 0..<12 {
            if current.lastPathComponent == "GAIAOS" {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent == current { break }
            current = parent
        }

        let homeRoot = fm.homeDirectoryForCurrentUser
        let fallback = homeRoot.appendingPathComponent("Documents").appendingPathComponent("FoT8D").appendingPathComponent("GAIAOS")
        if fm.fileExists(atPath: fallback.path) {
            return fallback
        }
        return URL(fileURLWithPath: fm.currentDirectoryPath)
    }
}
