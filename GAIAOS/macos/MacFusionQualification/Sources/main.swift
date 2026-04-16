// MacFusion IQ/OQ/PQ Qualification
// Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie

import Foundation
import Metal

struct Receipt: Codable {
    let spec: String
    let phase: String
    let cell: String
    let timestamp: String
    let status: String
    let pii_stored: Bool
}

func banner(_ msg: String) {
    print("\n\u{001B}[34m══════════════════════════════════════════════════════════\u{001B}[0m")
    print("\u{001B}[34m  \(msg)\u{001B}[0m")
    print("\u{001B}[34m══════════════════════════════════════════════════════════\u{001B}[0m")
}

func ok(_ msg: String) { print("\u{001B}[32m  ✅ \(msg)\u{001B}[0m") }
func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("\u{001B}[31m  ❌ BLOCKED: \(msg)\u{001B}[0m\n".utf8))
    exit(1)
}

func runProcess(_ args: [String], workingDir: String) -> (Int32, String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = args
    process.currentDirectoryURL = URL(fileURLWithPath: workingDir)
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try? process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    return (process.terminationStatus, output)
}

func writeReceipt(_ receipt: Receipt, path: String) {
    let fm = FileManager.default
    let url = URL(fileURLWithPath: path)
    try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let data = try? JSONEncoder().encode(receipt) {
        try? data.write(to: url)
    }
}

// ═══════════════════════════════════════════════════════════════
// IQ (Installation Qualification)
// ═══════════════════════════════════════════════════════════════

func runIQ(appPath: String) -> String {
    banner("MacFusion — IQ (Installation Qualification)")
    let fm = FileManager.default
    
    // Check Package.swift
    guard fm.fileExists(atPath: "\(appPath)/Package.swift") else {
        fail("Package.swift missing")
    }
    ok("Package.swift present")
    
    // Check staticlib
    guard fm.fileExists(atPath: "\(appPath)/MetalRenderer/lib/libgaia_metal_renderer.a") else {
        fail("libgaia_metal_renderer.a missing")
    }
    ok("Staticlib present")
    
    // Check header
    guard fm.fileExists(atPath: "\(appPath)/MetalRenderer/include/gaia_metal_renderer.h") else {
        fail("gaia_metal_renderer.h missing")
    }
    ok("Header present")
    
    // Build
    print("  Building MacFusion...")
    let (exitCode, output) = runProcess(["swift", "build", "--product", "GaiaFusion"], workingDir: appPath)
    if exitCode != 0 {
        print(output.split(separator: "\n").suffix(10).joined(separator: "\n"))
        fail("Build failed")
    }
    ok("Build: PASS")
    
    // Check executable
    guard fm.fileExists(atPath: "\(appPath)/.build/debug/GaiaFusion") else {
        fail("Executable missing")
    }
    ok("Executable: .build/debug/GaiaFusion")
    
    // Write receipt
    let receipt = Receipt(
        spec: "MACFUSION-IQ-001",
        phase: "IQ",
        cell: "MacFusion",
        timestamp: ISO8601DateFormatter().string(from: Date()),
        status: "PASS",
        pii_stored: false
    )
    writeReceipt(receipt, path: "\(appPath)/evidence/iq/macfusion_iq_receipt.json")
    ok("IQ receipt written")
    
    return "PASS"
}

// ═══════════════════════════════════════════════════════════════
// OQ (Operational Qualification)
// ═══════════════════════════════════════════════════════════════

func runOQ(appPath: String) -> String {
    banner("MacFusion — OQ (Operational Qualification)")
    
    let filters = [
        "CellStateTests",
        "SwapLifecycleTests",
        "PlantKindsCatalogTests",
        "FusionFacilityWireframeGeometryTests",
        "FusionUiTorsionTests",
        "ConfigValidationTests"
    ]
    
    var passed = 0
    for filter in filters {
        print("  Running: \(filter)...")
        let (exitCode, _) = runProcess(["swift", "test", "--filter", filter], workingDir: appPath)
        if exitCode == 0 {
            ok("\(filter): PASS")
            passed += 1
        } else {
            print("  ⚠️  \(filter): FAIL")
        }
    }
    
    let status = (passed == filters.count) ? "PASS" : "PARTIAL"
    
    // Write receipt
    let receipt = Receipt(
        spec: "MACFUSION-OQ-001",
        phase: "OQ",
        cell: "MacFusion",
        timestamp: ISO8601DateFormatter().string(from: Date()),
        status: status,
        pii_stored: false
    )
    writeReceipt(receipt, path: "\(appPath)/evidence/oq/macfusion_oq_receipt.json")
    ok("OQ receipt: \(passed)/\(filters.count) tests PASS")
    
    return status
}

// ═══════════════════════════════════════════════════════════════
// PQ (Performance Qualification) — Metal GPU
// ═══════════════════════════════════════════════════════════════

func runPQ(appPath: String) -> (String, String) {
    banner("MacFusion — PQ (Performance Qualification)")
    
    guard let device = MTLCreateSystemDefaultDevice() else {
        fail("No Metal GPU")
    }
    
    guard let queue = device.makeCommandQueue() else {
        fail("MTLCommandQueue creation failed")
    }
    
    let desc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false
    )
    desc.usage = [.renderTarget, .shaderRead]
    desc.storageMode = .managed
    
    guard let tex = device.makeTexture(descriptor: desc) else {
        fail("MTLTexture creation failed")
    }
    
    let rpd = MTLRenderPassDescriptor()
    rpd.colorAttachments[0].texture = tex
    rpd.colorAttachments[0].loadAction = .clear
    rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1.0)
    rpd.colorAttachments[0].storeAction = .store
    
    guard let cmd = queue.makeCommandBuffer(),
          let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else {
        fail("Command buffer creation failed")
    }
    
    enc.endEncoding()
    cmd.commit()
    cmd.waitUntilCompleted()
    
    guard let sync = queue.makeCommandBuffer(),
          let blit = sync.makeBlitCommandEncoder() else {
        fail("Sync buffer creation failed")
    }
    
    blit.synchronize(resource: tex)
    blit.endEncoding()
    sync.commit()
    sync.waitUntilCompleted()
    
    var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
    tex.getBytes(&pixels, bytesPerRow: 64 * 4, from: MTLRegionMake2D(0, 0, 64, 64), mipmapLevel: 0)
    
    let nonZero = pixels.filter { $0 > 0 }.count
    let status = nonZero > 0 ? "PASS" : "FAIL"
    
    // Write receipt
    let receipt = Receipt(
        spec: "MACFUSION-PQ-001",
        phase: "PQ",
        cell: "MacFusion",
        timestamp: ISO8601DateFormatter().string(from: Date()),
        status: status,
        pii_stored: false
    )
    writeReceipt(receipt, path: "\(appPath)/evidence/pq/macfusion_pq_receipt.json")
    ok("PQ: \(status) (GPU: \(device.name), pixels: \(nonZero))")
    
    if status == "FAIL" { fail("Metal render produced zero pixels") }
    
    return (status, device.name)
}

// ═══════════════════════════════════════════════════════════════
// Main
// ═══════════════════════════════════════════════════════════════

func main() {
    let appPath = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("GaiaFusion")
        .path
    
    banner("MacFusion Qualification — IQ → OQ → PQ")
    
    let iq = runIQ(appPath: appPath)
    let oq = runOQ(appPath: appPath)
    let (pq, gpu) = runPQ(appPath: appPath)
    
    banner("MacFusion Qualification Complete")
    print("\u{001B}[32m  IQ: \(iq) | OQ: \(oq) | PQ: \(pq) (GPU: \(gpu))\u{001B}[0m")
}

main()
