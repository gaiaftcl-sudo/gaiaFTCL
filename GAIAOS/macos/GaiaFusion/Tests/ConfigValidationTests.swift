import Foundation
import XCTest
@testable import GaiaFusion

final class ConfigValidationTests: XCTestCase {
    func testIsValidJSONForWellFormedAndMalformedText() {
        let manager = ConfigFileManager(repositoryRoot: tempRepositoryRoot())
        XCTAssertTrue(manager.isValidJSON("{\"ok\":true}"))
    XCTAssertFalse(manager.isValidJSON("{\"ok\": true,"))
        XCTAssertFalse(manager.isValidJSON("invalid"))
    }

    func testWriteReadRoundTripForJSONFile() throws {
        let root = makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let configDir = root.appendingPathComponent("config", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        let manager = ConfigFileManager(repositoryRoot: root)
        let fileURL = configDir.appendingPathComponent("sample.json")
        let payload = "{\n  \"service\": \"gaiaftcl\",\n  \"mesh\": true\n}"

        try manager.write(text: payload, to: fileURL)
        XCTAssertEqual(manager.readText(from: fileURL), payload)
        XCTAssertTrue(manager.isValidJSON(payload))
    }

    func testFusionCellRuntimeConfigURLMatchesRunnerPath() throws {
        let root = makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let deploy = root.appendingPathComponent("deploy/fusion_cell", isDirectory: true)
        try FileManager.default.createDirectory(at: deploy, withIntermediateDirectories: true)
        let cfg = deploy.appendingPathComponent("config.json")
        try "{\"virtual\":{\"cycles\":1}}".write(to: cfg, atomically: true, encoding: .utf8)

        let manager = ConfigFileManager(repositoryRoot: root)
        XCTAssertEqual(manager.fusionCellRuntimeConfigURL()?.path, cfg.path)
    }

    func testFileTreeReturnsConfiguredRoot() throws {
        let root = makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let configDir = root.appendingPathComponent("config", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir.appendingPathComponent("cells"), withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: configDir.appendingPathComponent("cells/cell-01.json").path,
            contents: Data("{\"node\":\"cell-01\"}".utf8),
            attributes: nil
        )

        let manager = ConfigFileManager(repositoryRoot: root)
        let nodes = manager.fileTree(for: "config")
        let hasCell = nodes.contains(where: { node in
            node.name == "cells" && (node.children?.first(where: { $0.name == "cell-01.json" }) != nil)
        })
        XCTAssertTrue(hasCell)
    }

    private func tempRepositoryRoot() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gaiafusion-config-tests-\(UUID().uuidString)")
    }

    private func makeTempWorkspace() -> URL {
        let root = tempRepositoryRoot()
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
