import Foundation
import simd

/// Procedural line-list vertices (pairs of `packed_float3`) for Metal `MTLPrimitiveType.line` — nine canonical fusion plant topologies (UUM-8D S⁴ facility shell proxy).
enum FusionFacilityWireframeGeometry {
    /// Drawable-size LOD: low reduces segments / icosphere level / beam counts (plan: cap vertices; cache per kind+lod).
    enum WireframeLOD: Int, Sendable, Equatable {
        case low = 0
        case high = 1
    }

    /// Maps viewport min dimension (points) to LOD.
    static func wireframeLOD(drawableMinDimensionPoints: Float) -> WireframeLOD {
        drawableMinDimensionPoints < 420 ? .low : .high
    }

    /// Line vertices: each consecutive pair is one segment (`vertexCount = floats.count / 3`).
    static func vertexFloats(for plant: PlantType, lod: WireframeLOD = .high) -> [Float] {
        let p = plant == .unknown ? PlantType.tokamak : plant
        switch p {
        case .inertial: return inertialICF(lod: lod)
        case .tokamak: return tokamak(lod: lod)
        case .sphericalTokamak: return sphericalTokamak(lod: lod)
        case .stellarator: return stellarator(lod: lod)
        case .frc: return frc(lod: lod)
        case .mirror: return magneticMirror(lod: lod)
        case .zPinch: return zPinch(lod: lod)
        case .spheromak: return spheromak(lod: lod)
        case .mif: return mif(lod: lod)
        case .unknown: return tokamak(lod: lod)
        }
    }

    /// Index for `OpenUSDProxy.metal` SubGame Y branch (`0...8` canonical; `255` unknown).
    static func shaderPlantKindIndex(_ plant: PlantType) -> UInt32 {
        switch plant {
        case .inertial: return 0
        case .tokamak: return 1
        case .sphericalTokamak: return 2
        case .stellarator: return 3
        case .frc: return 4
        case .mirror: return 5
        case .zPinch: return 6
        case .spheromak: return 7
        case .mif: return 8
        case .unknown: return 255
        }
    }

    // MARK: - Helpers

    private static func appendSegment(_ a: SIMD3<Float>, _ b: SIMD3<Float>, into out: inout [Float]) {
        out.append(contentsOf: [a.x, a.y, a.z, b.x, b.y, b.z])
    }

    private static let golden: Float = (1 + sqrt(5)) * 0.5

    /// Recursive icosahedron subdivision; `level` 0 = icosahedron only, 1+ adds geodesic detail.
    private static func icosphereWireframe(level: Int, radius: Float, into out: inout [Float]) {
        let phi = golden
        var verts: [SIMD3<Float>] = [
            simd_normalize(SIMD3(-1, phi, 0)), simd_normalize(SIMD3(1, phi, 0)),
            simd_normalize(SIMD3(-1, -phi, 0)), simd_normalize(SIMD3(1, -phi, 0)),
            simd_normalize(SIMD3(0, -1, phi)), simd_normalize(SIMD3(0, 1, phi)),
            simd_normalize(SIMD3(0, -1, -phi)), simd_normalize(SIMD3(0, 1, -phi)),
            simd_normalize(SIMD3(phi, 0, -1)), simd_normalize(SIMD3(phi, 0, 1)),
            simd_normalize(SIMD3(-phi, 0, -1)), simd_normalize(SIMD3(-phi, 0, 1)),
        ]
        var faces: [[Int]] = [
            [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
            [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
            [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
            [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
        ]
        var midCache: [UInt64: Int] = [:]
        func midIndex(_ i: Int, _ j: Int) -> Int {
            let a = min(i, j)
            let b = max(i, j)
            let key = (UInt64(a) << 32) | UInt64(b)
            if let e = midCache[key] { return e }
            let p = simd_normalize((verts[i] + verts[j]) * 0.5)
            verts.append(p)
            let idx = verts.count - 1
            midCache[key] = idx
            return idx
        }
        for _ in 0..<max(0, level) {
            var next: [[Int]] = []
            next.reserveCapacity(faces.count * 4)
            for f in faces {
                let m01 = midIndex(f[0], f[1])
                let m12 = midIndex(f[1], f[2])
                let m20 = midIndex(f[2], f[0])
                next.append([f[0], m01, m20])
                next.append([f[1], m12, m01])
                next.append([f[2], m20, m12])
                next.append([m01, m12, m20])
            }
            faces = next
            midCache.removeAll(keepingCapacity: true)
        }
        var edgeSet = Set<UInt64>()
        for f in faces {
            let tri = [(f[0], f[1]), (f[1], f[2]), (f[2], f[0])]
            for (u, v) in tri {
                let lo = min(u, v)
                let hi = max(u, v)
                edgeSet.insert((UInt64(lo) << 32) | UInt64(hi))
            }
        }
        let r = radius
        for e in edgeSet {
            let lo = Int(e >> 32)
            let hi = Int(e & 0xffff_ffff)
            appendSegment(verts[lo] * r, verts[hi] * r, into: &out)
        }
    }

    /// Evenly distributed points on a sphere (Fibonacci / golden spiral).
    private static func fibonacciSpherePoints(count: Int, radius: Float) -> [SIMD3<Float>] {
        guard count > 0 else { return [] }
        var pts: [SIMD3<Float>] = []
        pts.reserveCapacity(count)
        let n = Float(count)
        let offset = 2.0 / n
        let inc = Float.pi * (3 - sqrt(5))
        for i in 0..<count {
            let y = Float(i) * offset - 1 + offset * 0.5
            let r0 = sqrt(max(0, 1 - y * y))
            let phi = Float(i) * inc
            let x = cos(phi) * r0
            let z = sin(phi) * r0
            pts.append(SIMD3(x, y, z) * radius)
        }
        return pts
    }

    private static func circleRingXZ(centerY: Float, radius: Float, segments: Int, into out: inout [Float]) {
        guard segments >= 3 else { return }
        var prev = SIMD3<Float>(radius, centerY, 0)
        for s in 1...segments {
            let t = Float(s) / Float(segments) * Float.pi * 2
            let cur = SIMD3<Float>(cos(t) * radius, centerY, sin(t) * radius)
            appendSegment(prev, cur, into: &out)
            prev = cur
        }
    }

    private static func circleRingXY(centerZ: Float, radius: Float, segments: Int, into out: inout [Float]) {
        guard segments >= 3 else { return }
        var prev = SIMD3<Float>(radius, 0, centerZ)
        for s in 1...segments {
            let t = Float(s) / Float(segments) * Float.pi * 2
            let cur = SIMD3<Float>(cos(t) * radius, sin(t) * radius, centerZ)
            appendSegment(prev, cur, into: &out)
            prev = cur
        }
    }

    /// Open-ended cylinder along +Z from `z0` to `z1`, radius `r`, `segments` around axis.
    private static func cylinderOpen(z0: Float, z1: Float, radius: Float, segments: Int, into out: inout [Float]) {
        guard segments >= 4 else { return }
        for s in 0..<segments {
            let t0 = Float(s) / Float(segments) * Float.pi * 2
            let t1 = Float(s + 1) / Float(segments) * Float.pi * 2
            let a = SIMD3<Float>(cos(t0) * radius, sin(t0) * radius, z0)
            let b = SIMD3<Float>(cos(t1) * radius, sin(t1) * radius, z0)
            appendSegment(a, b, into: &out)
            let c = SIMD3<Float>(cos(t0) * radius, sin(t0) * radius, z1)
            let d = SIMD3<Float>(cos(t1) * radius, sin(t1) * radius, z1)
            appendSegment(c, d, into: &out)
            appendSegment(a, c, into: &out)
        }
    }

    /// Torus in XY plane, Z-up symmetry axis; major `R0`, minor `a`.
    private static func torusWireframe(R0: Float, a: Float, uSeg: Int, vSeg: Int, into out: inout [Float]) {
        guard uSeg >= 4, vSeg >= 4 else { return }
        for i in 0..<uSeg {
            let u0 = Float(i) / Float(uSeg) * Float.pi * 2
            let u1 = Float(i + 1) / Float(uSeg) * Float.pi * 2
            for j in 0..<vSeg {
                let v0 = Float(j) / Float(vSeg) * Float.pi * 2
                let v1 = Float(j + 1) / Float(vSeg) * Float.pi * 2
                func p(_ u: Float, _ v: Float) -> SIMD3<Float> {
                    let rp = R0 + a * cos(v)
                    return SIMD3<Float>(rp * cos(u), rp * sin(u), a * sin(v))
                }
                appendSegment(p(u0, v0), p(u1, v0), into: &out)
                appendSegment(p(u0, v0), p(u0, v1), into: &out)
            }
        }
    }

    // MARK: - Topologies

    /// ICF: geodesic outer shell + central hohlraum + inward beamlines (Fibonacci origins; count LOD).
    private static func inertialICF(lod: WireframeLOD) -> [Float] {
        var v: [Float] = []
        let icoLv = lod == .low ? 1 : 2
        let beams = lod == .low ? 96 : 192
        let hohlSeg = lod == .low ? 12 : 16
        icosphereWireframe(level: icoLv, radius: 1.0, into: &v)
        let hohlR: Float = 0.06
        let hohlH: Float = 0.14
        cylinderOpen(z0: -hohlH * 0.5, z1: hohlH * 0.5, radius: hohlR, segments: hohlSeg, into: &v)
        let origins = fibonacciSpherePoints(count: beams, radius: 0.82)
        let target = SIMD3<Float>(0, 0, 0)
        for o in origins {
            appendSegment(o, target, into: &v)
        }
        return v
    }

    /// Tokamak: nested torus vessel + PF stack + TF D-loops in meridional planes.
    private static func tokamak(lod: WireframeLOD) -> [Float] {
        var v: [Float] = []
        let R0: Float = 0.55
        let a: Float = 0.22
        let uSeg = lod == .low ? 24 : 40
        let vSeg = lod == .low ? 12 : 16
        let pfSeg = lod == .low ? 28 : 48
        let tfSteps = lod == .low ? 32 : 48
        let nTF = lod == .low ? 12 : 18
        torusWireframe(R0: R0, a: a, uSeg: uSeg, vSeg: vSeg, into: &v)
        for k in -3...3 {
            let z = Float(k) * 0.11
            circleRingXY(centerZ: z, radius: R0 + a * 1.05, segments: pfSeg, into: &v)
        }
        for i in 0..<nTF {
            let phi = Float(i) / Float(nTF) * Float.pi * 2
            let c = cos(phi)
            let s = sin(phi)
            var prev = SIMD3<Float>.zero
            for j in 0...tfSteps {
                let u = Float(j) / Float(tfSteps) * Float.pi * 2
                let rp = R0 + a * cos(u) * 1.02
                let x = rp * c - a * sin(u) * s * 0.15
                let y = rp * s + a * sin(u) * c * 0.15
                let z = a * sin(u) * 1.05
                let cur = SIMD3<Float>(x, y, z)
                if j > 0 { appendSegment(prev, cur, into: &v) }
                prev = cur
            }
        }
        return v
    }

    /// Spherical tokamak: cored sphere shell + dense central solenoid + asymmetric TF hints.
    private static func sphericalTokamak(lod: WireframeLOD) -> [Float] {
        var v: [Float] = []
        let R: Float = 0.75
        let holeR: Float = 0.12
        let seg = lod == .low ? 14 : 24
        let holeRingSeg = lod == .low ? 14 : 20
        let solN = lod == .low ? 14 : 24
        let tfLoops = lod == .low ? 8 : 12
        let tfSteps = lod == .low ? 22 : 36
        for m in 0..<seg {
            let t0 = Float(m) / Float(seg) * Float.pi
            let t1 = Float(m + 1) / Float(seg) * Float.pi
            for n in 0..<seg {
                let p0 = Float(n) / Float(seg) * Float.pi * 2
                let p1 = Float(n + 1) / Float(seg) * Float.pi * 2
                func sp(_ theta: Float, _ phi: Float) -> SIMD3<Float> {
                    let st = sin(theta)
                    return SIMD3<Float>(R * st * cos(phi), R * st * sin(phi), R * cos(theta))
                }
                appendSegment(sp(t0, p0), sp(t1, p0), into: &v)
                appendSegment(sp(t0, p0), sp(t0, p1), into: &v)
            }
        }
        circleRingXY(centerZ: 0, radius: holeR, segments: holeRingSeg, into: &v)
        for k in 0..<solN {
            let ang = Float(k) / Float(solN) * Float.pi * 2
            let x = cos(ang) * holeR * 0.92
            let y = sin(ang) * holeR * 0.92
            appendSegment(SIMD3(x, y, -0.55), SIMD3(x, y, 0.55), into: &v)
        }
        let R0: Float = 0.35
        let a: Float = 0.28
        for i in 0..<tfLoops {
            let phi = Float(i) / Float(tfLoops) * Float.pi * 2
            var prev = SIMD3<Float>.zero
            for j in 0...tfSteps {
                let u = Float(j) / Float(tfSteps) * Float.pi * 2
                let widen: Float = (cos(u) > 0) ? 1.18 : 0.82
                let rp = R0 + a * cos(u) * widen
                let x = rp * cos(phi)
                let y = rp * sin(phi)
                let z = a * sin(u)
                let cur = SIMD3<Float>(x, y, z)
                if j > 0 { appendSegment(prev, cur, into: &v) }
                prev = cur
            }
        }
        return v
    }

    /// Stellarator: twisted torus vessel + modular winding loops.
    private static func stellarator(lod: WireframeLOD) -> [Float] {
        var v: [Float] = []
        let R0: Float = 0.52
        let a: Float = 0.2
        let nTwist = 5
        let uSeg = lod == .low ? 32 : 48
        let vSeg = lod == .low ? 14 : 20
        for i in 0..<uSeg {
            let u0 = Float(i) / Float(uSeg) * Float.pi * 2
            let u1 = Float(i + 1) / Float(uSeg) * Float.pi * 2
            for j in 0..<vSeg {
                let v0 = Float(j) / Float(vSeg) * Float.pi * 2
                let v1 = Float(j + 1) / Float(vSeg) * Float.pi * 2
                func p(_ u: Float, _ vv: Float) -> SIMD3<Float> {
                    let twist = Float(nTwist) * 0.08 * sin(3 * u)
                    let rp = R0 + a * cos(vv + twist)
                    return SIMD3<Float>(rp * cos(u + twist * 0.3), rp * sin(u + twist * 0.3), a * sin(vv) + twist)
                }
                appendSegment(p(u0, v0), p(u1, v0), into: &v)
                appendSegment(p(u0, v0), p(u0, v1), into: &v)
            }
        }
        let coils = lod == .low ? 36 : 54
        let pathSteps = lod == .low ? 44 : 64
        for c in 0..<coils {
            let t = Float(c) / Float(coils) * Float.pi * 2
            var prev = SIMD3<Float>.zero
            for s in 0...pathSteps {
                let u = Float(s) / Float(pathSteps) * Float.pi * 2
                let pert = 0.04 * sin(Float(c) * 0.7 + u * 3)
                let rp = R0 + a * cos(u) + pert
                let x = rp * cos(t + u * 0.12)
                let y = rp * sin(t + u * 0.12)
                let z = a * sin(u) * 1.1 + pert
                let cur = SIMD3<Float>(x, y, z)
                if s > 0 { appendSegment(prev, cur, into: &v) }
                prev = cur
            }
        }
        return v
    }

    /// FRC: linear vessel + end formation coils + central confinement rings.
    private static func frc(lod: WireframeLOD) -> [Float] {
        var v: [Float] = []
        let L: Float = 0.9
        let r: Float = 0.28
        let cSeg = lod == .low ? 16 : 24
        let ringSeg = lod == .low ? 18 : 28
        let midSeg = lod == .low ? 18 : 24
        cylinderOpen(z0: -L, z1: L, radius: r, segments: cSeg, into: &v)
        let endRings = lod == .low ? 6 : 8
        for k in 0..<endRings {
            let z = -L + 0.02 + Float(k) * 0.006
            circleRingXY(centerZ: z, radius: r * 0.98, segments: ringSeg, into: &v)
        }
        for k in 0..<endRings {
            let z = L - 0.02 - Float(k) * 0.006
            circleRingXY(centerZ: z, radius: r * 0.98, segments: ringSeg, into: &v)
        }
        let midCount = lod == .low ? 7 : 9
        let denom = Float(max(1, midCount - 1))
        for k in 0..<midCount {
            let z = -L * 0.65 + Float(k) / denom * (L * 1.3)
            circleRingXY(centerZ: z, radius: r * 0.92, segments: midSeg, into: &v)
        }
        return v
    }

    /// Magnetic mirror: central sparse rings + dense choke rings at ends.
    private static func magneticMirror(lod: WireframeLOD) -> [Float] {
        var v: [Float] = []
        let L: Float = 1.0
        let r: Float = 0.22
        let cSeg = lod == .low ? 14 : 20
        let midRingSeg = lod == .low ? 16 : 20
        let chokeSeg = lod == .low ? 18 : 24
        let chokeStack = lod == .low ? 8 : 12
        cylinderOpen(z0: -L, z1: L, radius: r, segments: cSeg, into: &v)
        for k in -2...2 {
            let z = Float(k) * 0.25
            circleRingXY(centerZ: z, radius: r * 0.95, segments: midRingSeg, into: &v)
        }
        for k in 0..<chokeStack {
            let z = -L + 0.02 + Float(k) * 0.004
            circleRingXY(centerZ: z, radius: r * 0.99, segments: chokeSeg, into: &v)
        }
        for k in 0..<chokeStack {
            let z = L - 0.02 - Float(k) * 0.004
            circleRingXY(centerZ: z, radius: r * 0.99, segments: chokeSeg, into: &v)
        }
        return v
    }

    /// Z-pinch: pure cylinder + end electrodes (no external TF coils).
    private static func zPinch(lod: WireframeLOD) -> [Float] {
        var v: [Float] = []
        let L: Float = 0.85
        let r: Float = 0.2
        let cSeg = lod == .low ? 20 : 28
        let eSeg = lod == .low ? 22 : 32
        let spokes = lod == .low ? 6 : 8
        cylinderOpen(z0: -L, z1: L, radius: r, segments: cSeg, into: &v)
        circleRingXY(centerZ: -L, radius: r * 1.08, segments: eSeg, into: &v)
        circleRingXY(centerZ: L, radius: r * 1.08, segments: eSeg, into: &v)
        for i in 0..<spokes {
            let t = Float(i) / Float(spokes) * Float.pi * 2
            appendSegment(SIMD3<Float>(cos(t) * r * 1.08, sin(t) * r * 1.08, -L), SIMD3<Float>(0, 0, -L - 0.06), into: &v)
        }
        for i in 0..<spokes {
            let t = Float(i) / Float(spokes) * Float.pi * 2
            appendSegment(SIMD3<Float>(cos(t) * r * 1.08, sin(t) * r * 1.08, L), SIMD3<Float>(0, 0, L + 0.06), into: &v)
        }
        return v
    }

    /// Spheromak: flux conserver shell + coaxial injector stub.
    private static func spheromak(lod: WireframeLOD) -> [Float] {
        var v: [Float] = []
        let R: Float = 0.55
        let seg = lod == .low ? 14 : 24
        for m in 0..<seg {
            let t0 = Float(m) / Float(seg) * Float.pi
            let t1 = Float(m + 1) / Float(seg) * Float.pi
            for n in 0..<seg {
                let p0 = Float(n) / Float(seg) * Float.pi * 2
                let p1 = Float(n + 1) / Float(seg) * Float.pi * 2
                func sp(_ theta: Float, _ phi: Float) -> SIMD3<Float> {
                    let st = sin(theta)
                    return SIMD3<Float>(R * st * cos(phi), R * st * sin(phi), R * cos(theta))
                }
                appendSegment(sp(t0, p0), sp(t1, p0), into: &v)
                appendSegment(sp(t0, p0), sp(t0, p1), into: &v)
            }
        }
        let gunLen: Float = 0.35
        let gunR: Float = 0.12
        let gunSeg = lod == .low ? 12 : 16
        cylinderOpen(z0: R * 0.85, z1: R * 0.85 + gunLen, radius: gunR, segments: gunSeg, into: &v)
        appendSegment(SIMD3(0, 0, R * 0.85 + gunLen * 0.5), SIMD3(0, 0, R * 0.2), into: &v)
        return v
    }

    /// MIF: icosphere boundary + radial plasma guns at Fibonacci sites.
    private static func mif(lod: WireframeLOD) -> [Float] {
        var v: [Float] = []
        let icoLv = lod == .low ? 1 : 2
        let nGun = lod == .low ? 32 : 48
        icosphereWireframe(level: icoLv, radius: 1.0, into: &v)
        let gunStarts = fibonacciSpherePoints(count: nGun, radius: 0.92)
        let inner = fibonacciSpherePoints(count: nGun, radius: 0.45)
        for i in 0..<gunStarts.count {
            let a = gunStarts[i]
            let b = inner[i]
            appendSegment(a, b, into: &v)
            let dir = simd_normalize(b - a)
            let barrel = a + dir * 0.08
            appendSegment(a, barrel, into: &v)
        }
        return v
    }
}
