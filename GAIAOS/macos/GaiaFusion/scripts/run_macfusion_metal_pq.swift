#!/usr/bin/env swift
// Standalone Metal PQ test for MacFusion
// Patents: USPTO 19/460,960 | USPTO 19/096,071

import Metal
import Foundation

guard let device = MTLCreateSystemDefaultDevice() else {
    print("❌ PQ FAIL: No Metal GPU detected")
    exit(1)
}
guard let queue = device.makeCommandQueue() else {
    print("❌ PQ FAIL: MTLCommandQueue creation failed")
    exit(1)
}

let desc = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
desc.usage = [.renderTarget, .shaderRead]
desc.storageMode = .managed
guard let tex = device.makeTexture(descriptor: desc) else {
    print("❌ PQ FAIL: MTLTexture creation failed")
    exit(1)
}

let rpd = MTLRenderPassDescriptor()
rpd.colorAttachments[0].texture = tex
rpd.colorAttachments[0].loadAction = .clear
rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1.0) // Tokamak M
rpd.colorAttachments[0].storeAction = .store

guard let cmd = queue.makeCommandBuffer(),
      let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else {
    print("❌ PQ FAIL: Command buffer/encoder creation failed")
    exit(1)
}

enc.endEncoding()
cmd.commit()
cmd.waitUntilCompleted()

guard let sync = queue.makeCommandBuffer(),
      let blit = sync.makeBlitCommandEncoder() else {
    print("❌ PQ FAIL: Blit encoder creation failed")
    exit(1)
}

blit.synchronize(resource: tex)
blit.endEncoding()
sync.commit()
sync.waitUntilCompleted()

var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
tex.getBytes(&pixels, bytesPerRow: 64 * 4,
             from: MTLRegionMake2D(0, 0, 64, 64), mipmapLevel: 0)
let nonZero = pixels.filter { $0 > 0 }.count

if nonZero == 0 {
    print("❌ PQ FAIL: Metal render produced all-zero pixels")
    exit(1)
}

// Write PQ receipt
let receipt: [String: Any] = [
    "spec": "GFTCL-PQ-MACFUSION-001",
    "phase": "PQ",
    "cell": "MacFusion",
    "metal_device_name": device.name,
    "nonzero_pixels": nonZero,
    "pq_status": "PASS",
    "timestamp": ISO8601DateFormatter().string(from: Date()),
    "pii_stored": false,
]

let pqDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .deletingLastPathComponent()
    .appendingPathComponent("evidence/pq")

try? FileManager.default.createDirectory(at: pqDir, withIntermediateDirectories: true)

let pqFile = pqDir.appendingPathComponent("macfusion_pq_receipt.json")
let data = try! JSONSerialization.data(withJSONObject: receipt, options: .prettyPrinted)
try! data.write(to: pqFile)

print("✅ MacFusion Metal PQ: PASS")
print("   GPU: \(device.name)")
print("   Pixels rendered: \(nonZero)/16384")
print("   Receipt: \(pqFile.path)")
