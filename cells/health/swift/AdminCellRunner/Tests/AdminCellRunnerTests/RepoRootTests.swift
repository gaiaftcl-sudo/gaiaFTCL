import AdminCellCore
import XCTest

final class RepoRootTests: XCTestCase {
    func testArgDeviationRequiresReason() {
        XCTAssertTrue(ArgDeviation.requiresDeviationReason(["--skip-ui"]))
        XCTAssertNil(ArgDeviation.deviationReason(from: ["--skip-ui"]))
        XCTAssertThrowsError(try ArgDeviation.validateOrThrow(["--skip-ui"]))
    }

    func testArgDeviationWithReason() throws {
        try ArgDeviation.validateOrThrow(["--skip-ui", "--deviation-reason=ci_headless"])
        XCTAssertEqual(ArgDeviation.deviationReason(from: ["--deviation-reason=ci_headless"]), "ci_headless")
    }

    func testSelfTestZsh() throws {
        try OrchestratorLaunch.selfTestZsh()
    }

    func testRepoRootConflict() {
        let a = FileManager.default.temporaryDirectory.appendingPathComponent("admincell_a").path
        let b = FileManager.default.temporaryDirectory.appendingPathComponent("admincell_b").path
        XCTAssertThrowsError(try RepoRootResolver().resolve(cliRepo: a, envRepo: b)) { err in
            XCTAssertTrue("\(err)".contains("conflict"), "\(err)")
        }
    }

    /// App bundles / CLI arbitrary paths: walk to FoT8D root.
    func testDiscoverWalkingUpFromDeepPath() throws {
        var url = URL(fileURLWithPath: #file)
        for _ in 0..<7 { url.deleteLastPathComponent() }
        let root = url.standardizedFileURL
        let script = root.appendingPathComponent("cells/health/scripts/health_full_local_iqoqpq_gamp.sh")
        guard FileManager.default.fileExists(atPath: script.path) else {
            throw XCTSkip("not running in FoT8D layout")
        }
        let fromFile = root
            .appendingPathComponent("cells/health/swift/MacFranklin/Package.swift")
        let found = RepoRootResolver().discoverWalkingUp(from: fromFile)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.path, root.path)
    }

    /// F0: `fo-franklin verify-pins` (Rust `fo_cell_substrate` @ `target/release/fo-franklin`) — repo must be FoT8D (cells/… layout).
    func testFranklinPinnedScriptsMatch() throws {
        var url = URL(fileURLWithPath: #file)
        for _ in 0..<7 { url.deleteLastPathComponent() }
        let pyLegacy = url.appendingPathComponent("cells/franklin/scripts/verify_franklin_pins.py")
        let tool = url.appendingPathComponent("target/release/fo-franklin")
        guard FileManager.default.fileExists(atPath: pyLegacy.path) else {
            throw XCTSkip("not running inside FoT8D monorepo checkout")
        }
        guard FileManager.default.isExecutableFile(atPath: tool.path) else {
            throw XCTSkip("fo-franklin not built (from repo: cargo build -p fo_cell_substrate --release)")
        }
        let p = Process()
        p.executableURL = tool
        p.arguments = ["verify-pins", "--repo", url.path]
        p.currentDirectoryURL = url
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(p.terminationStatus, 0, "fo-franklin verify-pins failed:\n\(out)")
    }
}
