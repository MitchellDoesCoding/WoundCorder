import Foundation

@main
struct WoundBoundaryReviewPolicyTests {
    static func main() {
        func review(_ count: Int, _ captured: Double, start: Double = 100, now: Double = 104) -> Bool {
            WoundBoundaryReviewPolicy.canReview(matchingObservations: count, capturedAt: captured,
                scanStartedAt: start, now: now, maximumAge: 4.5)
        }
        precondition(review(2, 103), "A fresh matched pair must reach user review without four detections")
        precondition(!review(1, 103), "A single candidate must not bypass matching")
        precondition(!review(4, 99), "A previous scan cannot supply confirmation")
        precondition(!review(4, 101, now: 106), "Stale matching evidence must not enable review")
        precondition(!review(2, 105), "Future frames must not enable review")
        precondition(!review(2, .nan))
        precondition(!review(2, 103, start: .nan))
        precondition(!review(2, 103, now: .infinity))
        precondition(review(2, 100, now: 104.5))
        print("PASS: matched-pair boundary review, single-frame rejection, scan isolation, freshness, and invalid timestamps")
    }
}
