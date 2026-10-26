import Foundation

/// Sensor timestamps, rather than inference completion times, determine freshness.
struct WoundDetectionFrameGate {
    private(set) var lastSubmittedTimestamp: TimeInterval?

    static func isFresh(capturedAt: TimeInterval, now: TimeInterval, maximumAge: TimeInterval) -> Bool {
        capturedAt.isFinite && now.isFinite && maximumAge.isFinite && maximumAge >= 0
            && capturedAt <= now && now - capturedAt <= maximumAge
    }

    mutating func submit(capturedAt: TimeInterval, now: TimeInterval, maximumAge: TimeInterval) -> Bool {
        guard Self.isFresh(capturedAt: capturedAt, now: now, maximumAge: maximumAge),
              lastSubmittedTimestamp.map({ capturedAt > $0 }) ?? true else { return false }
        lastSubmittedTimestamp = capturedAt
        return true
    }
}
