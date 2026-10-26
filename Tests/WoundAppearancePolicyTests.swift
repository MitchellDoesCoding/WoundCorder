import Foundation
@main struct WoundAppearancePolicyTests {
    static func main() {
        func score(_ color: Float, _ depth: Float) -> Float {
            WoundAppearancePolicy.score(color: color, contrast: 0.3, depth: depth, center: 1, borderPenalty: 0)
        }
        precondition(score(0.1, 1) == 0, "Depth-only relief cannot select normal surrounding skin")
        precondition(score(0.8, 0) > 0.6, "Visible discoloration can stand without a depression")
        precondition(score(0.8, 1) - score(0.8, 0) <= 0.041, "Depth contribution stays bounded")
        precondition(score(.nan, 0) == 0)
        print("PASS: appearance-led detection, depth-only rejection, bounded geometry, invalid input")
    }
}
