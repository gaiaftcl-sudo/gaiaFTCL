import Darwin
import Foundation

/// When launched with `--cli`, exec-equivalent: runs `scripts/fusion_surface.sh` under bash and exits with its status.
/// Optional `--gaia-root` applies to this invocation only (also sets `GAIA_ROOT` for the child).
enum FusionMacCLI {
    static func handleInvocationInAppInit() {
        var argv = Array(CommandLine.arguments.dropFirst())
        guard !argv.isEmpty else { return }

        if argv[0] == "--help" || argv[0] == "-h" {
            fputs(usageText, stdout)
            exit(0)
        }

        guard argv[0] == "--cli" else { return }
        argv.removeFirst()

        var gaiaRoot = ProcessInfo.processInfo.environment["GAIA_ROOT"] ?? ""
        if let idx = argv.firstIndex(of: "--gaia-root"), argv.indices.contains(idx + 1) {
            gaiaRoot = argv[idx + 1]
            argv.removeSubrange(idx ... idx + 1)
        }

        var feederMode = false
        if argv.first == "feeder" {
            argv.removeFirst()
            feederMode = true
        } else if argv.first == "fusion" {
            argv.removeFirst()
        }

        guard !gaiaRoot.isEmpty else {
            fputs(
                "FusionSidecarHost: set GAIA_ROOT or pass --gaia-root /path/to/GAIAOS before subcommands.\n",
                stderr
            )
            exit(2)
        }

        let scriptName = feederMode ? "fusion_feeder_service.sh" : "fusion_surface.sh"
        let script = (gaiaRoot as NSString).appendingPathComponent("scripts/\(scriptName)")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: script, isDirectory: &isDir), !isDir.boolValue else {
            fputs("FusionSidecarHost: missing \(script)\n", stderr)
            exit(2)
        }

        if !feederMode, ProcessInfo.processInfo.environment["FUSION_SKIP_MOOR_PREFLIGHT"] != "1",
           argv.first == "moor"
        {
            let preflight = (gaiaRoot as NSString).appendingPathComponent("scripts/fusion_moor_preflight.sh")
            var preIsDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: preflight, isDirectory: &preIsDir), !preIsDir.boolValue else {
                fputs("FusionSidecarHost: missing \(preflight)\n", stderr)
                exit(2)
            }
            let pre = Process()
            pre.executableURL = URL(fileURLWithPath: "/bin/bash")
            pre.arguments = [preflight]
            var preEnv = ProcessInfo.processInfo.environment
            preEnv["GAIA_ROOT"] = gaiaRoot
            pre.environment = preEnv
            pre.standardInput = FileHandle.nullDevice
            pre.standardOutput = FileHandle.standardOutput
            pre.standardError = FileHandle.standardError
            do {
                try pre.run()
                pre.waitUntilExit()
                if pre.terminationStatus != 0 {
                    exit(pre.terminationStatus)
                }
            } catch {
                fputs("\(error)\n", stderr)
                exit(1)
            }
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [script] + argv
        var env = ProcessInfo.processInfo.environment
        env["GAIA_ROOT"] = gaiaRoot
        proc.environment = env
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = FileHandle.standardOutput
        proc.standardError = FileHandle.standardError

        do {
            try proc.run()
            proc.waitUntilExit()
            exit(proc.terminationStatus)
        } catch {
            fputs("\(error)\n", stderr)
            exit(1)
        }
    }

    private static let usageText = """
    FusionSidecarHost — VM GUI, or CLI delegate to GAIA_ROOT/scripts/

      Show help:
        FusionSidecarHost --help

      Moor stack + UI (nonstop long-run) → scripts/fusion_surface.sh:
        GAIA_ROOT=/path/to/GAIAOS FusionSidecarHost --cli moor --nonstop --profile local
        (runs scripts/fusion_moor_preflight.sh first unless FUSION_SKIP_MOOR_PREFLIGHT=1)

      M8 benchmark feeders → scripts/fusion_feeder_service.sh:
        FusionSidecarHost --gaia-root /path/to/GAIAOS --cli feeder start nstxu
        FusionSidecarHost --gaia-root /path/to/GAIAOS --cli feeder status
        FusionSidecarHost --gaia-root /path/to/GAIAOS --cli feeder stop all

      Fixed batch iterations then exit long-run child:
        FusionSidecarHost --gaia-root /path/to/GAIAOS --cli fusion moor --iterations 10 --profile local

      Optional word \"fusion\" after --cli is ignored (operator muscle memory).

    """
}
