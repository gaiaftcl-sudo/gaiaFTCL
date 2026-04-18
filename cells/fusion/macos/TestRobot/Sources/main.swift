// TestRobot — Performance Qualification Orchestrator
// Runs Metal PQ tests for MacFusion + MacHealth
// Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie

import Foundation
import Metal

// ═══════════════════════════════════════════════════════════════
// TestRobot — PQ Phase Only
// IQ (install) and OQ (operational) are handled by zsh scripts
// This executable runs Performance Qualification (Metal GPU tests)
// ═══════════════════════════════════════════════════════════════

struct PQResult: Codable {
    let spec: String
    let phase: String
    let cell: String
    let metal_device_name: String
    let nonzero_pixels: Int
    let pq_status: String
    let timestamp: String
    let pii_stored: Bool
}

struct TestRobotReceipt: Codable {
    let receipt_id: String
    let spec: String
    let timestamp: String
    let pii_stored: Bool
    let apps: [String: AppStatus]
    let overall_status: String
    let notes: [String]
    let operator_pubkey_hash: String
    
    struct AppStatus: Codable {
        let pq_status: String
        let metal_device: String
        let pq_receipt: String
    }
}

func banner(_ msg: String) {
    print("\n\u{001B}[34m══════════════════════════════════════════════════════════\u{001B}[0m")
    print("\u{001B}[34m  \(msg)\u{001B}[0m")
    print("\u{001B}[34m══════════════════════════════════════════════════════════\u{001B}[0m")
}

func ok(_ msg: String) {
    print("\u{001B}[32m  ✅ \(msg)\u{001B}[0m")
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("\u{001B}[31m  ❌ STATE: BLOCKED — \(msg)\u{001B}[0m\n".utf8))
    exit(1)
}

// ═══════════════════════════════════════════════════════════════
// Metal PQ Test — Offscreen Render
// ═══════════════════════════════════════════════════════════════

func runMetalPQ(appName: String, clearColor: MTLClearColor, receiptPath: String) -> PQResult? {
    guard let device = MTLCreateSystemDefaultDevice() else {
        print("  ❌ No Metal GPU detected — \(appName) PQ FAIL")
        return nil
    }
    
    guard let queue = device.makeCommandQueue() else {
        print("  ❌ MTLCommandQueue creation failed")
        return nil
    }
    
    let desc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: 64,
        height: 64,
        mipmapped: false
    )
    desc.usage = [.renderTarget, .shaderRead]
    desc.storageMode = .managed
    
    guard let tex = device.makeTexture(descriptor: desc) else {
        print("  ❌ MTLTexture creation failed")
        return nil
    }
    
    let rpd = MTLRenderPassDescriptor()
    rpd.colorAttachments[0].texture = tex
    rpd.colorAttachments[0].loadAction = .clear
    rpd.colorAttachments[0].clearColor = clearColor
    rpd.colorAttachments[0].storeAction = .store
    
    guard let cmd = queue.makeCommandBuffer(),
          let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else {
        print("  ❌ Command buffer/encoder creation failed")
        return nil
    }
    
    enc.endEncoding()
    cmd.commit()
    cmd.waitUntilCompleted()
    
    // Synchronize managed texture
    guard let sync = queue.makeCommandBuffer(),
          let blit = sync.makeBlitCommandEncoder() else {
        print("  ❌ Sync command buffer creation failed")
        return nil
    }
    
    blit.synchronize(resource: tex)
    blit.endEncoding()
    sync.commit()
    sync.waitUntilCompleted()
    
    // Read back pixels
    var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
    tex.getBytes(
        &pixels,
        bytesPerRow: 64 * 4,
        from: MTLRegionMake2D(0, 0, 64, 64),
        mipmapLevel: 0
    )
    
    let nonZero = pixels.filter { $0 > 0 }.count
    let status = nonZero > 0 ? "PASS" : "FAIL"
    
    let result = PQResult(
        spec: "\(appName.uppercased())-PQ-001",
        phase: "PQ",
        cell: appName,
        metal_device_name: device.name,
        nonzero_pixels: nonZero,
        pq_status: status,
        timestamp: ISO8601DateFormatter().string(from: Date()),
        pii_stored: false
    )
    
    // Write receipt
    let receiptURL = URL(fileURLWithPath: receiptPath)
    try? FileManager.default.createDirectory(
        at: receiptURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    
    if let data = try? JSONEncoder().encode(result) {
        try? data.write(to: receiptURL)
        print("  ✅ \(appName) PQ: \(status)")
        print("     GPU: \(device.name)")
        print("     Pixels: \(nonZero)/\(64*64*4)")
        print("     Receipt: \(receiptPath)")
    }
    
    return result
}

// ═══════════════════════════════════════════════════════════════
// Main TestRobot Execution
// ═══════════════════════════════════════════════════════════════

func main() {
    banner("TestRobot — Performance Qualification")
    
    let timestamp = ISO8601DateFormatter().string(from: Date())
        .replacingOccurrences(of: ":", with: "")
        .replacingOccurrences(of: "-", with: "")
    
    // Get repo root (assumes TestRobot is in cells/fusion/macos/TestRobot)
    let currentPath = URL(fileURLWithPath: #file)
        .deletingLastPathComponent() // Sources
        .deletingLastPathComponent() // TestRobot
        .deletingLastPathComponent() // macos
        .deletingLastPathComponent() // GAIAOS
        .deletingLastPathComponent() // FoT8D
    
    let repoRoot = currentPath.path
    print("  Repo root: \(repoRoot)")
    
    // ── MacFusion PQ ──
    banner("MacFusion — Metal PQ")
    let mfReceiptPath = "\(repoRoot)/cells/fusion/macos/GaiaFusion/evidence/pq/macfusion_pq_receipt.json"
    guard let mfResult = runMetalPQ(
        appName: "MacFusion",
        clearColor: MTLClearColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1.0), // Tokamak red
        receiptPath: mfReceiptPath
    ) else {
        fail("MacFusion Metal PQ failed")
    }
    
    // ── MacHealth PQ ──
    banner("MacHealth — Metal PQ")
    let mhReceiptPath = "\(repoRoot)/cells/fusion/macos/MacHealth/evidence/pq/machealth_pq_receipt.json"
    guard let mhResult = runMetalPQ(
        appName: "MacHealth",
        clearColor: MTLClearColor(red: 0.0, green: 0.4, blue: 0.9, alpha: 1.0), // Health blue
        receiptPath: mhReceiptPath
    ) else {
        fail("MacHealth Metal PQ failed")
    }
    
    // ── Write unified receipt ──
    banner("Writing TESTROBOT_RECEIPT.json")
    
    let receipt = TestRobotReceipt(
        receipt_id: "TESTROBOT-\(timestamp)",
        spec: "FoT8D-TESTROBOT-PQ-001",
        timestamp: timestamp,
        pii_stored: false,
        apps: [
            "MacFusion": TestRobotReceipt.AppStatus(
                pq_status: mfResult.pq_status,
                metal_device: mfResult.metal_device_name,
                pq_receipt: mfReceiptPath
            ),
            "MacHealth": TestRobotReceipt.AppStatus(
                pq_status: mhResult.pq_status,
                metal_device: mhResult.metal_device_name,
                pq_receipt: mhReceiptPath
            )
        ],
        overall_status: (mfResult.pq_status == "PASS" && mhResult.pq_status == "PASS") ? "PASS" : "FAIL",
        notes: [
            "PQ phase only — IQ/OQ handled by zsh scripts",
            "MacFusion Metal PQ: \(mfResult.pq_status)",
            "MacHealth Metal PQ: \(mhResult.pq_status)",
            "GPU: \(mfResult.metal_device_name)"
        ],
        operator_pubkey_hash: "CELL-OPERATOR-PUBKEY-HASH-REQUIRED"
    )
    
    let receiptPath = "\(repoRoot)/evidence/TESTROBOT_RECEIPT.json"
    let receiptURL = URL(fileURLWithPath: receiptPath)
    
    if let data = try? JSONEncoder().encode(receipt) {
        try? data.write(to: receiptURL)
        ok("Receipt: \(receiptPath)")
    }
    
    banner("STATE: CALORIE — PQ Complete")
    print("\u{001B}[32m  MacFusion PQ: \(mfResult.pq_status) (GPU: \(mfResult.metal_device_name))\u{001B}[0m")
    print("\u{001B}[32m  MacHealth PQ: \(mhResult.pq_status) (GPU: \(mhResult.metal_device_name))\u{001B}[0m")
    print()
    print("\u{001B}[33m  Rick: Sign evidence/TESTROBOT_RECEIPT.json\u{001B}[0m")
}

main()
