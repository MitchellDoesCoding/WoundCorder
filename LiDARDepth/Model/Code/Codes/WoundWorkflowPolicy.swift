import Foundation

enum WoundWorkflowPolicy {
    static func candidateCount(topProbability: Float, combined: Bool) -> Int {
        combined || !topProbability.isFinite || topProbability < 0.5 ? 2 : 1
    }
    /// Accept either decimal separator; reject grouping/ambiguous mixed separators.
    static func decimalInput(_ input: String) -> Double? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(text.contains(",") && text.contains(".")),
              text.filter({ $0 == "," }).count <= 1 else { return nil }
        return Double(text.replacingOccurrences(of: ",", with: "."))
    }
    static func bmi(heightCM: String, weightKG: String) -> Double? {
        guard let cm = decimalInput(heightCM),
              let kg = decimalInput(weightKG),
              cm.isFinite, kg.isFinite, cm > 0, kg > 0 else { return nil }
        let value = kg / pow(cm / 100, 2)
        return value.isFinite ? value : nil
    }
}
