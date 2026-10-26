import Foundation

/// Engineering acceptance gates for a confirmed wound's multi-view capture.
/// These are not clinical accuracy guarantees.
enum WoundCaptureConsistencyPolicy {
    static let coverageFraction = 0.60
    static let minimumViews = 3
    static let viewSeparationDegrees: Float = 5
    static var coveragePercent: Int { Int((coverageFraction * 100).rounded()) }
    static let minimumRimPoints = 32
    static let minimumCaptureSeconds = 4.0
    static let estimateInterval = 0.35
    static let requiredEstimates = 3
    static let maximumOffsetDeviation: Float = 0.0035

    static func hasCoverage(expectedCells: Int, verifiedCells: Int, viewpoints: Int,
                            rimPoints: Int, elapsed: TimeInterval) -> Bool {
        guard expectedCells > 0, elapsed.isFinite else { return false }
        return hasSufficientEvidence(expectedCells: expectedCells, verifiedCells: verifiedCells,
                                     viewpoints: viewpoints, rimPoints: rimPoints)
            && elapsed >= minimumCaptureSeconds
    }

    /// Start convergence checks as soon as coverage is sound, while the minimum
    /// capture time is still running. Time alone never substitutes for evidence.
    static func hasSufficientEvidence(expectedCells: Int, verifiedCells: Int,
                                      viewpoints: Int, rimPoints: Int) -> Bool {
        guard expectedCells > 0 else { return false }
        let required = max(5, Int(ceil(Double(expectedCells) * coverageFraction)))
        return verifiedCells >= required && viewpoints >= minimumViews
            && rimPoints >= minimumRimPoints
    }

    /// One sample from each of two distinct views is already independent evidence.
    /// Additional samples within a view must remain coherent.
    static func stableViewOffset(_ offsets: [Float]) -> Float? {
        guard !offsets.isEmpty, offsets.allSatisfy(\.isFinite),
              let center = WoundMeasurementConsistency.medianValue(offsets.sorted()),
              let mad = WoundMeasurementConsistency.medianValue(offsets.map { abs($0 - center) }.sorted()),
              mad <= maximumOffsetDeviation else { return nil }
        return center
    }

    static func agreeingIndices(_ offsets: [Float]) -> [Int] {
        guard offsets.count >= 2, offsets.allSatisfy(\.isFinite),
              let center = WoundMeasurementConsistency.medianValue(offsets.sorted()) else { return [] }
        let indices = offsets.indices.filter { abs(offsets[$0] - center) <= maximumOffsetDeviation }
        return indices.count >= max(2, offsets.count / 2 + 1) ? indices : []
    }

    static func hasConverged(_ samples: [WoundMeasurementConsistency.VolumetricMetricSample]) -> Bool {
        guard samples.count >= requiredEstimates else { return false }
        let recent = Array(samples.suffix(requiredEstimates))
        guard recent.allSatisfy({ $0.qualityRank >= 1 && $0.area.isFinite && $0.area > 0
            && $0.perimeter.isFinite && $0.perimeter > 0 && $0.volume.isFinite && $0.volume >= 0 }) else { return false }
        func agrees(_ values: [Float], relative: Float, absolute: Float = 0) -> Bool {
            let sorted = values.sorted()
            let median = sorted[sorted.count / 2]
            return sorted.last! - sorted.first! <= max(absolute, median * relative)
        }
        return agrees(recent.map(\.area), relative: 0.10)
            && agrees(recent.map(\.perimeter), relative: 0.10)
            && agrees(recent.map(\.volume), relative: 0.10, absolute: 0.03)
    }
}
