import Foundation

enum WoundAppearancePolicy {
    /// Geometry can reinforce an appearance cue, never create a wound boundary.
    static func score(color: Float, contrast: Float, depth: Float, center: Float, borderPenalty: Float) -> Float {
        guard [color, contrast, depth, center, borderPenalty].allSatisfy(\.isFinite),
              color >= 0.20 else { return 0 }
        func unit(_ value: Float) -> Float { min(1, max(0, value)) }
        let support = unit((color - 0.20) / 0.50)
        return unit(0.76 * unit(color) + 0.16 * unit(contrast) +
                    0.04 * unit(depth) * support + 0.04 * unit(center) - max(0, borderPenalty))
    }
}
