import Foundation

/// Review eligibility is separate from final measurement quality. Two matching
/// observations establish a candidate; the user still confirms its boundary.
enum WoundBoundaryReviewPolicy {
    static let minimumMatchingObservations = 2
    static let mappingTimeout: TimeInterval = 20

    static func canReview(matchingObservations: Int, capturedAt: TimeInterval,
                          scanStartedAt: TimeInterval, now: TimeInterval,
                          maximumAge: TimeInterval) -> Bool {
        matchingObservations >= minimumMatchingObservations
            && scanStartedAt.isFinite && capturedAt >= scanStartedAt
            && WoundDetectionFrameGate.isFresh(capturedAt: capturedAt, now: now, maximumAge: maximumAge)
    }
}
