import AppKit
import Darwin
import Foundation

/// One **Mac cell** per **bound UI port**: a single GaiaFusion GUI process per lock file. A second launch on the
/// same port exits immediately and foregrounds the existing instance (prevents the multi-process pile-up that
/// required `stop_mac_cell_gaiafusion.sh`).
///
/// `run_fusion_mac_app_gate.py` sets `FUSION_UI_PORT` to an ephemeral port — that uses a **different** flock than
/// the default interactive instance on 8910, so the gate child can run while GaiaFusion is already open for the operator.
///
/// Opt out (rare): `GAIAFUSION_ALLOW_MULTI_INSTANCE=1`
enum SingleMacCellLock {
    static func enforceSingleGUIInstanceOrExit() {
        if ProcessInfo.processInfo.environment["GAIAFUSION_ALLOW_MULTI_INSTANCE"] == "1" {
            return
        }
        let envPort = ProcessInfo.processInfo.environment["FUSION_UI_PORT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let portSuffix: String
        if let s = envPort, let p = Int(s), p > 0, p <= 65535 {
            portSuffix = ".\(p)"
        } else {
            portSuffix = ".default8910"
        }
        let lockPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(
            "com.gaiaftcl.GaiaFusion.mac_cell.flock\(portSuffix)"
        )
        let fd = lockPath.withCString { open($0, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR) }
        guard fd >= 0 else {
            return
        }
        // FD intentionally leaked for process lifetime — kernel releases flock on exit (no static mutable state).
        // LOCK_EX (0x02) | LOCK_NB (0x04) — second instance fails immediately without blocking.
        let rc = flock(fd, Int32(0x02 | 0x04))
        if rc != 0 {
            let bid = Bundle.main.bundleIdentifier ?? "com.gaiaftcl.GaiaFusion"
            let mine = ProcessInfo.processInfo.processIdentifier
            NSRunningApplication.runningApplications(withBundleIdentifier: bid)
                .first(where: { $0.processIdentifier != mine })?
                .activate(options: [.activateAllWindows])
            Darwin.exit(0)
        }
    }
}
