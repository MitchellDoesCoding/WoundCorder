import Foundation

enum WoundSemanticMath {
    static func probabilities(logits: [Float], temperature: Float) -> [Float]? {
        guard !logits.isEmpty, logits.allSatisfy(\.isFinite), temperature.isFinite, temperature > 0,
              let maximum = logits.max() else { return nil }
        let weights = logits.map { exp((Double($0) - Double(maximum)) / Double(temperature)) }
        let total = weights.reduce(0, +)
        guard total.isFinite, total > 0 else { return nil }
        return weights.map { Float($0 / total) }
    }
    static func sigmoid(_ value: Float) -> Float { Float(1 / (1 + exp(-Double(value)))) }
    static func normalized(_ vector: [Float]) -> [Float]? {
        guard !vector.isEmpty, vector.allSatisfy(\.isFinite) else { return nil }
        let norm = sqrt(vector.reduce(0.0) { $0 + Double($1) * Double($1) })
        guard norm.isFinite, norm > 0 else { return nil }
        return vector.map { Float(Double($0) / norm) }
    }
}
