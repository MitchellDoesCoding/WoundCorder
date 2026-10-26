import Foundation

/// Model text is data, never HTML, executable markup, or a source of new diagnoses.
struct WoundContextComments: Codable {
    enum Assessment: String, Codable { case possibleMatches = "possible_matches", unableToDetermine = "unable_to_determine" }
    var assessment: Assessment? = nil // Missing only in older saved records.
    var isUnableToDetermine: Bool { assessment == .unableToDetermine }
    static let unsureMessage = "Unable to determine the wound type. No wound labels are shown. Try a clearer, well-lit photo or ask your care team to assess the wound. This does not mean the wound is harmless."
    let candidate_labels: [WoundClass]
    let summary: String
    let observations: [String]
    let care_questions: [String]
    let limitations: String

    static func parse(_ raw: String, allowedLabels: [WoundClass]? = nil) -> WoundContextComments? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```"), let newline = text.firstIndex(of: "\n"), text.hasSuffix("```") {
            text = String(text[text.index(after: newline)...].dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = text.data(using: .utf8),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              !value.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.summary.count <= 2000, value.limitations.count <= 2000,
              value.observations.count <= 8, value.care_questions.count <= 5,
              (value.observations + value.care_questions).allSatisfy({ $0.count <= 1200 }) else { return nil }
        if value.isUnableToDetermine {
            guard value.candidate_labels.isEmpty else { return nil }
        } else {
            guard value.candidate_labels.count == 2, Set(value.candidate_labels).count == 2 else { return nil }
        }
        if let allowedLabels, !Set(value.candidate_labels).isSubset(of: Set(allowedLabels)) { return nil }
        return value
    }
    var plainText: String {
        if isUnableToDetermine { return Self.unsureMessage }
        return ([summary] + observations + care_questions + [limitations]).joined(separator: "\n\n")
    }
    static func displayText(_ raw: String) -> String { parse(raw)?.plainText ?? raw }
}
