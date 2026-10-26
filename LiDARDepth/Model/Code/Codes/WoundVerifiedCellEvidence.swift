import Foundation

/// Retain accepted geometry unless repeated observations agree on a different
/// surface from two views. Motion noise alone must not erase earlier evidence.
struct WoundVerifiedCellEvidence {
    let offset: Float
    private(set) var isInvalidated = false
    private var conflictingOffsets: [Int: [Float]] = [:]

    init(offset: Float) { self.offset = offset }

    mutating func observe(offset candidate: Float, view: Int) {
        guard !isInvalidated, candidate.isFinite else { return }
        let tolerance = WoundCaptureConsistencyPolicy.maximumOffsetDeviation
        if abs(candidate - offset) <= tolerance {
            conflictingOffsets.removeAll(keepingCapacity: true)
            return
        }
        var observations = conflictingOffsets[view] ?? []
        observations.append(candidate)
        conflictingOffsets[view] = Array(observations.suffix(3))
        // Each opposing view must independently repeat a coherent depth.
        let centers = conflictingOffsets.values.compactMap { samples -> Float? in
            guard samples.count == 3,
                  let low = samples.min(), let high = samples.max(),
                  high - low <= tolerance else { return nil }
            return samples.sorted()[1]
        }
        // Opposite-side noise, or conflicting depths from different angles, is
        // not evidence of a replacement surface.
        for center in centers {
            let coherent = centers.filter {
                ($0 - offset) * (center - offset) > 0 && abs($0 - center) <= tolerance
            }
            if coherent.count >= 2 { isInvalidated = true; return }
        }
    }
}
