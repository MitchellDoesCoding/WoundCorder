import ARKit
import simd

class LiDARVolumeCalculator {
    // These properties exist so ARViewController can assign them:
    var scannedMeshAnchors: [ARMeshAnchor] = []
    
    /// The user-defined wound boundary points.
    var woundBoundaryPoints: [SIMD3<Float>] = []
    
    /// If you're doing the "select depth point" logic
    var userSelectedPoint: SIMD3<Float>?
    
    /// Store previously computed metrics if you want to check for "significant change"
    private var lastCalculatedMetrics: (perimeter: Float, area: Float, volume: Float)?
    
    // MARK: - Optional: Smoothing Helpers
    
    private func smoothBoundaryPoints(_ points: [SIMD3<Float>], iterations: Int = 1) -> [SIMD3<Float>] {
        guard points.count > 2 else { return points }
        var result = points
        for _ in 0..<iterations {
            result = chaikinSmoothOnce(result)
        }
        return result
    }

    /// Chaikin's algorithm for polygon smoothing (once).
    private func chaikinSmoothOnce(_ points: [SIMD3<Float>]) -> [SIMD3<Float>] {
        // Must be treated as a closed polygon.
        var newPoints: [SIMD3<Float>] = []
        for i in 0..<points.count {
            let current = points[i]
            let next = points[(i + 1) % points.count]
            let q = (current * 0.75) + (next * 0.25)
            let r = (current * 0.25) + (next * 0.75)
            newPoints.append(q)
            newPoints.append(r)
        }
        return newPoints
    }
    
    // MARK: - Public method your ARViewController calls:
    
    /// Main entry point for calculating perimeter, area, volume.
    func calculateMetrics(
        from session: ARSession,
        cameraPosition: SIMD3<Float>,
        completion: @escaping (Float, Float, Float) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            // 1) Perimeter in cm, from the boundary polygon
            let perimeter = self.calculatePerimeterFromBoundary()
            
            // 2) Area in cm², from the boundary polygon
            let area = self.calculateAreaFromBoundary()
            
            // 3) Volume in cm³
            let volume = self.calculateVolumeSimple()

            let newMetrics = (perimeter, area, volume)

            // If you only want to send updates when there's a big change:
            if self.lastCalculatedMetrics == nil || self.hasSignificantChange(newMetrics) {
                self.lastCalculatedMetrics = newMetrics
                DispatchQueue.main.async {
                    completion(perimeter, area, volume)
                }
            }
        }
    }

    // MARK: - Perimeter (cm)

    private func calculatePerimeterFromBoundary() -> Float {
        // Optional: smooth the boundary
        let points = smoothBoundaryPoints(woundBoundaryPoints, iterations: 1)
        guard points.count > 1 else { return 0.0 }

        var perimeter: Float = 0.0
        for i in 0..<(points.count - 1) {
            perimeter += distance(points[i], points[i + 1])
        }
        // Close the polygon
        perimeter += distance(points.last!, points.first!)

        // Convert meters to cm
        return perimeter * 100.0
    }

    // MARK: - Area (cm²) - 2D projection via plane

    private func calculateAreaFromBoundary() -> Float {
        // Optional: smooth the boundary
        let points = smoothBoundaryPoints(woundBoundaryPoints, iterations: 1)
        guard points.count > 2 else { return 0.0 }

        // Fit a plane from the first three points (for simplicity)
        let planeOrigin = points[0]
        let planeNormal = bestFitNormal(points: points)

        // Create an orthonormal basis for that plane
        let up = simd_normalize(planeNormal)
        let arbitrary = abs(up.x) < 0.9 ? SIMD3<Float>(1,0,0) : SIMD3<Float>(0,1,0)
        let right = simd_normalize(simd_cross(up, arbitrary))
        let forward = simd_cross(up, right)

        // Project each boundary point into 2D
        var projected2D = [SIMD2<Float>]()
        for p in points {
            let rel = p - planeOrigin
            let x = simd_dot(rel, right)
            let y = simd_dot(rel, forward)
            projected2D.append(SIMD2<Float>(x, y))
        }

        // Shoelace formula => area in m²
        let areaM2 = shoelaceArea2D(projected2D)

        // Convert m² => cm²
        return areaM2 * 10_000.0
    }

    // MARK: - Volume (cm³)

    /// volume = area_in_m² * depth_in_m => cm³
    /// We'll define "depth" as the perpendicular distance from userSelectedPoint
    /// to the plane of the boundary.
    private func calculateVolumeSimple() -> Float {
        guard woundBoundaryPoints.count > 2, let depthPoint = userSelectedPoint else {
            return 0.0
        }

        // 1) Get area in m²
        let areaCm2 = calculateAreaFromBoundary()
        let areaM2 = areaCm2 / 10_000.0

        // 2) Fit plane
        let planeOrigin = woundBoundaryPoints[0]
        let planeNormal = bestFitNormal(points: woundBoundaryPoints)

        // 3) Distance from depthPoint to that plane
        let distM = pointToPlaneDistance(point: depthPoint,
                                         planeOrigin: planeOrigin,
                                         planeNormal: planeNormal)

        // 4) volume (m³) = areaM2 * distM -> cm³
        let volumeM3 = areaM2 * distM
        return volumeM3 * 1_000_000.0
    }

    // MARK: - Helpers

    private func hasSignificantChange(_ newMetrics: (Float, Float, Float)) -> Bool {
        guard let last = lastCalculatedMetrics else { return true }
        let (pOld, aOld, vOld) = last
        let (pNew, aNew, vNew) = newMetrics

        return abs(pOld - pNew) > 0.1 ||
               abs(aOld - aNew) > 0.1 ||
               abs(vOld - vNew) > 0.1
    }

    /// Estimate a plane normal using cross of vectors from first 3 points.
    private func bestFitNormal(points: [SIMD3<Float>]) -> SIMD3<Float> {
        guard points.count >= 3 else {
            // fallback if fewer than 3
            return SIMD3<Float>(0, 1, 0)
        }
        let v1 = points[1] - points[0]
        let v2 = points[2] - points[0]
        let normal = simd_cross(v1, v2)
        return normal
    }

    /// Shoelace formula in 2D => area in m²
    private func shoelaceArea2D(_ pts: [SIMD2<Float>]) -> Float {
        guard pts.count >= 3 else { return 0 }
        var area: Float = 0
        for i in 0..<pts.count {
            let j = (i + 1) % pts.count
            area += (pts[i].x * pts[j].y) - (pts[j].x * pts[i].y)
        }
        return abs(area) / 2.0
    }

    /// Signed distance from point to plane(planeOrigin, planeNormal).
    private func pointToPlaneDistance(point: SIMD3<Float>,
                                      planeOrigin: SIMD3<Float>,
                                      planeNormal: SIMD3<Float>) -> Float {
        let diff = point - planeOrigin
        let n = simd_normalize(planeNormal)
        let dist = simd_dot(diff, n)
        return abs(dist)
    }

    // MARK: - (Optional) Calibration

    /// A global scale factor you can apply (e.g. if you measured a known reference).
    var calibrationScale: Float = 1.0

    /// Example method: The user picks two points on a known reference object.
    /// Suppose that object is knownLengthInM meters in real life.
    func calibrateWithKnownLength(_ knownLengthInM: Float) {
        guard woundBoundaryPoints.count >= 2 else { return }
        let p1 = woundBoundaryPoints[0]
        let p2 = woundBoundaryPoints[1]
        let measuredDistance = distance(p1, p2) // in meters
        if measuredDistance > 0.001 {
            calibrationScale = knownLengthInM / measuredDistance
            print("Calibrated. scale factor = \(calibrationScale)")
        }
    }

    /// Scale a raw distance by the calibration factor
    func scaledDistance(_ p1: SIMD3<Float>, _ p2: SIMD3<Float>) -> Float {
        let rawDist = distance(p1, p2) // in meters
        return rawDist * calibrationScale
    }

    /// Example of a perimeter in meters, then scaled
    /// (If you want perimeter in cm, multiply by 100 again.)
    func scaledPerimeter() -> Float {
        let pm = perimeterInMeters()
        return pm * calibrationScale
    }

    private func perimeterInMeters() -> Float {
        let pts = woundBoundaryPoints
        guard pts.count > 1 else { return 0 }
        var perimeterM: Float = 0
        for i in 0..<(pts.count - 1) {
            perimeterM += distance(pts[i], pts[i+1])
        }
        perimeterM += distance(pts.last!, pts.first!)
        return perimeterM
    }
}
