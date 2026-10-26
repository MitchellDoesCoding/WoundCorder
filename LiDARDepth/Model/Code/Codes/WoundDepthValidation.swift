import Foundation

/// ARKit confidence values are categorical: low=0, medium=1, high=2.
/// An all-low map is not a differently scaled high-confidence map.
enum WoundDepthValidation {
    static func isUsable(depth: Float, confidence: UInt8?) -> Bool {
        depth.isFinite && depth > 0.02 && depth < 5 && (confidence == 1 || confidence == 2)
    }
    static func normalizedConfidence(_ value: UInt8?) -> Float {
        switch value { case 1: return 0.5; case 2: return 1; default: return 0 }
    }
}
