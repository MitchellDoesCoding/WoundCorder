import Foundation
import simd
/// Pure geometry shared by the scanner and analytic regression fixtures. Inputs are meters.
enum WoundGeometry {
    struct VolumeQualityFlags {
        var contourMismatch = false
        var incompleteOutline = false
        var bottomLargerThanTop = false
        var calibrationUncertainty = false
    }
    static func validateContourForVolume(_ pts: [SIMD3<Float>]) -> Bool {
        guard pts.count >= 3, pts.allSatisfy(isFinite) else { return false }
        let areaM2 = simd_length(areaVector(pts))
        let perimeterM = zip(pts, pts.dropFirst() + [pts[0]])
            .reduce(0.0) { $0 + simd_length(SIMD3<Double>($1.1) - SIMD3<Double>($1.0)) }
        // Test the unnormalized area, not the length of a unit normal. The relative
        // bound rejects collapsed/near-collinear traces at any scene position.
        return areaM2.isFinite && areaM2 > max(1e-8, perimeterM * perimeterM * 1e-6)
    }
    static func resampleClosedPolyline(_ pts: [SIMD3<Float>], targetCount: Int) -> [SIMD3<Float>] {
        guard pts.count >= 3, targetCount >= 3, pts.allSatisfy(isFinite) else { return [] }
        // build cumulative lengths around closed loop
        var loop = pts
        if loop.first != loop.last { loop.append(loop.first!) }
        var lengths: [Float] = [0]
        var total: Float = 0
        for i in 0..<(loop.count - 1) {
            let d = simd_length(loop[i+1] - loop[i])
            total += d
            lengths.append(total)
        }
        guard total > 0 else { return Array(pts.prefix(targetCount)) }
        // sample equally spaced
        var out: [SIMD3<Float>] = []
        out.reserveCapacity(targetCount)
        for k in 0..<targetCount {
            let t = (Float(k) / Float(targetCount)) * total
            // find segment
            var idx = 0
            while idx < lengths.count - 1 && lengths[idx+1] < t { idx += 1 }
            let t0 = lengths[idx]
            let t1 = lengths[idx+1]
            let segT = (t1 - t0) > 0 ? (t - t0) / (t1 - t0) : 0
            let p = simd_mix(loop[idx], loop[idx+1], SIMD3<Float>(repeating: segT))
            out.append(p)
        }
        return out
    }
    static func alignedResampledLoops(top: [SIMD3<Float>], bottom: [SIMD3<Float>], targetCount: Int) -> (t: [SIMD3<Float>], b: [SIMD3<Float>])? {
        guard validateContourForVolume(top), validateContourForVolume(bottom) else { return nil }

        let N = max(32, min(targetCount, 256))
        let t = resampleClosedPolyline(top, targetCount: N)
        var b = resampleClosedPolyline(bottom, targetCount: N)
        guard t.count >= 3, b.count >= 3 else { return nil }

        // Normalize winding
        let nt = polygonNormal(t)
        let nb = polygonNormal(b)
        if simd_dot(nt, nb) < 0 {
            b.reverse()
        }

        // Align starts by cyclic shift to minimize RMS distance between corresponding points
        func bestShift(reference: [SIMD3<Float>], candidate: [SIMD3<Float>]) -> Int {
            let n = min(reference.count, candidate.count)
            guard n > 0 else { return 0 }
            var best = 0
            var bestScore: Float = .greatestFiniteMagnitude
            for s in 0..<n {
                var score: Float = 0
                for i in 0..<n {
                    let d = reference[i] - candidate[(i + s) % n]
                    score += simd_length_squared(d)
                }
                if score < bestScore {
                    bestScore = score
                    best = s
                }
            }
            return best
        }

        let shift = bestShift(reference: t, candidate: b)
        if shift != 0 {
            b = Array(b[shift...]) + Array(b[..<shift])
        }

        return (t, b)
    }

    static func loftedVolume(top: [SIMD3<Float>], bottom: [SIMD3<Float>]) -> Float? {
        guard validateContourForVolume(top), validateContourForVolume(bottom) else { return nil }
        let origin = top[0]
        // Recenter BEFORE resampling or unit conversion. A millimeter-scale cavity
        // must not be obtained by subtracting tetrahedra relative to the AR origin.
        guard let loops = alignedResampledLoops(
            top: top.map { $0 - origin }, bottom: bottom.map { $0 - origin },
            targetCount: max(top.count, bottom.count)
        ) else { return nil }
        return enclosedVolume(top: loops.t, bottom: loops.b)
    }
    static func robustLoftMetricsMM(top: [SIMD3<Float>], bottom: [SIMD3<Float>]) -> (topAreaMM2: Float?, bottomAreaMM2: Float?, volumeMM3: Float?, flags: VolumeQualityFlags) {
        var flags = VolumeQualityFlags()
        guard validateContourForVolume(top), validateContourForVolume(bottom) else {
            flags.incompleteOutline = true
            return (nil, nil, nil, flags)
        }
        let origin = top[0]
        guard let loops = alignedResampledLoops(
            top: top.map { $0 - origin }, bottom: bottom.map { $0 - origin },
            targetCount: max(top.count, bottom.count)
        ) else {
            flags.incompleteOutline = true
            return (nil, nil, nil, flags)
        }
        let topArea = Float(simd_length(areaVector(loops.t)) * 1_000_000)
        let bottomArea = Float(simd_length(areaVector(loops.b)) * 1_000_000)
        flags.bottomLargerThanTop = bottomArea > topArea
        flags.contourMismatch = zip(loops.t, loops.b).contains { simd_length($0 - $1) > 0.1 }
        let volume = enclosedVolume(top: loops.t, bottom: loops.b).map { $0 * 1_000_000_000 }
        if volume == nil { flags.incompleteOutline = true }
        return (topArea, bottomArea, volume, flags)
    }
    static func triangulatePolygon(_ points: [SIMD3<Float>]) -> [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] {
        guard validateContourForVolume(points) else { return [] }

        let normal = polygonNormal(points)
        let (u, v) = planeBasis(from: normal)
        let origin = points[0]

        var pts2D: [CGPoint] = points.map { p in
            let d = p - origin
            let x = CGFloat(simd_dot(d, u))
            let y = CGFloat(simd_dot(d, v))
            return CGPoint(x: x, y: y)
        }

        var indices = Array(0..<points.count)
        var tris: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []

        func area(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
            return 0.5 * ((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x))
        }

        func isCCW() -> Bool {
            var sum: CGFloat = 0
            for i in 0..<pts2D.count {
                let a = pts2D[i]
                let b = pts2D[(i + 1) % pts2D.count]
                sum += (b.x - a.x) * (b.y + a.y)
            }
            return sum < 0
        }

        if !isCCW() {
            pts2D.reverse()
            indices.reverse()
        }

        var guardCounter = 0
        while indices.count >= 3 && guardCounter < 1000 {
            guardCounter += 1
            var earFound = false
            for i in 0..<indices.count {
                let i0 = (i - 1 + indices.count) % indices.count
                let i1 = i
                let i2 = (i + 1) % indices.count

                let a = pts2D[i0]
                let b = pts2D[i1]
                let c = pts2D[i2]

                if area(a, b, c) <= 0 { continue }

                var contains = false
                for j in 0..<indices.count where j != i0 && j != i1 && j != i2 {
                    if pointInTriangle(pts2D[j], a, b, c) {
                        contains = true
                        break
                    }
                }
                if contains { continue }

                let pa = points[indices[i0]]
                let pb = points[indices[i1]]
                let pc = points[indices[i2]]
                tris.append((pa, pb, pc))

                pts2D.remove(at: i1)
                indices.remove(at: i1)
                earFound = true
                break
            }
            if !earFound { break }
        }
        return tris
    }
    static func polygonNormal(_ points: [SIMD3<Float>]) -> SIMD3<Float> {
        let vector = areaVector(points)
        let length = simd_length(vector)
        guard length.isFinite, length > 0 else { return .zero }
        return SIMD3<Float>(vector / length)
    }
    static func planeBasis(from normal: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
        let n = simd_normalize(normal)
        let up = abs(n.y) < 0.9 ? SIMD3<Float>(0,1,0) : SIMD3<Float>(1,0,0)
        let u = simd_normalize(simd_cross(up, n))
        let v = simd_normalize(simd_cross(n, u))
        return (u, v)
    }
    static func pointInTriangle(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Bool {
        let v0 = CGPoint(x: c.x - a.x, y: c.y - a.y)
        let v1 = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let v2 = CGPoint(x: p.x - a.x, y: p.y - a.y)

        let dot00 = v0.x * v0.x + v0.y * v0.y
        let dot01 = v0.x * v1.x + v0.y * v1.y
        let dot02 = v0.x * v2.x + v0.y * v2.y
        let dot11 = v1.x * v1.x + v1.y * v1.y
        let dot12 = v1.x * v2.x + v1.y * v2.y

        let invDenom = 1.0 / (dot00 * dot11 - dot01 * dot01)
        let u = (dot11 * dot02 - dot01 * dot12) * invDenom
        let v = (dot00 * dot12 - dot01 * dot02) * invDenom
        return u >= 0 && v >= 0 && (u + v) <= 1
    }
    static func computePlanarArea(_ points: [SIMD3<Float>]) -> Float? {
        guard validateContourForVolume(points) else { return nil }
        return Float(simd_length(areaVector(points)) * 10_000)
    }
    static func computePerimeterCM(_ points: [SIMD3<Float>]) -> Float? {
        guard points.count >= 2, points.allSatisfy(isFinite) else { return nil }
        let lengthM = zip(points, points.dropFirst() + [points[0]])
            .reduce(0.0) { $0 + simd_length(SIMD3<Double>($1.1) - SIMD3<Double>($1.0)) }
        let cm = Float(lengthM * 100)
        return cm.isFinite ? cm : nil
    }
    private static func isFinite(_ point: SIMD3<Float>) -> Bool {
        point.x.isFinite && point.y.isFinite && point.z.isFinite
    }

    /// Oriented area in m² for meter inputs, accumulated relative to a local origin.
    private static func areaVector(_ points: [SIMD3<Float>]) -> SIMD3<Double> {
        guard points.count >= 3, points.allSatisfy(isFinite) else { return .zero }
        let origin = SIMD3<Double>(points[0])
        var vector = SIMD3<Double>.zero
        for index in points.indices {
            let a = SIMD3<Double>(points[index]) - origin
            let b = SIMD3<Double>(points[(index + 1) % points.count]) - origin
            vector += simd_cross(a, b) * 0.5
        }
        return vector
    }

    private static func enclosedVolume(top: [SIMD3<Float>], bottom: [SIMD3<Float>]) -> Float? {
        guard top.count == bottom.count, top.count >= 3 else { return nil }
        let topTriangles = triangulatePolygon(top)
        let bottomTriangles = triangulatePolygon(bottom)
        // Ear clipping must cover each cap. A partial cap is an open solid and
        // cannot produce a reliable signed volume.
        func capIsComplete(_ triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)], _ points: [SIMD3<Float>]) -> Bool {
            let covered = triangles.reduce(SIMD3<Double>.zero) { sum, triangle in
                sum + simd_cross(SIMD3<Double>(triangle.1) - SIMD3<Double>(triangle.0),
                                 SIMD3<Double>(triangle.2) - SIMD3<Double>(triangle.0)) * 0.5
            }
            let expected = areaVector(points)
            return simd_length(covered - expected) <= max(1e-12, simd_length(expected) * 0.001)
        }
        guard capIsComplete(topTriangles, top), capIsComplete(bottomTriangles, bottom) else { return nil }
        func tetrahedron(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> Double {
            simd_dot(SIMD3<Double>(a), simd_cross(SIMD3<Double>(b), SIMD3<Double>(c))) / 6
        }
        var volume = 0.0
        for index in top.indices {
            let next = (index + 1) % top.count
            volume += tetrahedron(top[index], bottom[index], top[next])
            volume += tetrahedron(top[next], bottom[index], bottom[next])
        }
        for t in topTriangles { volume += tetrahedron(t.0, t.1, t.2) }
        for t in bottomTriangles { volume += tetrahedron(t.2, t.1, t.0) }
        let result = Float(abs(volume))
        return result.isFinite ? result : nil
    }

}
