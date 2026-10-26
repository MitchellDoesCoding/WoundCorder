import Foundation
import simd

@main
struct WoundMeasurementRegressionTests {
    static var checks = 0
    static func check(_ condition: Bool, _ message: String) {
        precondition(condition, message)
        checks += 1
    }
    static func near(_ actual: Float?, _ expected: Float, relative: Float = 0.001, _ message: String) {
        guard let actual else { fatalError("Missing value: \(message)") }
        check(actual.isFinite && abs(actual - expected) <= max(1e-10, abs(expected) * relative),
              "\(message): expected \(expected), got \(actual)")
    }
    static func main() {
        geometry()
        consistency()
        detectionFrames()
        print("PASS: \(checks) geometry, consensus, and frame-freshness regression checks")
    }
    static func geometry() {
        let square: [SIMD3<Float>] = [[0,0,0],[0.02,0,0],[0.02,0.02,0],[0,0.02,0]]
        let bottom = square.map { $0 + SIMD3<Float>(0,0,-0.005) }
        near(WoundGeometry.computePerimeterCM(square), 8, "Square perimeter in cm")
        near(WoundGeometry.computePlanarArea(square), 4, "Square area in cm²")
        let rotation = simd_quatf(angle: 0.91, axis: simd_normalize(SIMD3<Float>(1,2,3)))
        for shift: SIMD3<Float> in [[0,0,0],[1,1,1],[3,-2,4],[10,10,10]] {
            for rotated in [false, true] {
                let transform: (SIMD3<Float>) -> SIMD3<Float> = { (rotated ? rotation.act($0) : $0) + shift }
                let t = square.map(transform), b = bottom.map(transform)
                for reverse in [false, true] {
                    let candidate = reverse ? Array(b.reversed()) : b
                    for offset in 0..<candidate.count {
                        let shiftedBottom = Array(candidate[offset...]) + Array(candidate[..<offset])
                        let metrics = WoundGeometry.robustLoftMetricsMM(top: t, bottom: shiftedBottom)
                        near(metrics.volumeMM3, 2000, "Translation/rotation/winding/start invariance")
                        near(metrics.topAreaMM2, 400, "Rim area in mm²")
                        near(WoundGeometry.loftedVolume(top: t, bottom: shiftedBottom), 0.000002,
                             "Volume in m³")
                        check(!metrics.flags.incompleteOutline, "Valid solid must have complete caps")
                    }
                }
            }
        }
        let smallBottom = square.map { $0 * 0.5 + SIMD3<Float>(0.005,0.005,-0.005) }
        let frustum = WoundGeometry.robustLoftMetricsMM(top: square, bottom: smallBottom)
        near(frustum.volumeMM3, 1166.6667, "Square frustum volume")
        near(frustum.topAreaMM2, 400, "Smaller bottom must not change rim area")
        let concave: [SIMD3<Float>] = [[0,0,0],[0.04,0,0],[0.04,0.01,0],[0.01,0.01,0],[0.01,0.04,0],[0,0.04,0]]
        near(WoundGeometry.robustLoftMetricsMM(top: concave, bottom: concave.map { $0 + SIMD3<Float>(0,0,-0.005) }).volumeMM3,
             3500, "Concave L-shaped prism")
        for invalid: [SIMD3<Float>] in [[], [[0,0,0],[1,0,0]], [[0,0,0],[0.02,0,0],[0.01,1e-9,0]],
                                       [[0,0,0],[0,0,0],[0,0,0]], [[0,0,0],[.nan,0,0],[0,1,0]],
                                       [[0,0,0],[.infinity,0,0],[0,1,0]]] {
            check(!WoundGeometry.validateContourForVolume(invalid), "Reject degenerate/nonfinite outline")
            check(WoundGeometry.robustLoftMetricsMM(top: invalid, bottom: bottom).volumeMM3 == nil,
                  "Invalid outline cannot produce volume")
        }
        let dense = WoundGeometry.resampleClosedPolyline(square, targetCount: 64)
        near(WoundGeometry.robustLoftMetricsMM(top: dense, bottom: bottom).volumeMM3, 2000,
             "Trace density invariance")
        near(WoundGeometry.robustLoftMetricsMM(top: Array(square.reversed()), bottom: Array(bottom.reversed())).volumeMM3,
             2000, "Reversing both loops")
    }
    static func consistency() {
        typealias Sample = WoundMeasurementConsistency.VolumetricMetricSample
        func sample(_ area: Float, _ volume: Float, quality: Int = 1) -> Sample {
            Sample(perimeter: 8, area: area, volume: volume, qualityRank: quality)
        }
        func stable(_ samples: [Sample]) -> Bool {
            WoundMeasurementConsistency.stabilizedVolumetricMetrics(samples)?.hasConsensus == true
        }
        check(!stable([]), "No samples")
        check(!stable([sample(4,2)]), "One frame cannot establish consensus")
        check(stable([sample(4,2),sample(4.1,2.1)]), "Two close medium-quality frames")
        check(!stable([sample(4,2),sample(5,2)]), "Reject area disagreement")
        check(!stable([sample(4,2),sample(4,3)]), "Reject volume disagreement")
        check(!stable([sample(4,2,quality:0),sample(4,2,quality:0)]), "Low quality cannot establish consensus")
        check(stable([sample(4,2),sample(4,2),sample(4,2),sample(100,100)]), "One outlier must not veto three agreeing frames")
        check(!stable([sample(10,50),sample(10,50),sample(10,10),sample(50,10),sample(50,10)]),
              "Independent area/volume majorities are not a paired consensus")
        check(stable([sample(4,0),sample(4,0)]), "Consistent area-only observations")
        check(!stable([sample(4,0),sample(4,0),sample(4,2)]), "One positive volume must not become consensus")
        check(!stable([sample(.nan,2),sample(4,.infinity),sample(-1,2)]), "Invalid measurements")
    }
    static func detectionFrames() {
        var gate = WoundDetectionFrameGate()
        check(gate.submit(capturedAt: 100, now: 100.1, maximumAge: 4.5), "First recent frame")
        check(!gate.submit(capturedAt: 100, now: 100.2, maximumAge: 4.5), "Repeated ARFrame cannot count twice")
        check(!gate.submit(capturedAt: 99.9, now: 100.2, maximumAge: 4.5), "Out-of-order frame")
        check(!gate.submit(capturedAt: 100.2, now: 106, maximumAge: 4.5), "Stale submission")
        check(gate.submit(capturedAt: 106, now: 106.1, maximumAge: 4.5), "Next fresh frame")
        check(!WoundDetectionFrameGate.isFresh(capturedAt: 106, now: 111, maximumAge: 4.5), "Slow inference does not refresh frame age")
        check(!WoundDetectionFrameGate.isFresh(capturedAt: .nan, now: 111, maximumAge: 4.5), "Nonfinite timestamp")
        check(!WoundDetectionFrameGate.isFresh(capturedAt: 112, now: 111, maximumAge: 4.5), "Future timestamp")
    }
}
