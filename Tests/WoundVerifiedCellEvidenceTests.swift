import Foundation

@main
struct WoundVerifiedCellEvidenceTests {
    static func main() {
        var cell = WoundVerifiedCellEvidence(offset: 0.01)
        cell.observe(offset: 0.03, view: 1)
        precondition(!cell.isInvalidated, "One bad angle cannot erase verified coverage")
        cell.observe(offset: 0.011, view: 2)
        precondition(!cell.isInvalidated)
        for _ in 0..<5 { cell.observe(offset: 0.03, view: 3) }
        precondition(!cell.isInvalidated, "A single disagreeing viewpoint cannot invalidate a verified patch")
        cell.observe(offset: 0.03, view: 4)
        precondition(!cell.isInvalidated, "Crossing an angle boundary once must not erase prior points")
        cell.observe(offset: 0.031, view: 4)
        cell.observe(offset: 0.03, view: 4)
        precondition(cell.isInvalidated, "Sustained cross-view disagreement must invalidate coverage")
        cell.observe(offset: 0.01, view: 5)
        precondition(cell.isInvalidated, "Old evidence must not immediately reverify a conflicted patch")
        var moving = WoundVerifiedCellEvidence(offset: 0.01)
        for _ in 0..<6 {
            moving.observe(offset: 0.025, view: 1)
            moving.observe(offset: -0.005, view: 2)
        }
        precondition(!moving.isInvalidated, "Incoherent motion noise must retain earlier verified geometry")
        moving.observe(offset: 0.011, view: 3)
        for _ in 0..<3 { moving.observe(offset: 0.025, view: 2) }
        precondition(!moving.isInvalidated, "An agreeing revisit clears old conflicts")
        var other = WoundVerifiedCellEvidence(offset: 0.01)
        for view in 0..<20 {
            other.observe(offset: .nan, view: view)
            other.observe(offset: 0.012, view: view)
        }
        precondition(!other.isInvalidated)
        precondition(!WoundVerifiedCellEvidence(offset: 0.01).isInvalidated, "A new scan starts fresh")
        print("PASS: verified-cell retention, isolated noise, single-view bias, sustained conflict, and scan reset")
    }
}
