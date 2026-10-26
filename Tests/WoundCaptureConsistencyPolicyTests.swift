import Foundation

@main
struct WoundCaptureConsistencyPolicyTests {
    static func main() {
        typealias Policy = WoundCaptureConsistencyPolicy
        typealias Sample = WoundMeasurementConsistency.VolumetricMetricSample
        func sample(_ area: Float = 10, _ volume: Float = 1, quality: Int = 1) -> Sample {
            Sample(perimeter: 12, area: area, volume: volume, qualityRank: quality)
        }
        precondition(!Policy.hasCoverage(expectedCells: 100, verifiedCells: 59, viewpoints: 4, rimPoints: 32, elapsed: 20))
        precondition(Policy.hasCoverage(expectedCells: 100, verifiedCells: 60, viewpoints: 4, rimPoints: 32, elapsed: 6))
        precondition(!Policy.hasCoverage(expectedCells: 100, verifiedCells: 90, viewpoints: 2, rimPoints: 32, elapsed: 20))
        precondition(!Policy.hasCoverage(expectedCells: 100, verifiedCells: 90, viewpoints: 4, rimPoints: 31, elapsed: 20))
        precondition(!Policy.hasCoverage(expectedCells: 100, verifiedCells: 90, viewpoints: 4, rimPoints: 32, elapsed: 3.99))
        precondition(!Policy.hasCoverage(expectedCells: 0, verifiedCells: 90, viewpoints: 4, rimPoints: 32, elapsed: 20))
        precondition(!Policy.hasCoverage(expectedCells: 100, verifiedCells: 90, viewpoints: 4, rimPoints: 32, elapsed: .infinity))
        precondition(Policy.coveragePercent == 60)
        // Lower coverage never bypasses independent views or depth agreement.
        precondition(!Policy.hasCoverage(expectedCells: 100, verifiedCells: 60, viewpoints: 1, rimPoints: 32, elapsed: 20))
        precondition(!Policy.hasCoverage(expectedCells: 100, verifiedCells: 60, viewpoints: 3, rimPoints: 0, elapsed: 20))
        // Good coverage can collect estimates before the five-second floor.
        precondition(Policy.hasSufficientEvidence(expectedCells: 100, verifiedCells: 60, viewpoints: 3, rimPoints: 32))
        precondition(Policy.hasCoverage(expectedCells: 100, verifiedCells: 60, viewpoints: 3, rimPoints: 32, elapsed: 5))
        precondition(!Policy.hasSufficientEvidence(expectedCells: 100, verifiedCells: 59, viewpoints: 3, rimPoints: 32))
        precondition(!Policy.hasCoverage(expectedCells: 100, verifiedCells: 59, viewpoints: 3, rimPoints: 32, elapsed: 10))
        precondition(!Policy.hasConverged([sample(), sample()]))
        precondition(Policy.hasConverged([sample(10, 1), sample(10.3, 1.04), sample(10.7, 1.09)]))
        precondition(!Policy.hasConverged([sample(10), sample(10.4), sample(11.2)]))
        precondition(!Policy.hasConverged([sample(10, 1), sample(10, 1.05), sample(10, 1.12)]))
        precondition(Policy.hasConverged([sample(10, 1), sample(10.1, 1.02), sample(10.2, 1.04)]))
        precondition(!Policy.hasConverged([sample(), sample(10, 1.4), sample()]), "A volume jump must not finalize")
        precondition(!Policy.hasConverged([sample(), sample(12), sample()]), "An area jump must not finalize")
        precondition(!Policy.hasConverged([sample(), sample(), sample(quality: 0)]))
        precondition(!Policy.hasConverged([sample(), sample(), sample(.nan)]))
        precondition(Policy.hasConverged([sample(10, 0), sample(10, 0.01), sample(10, 0.02)]))
        // A moving sweep may produce one frame in each angle bin; those two
        // independent views must be compared without a redundant per-view wait.
        let firstView = Policy.stableViewOffset([0.01])!
        let secondView = Policy.stableViewOffset([0.011])!
        precondition(Policy.agreeingIndices([firstView, secondView]) == [0, 1])
        precondition(Policy.stableViewOffset([]) == nil)
        precondition(Policy.stableViewOffset([.nan]) == nil)
        precondition(Policy.stableViewOffset([0.01, 0.04]) == nil)
        precondition(Policy.agreeingIndices([0]).isEmpty, "One viewpoint is insufficient")
        precondition(Policy.agreeingIndices([0, 0.02]).isEmpty, "Disagreeing viewpoints cannot inflate tolerance")
        precondition(Policy.agreeingIndices([0, 0.001, 0.04]) == [0, 1])
        precondition(Policy.agreeingIndices([0, 0.001, 0.02, 0.021]).isEmpty, "Competing surfaces lack a majority")
        precondition(Policy.agreeingIndices([0, .nan]).isEmpty)
        print("PASS: three-estimate convergence, jump rejection, multi-view point consensus, and outlier rejection")
    }
}
