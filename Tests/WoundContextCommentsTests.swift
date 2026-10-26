import Foundation
@main struct WoundContextCommentsTests {
    static func main() throws {
        let valid = WoundContextComments(candidate_labels: [.abrasion, .bruise], summary: "Ask your care team.", observations: ["A mark is visible."], care_questions: ["How long has it been here?"], limitations: "A photo is not a diagnosis.")
        let json = String(decoding: try JSONEncoder().encode(valid), as: UTF8.self)
        precondition(WoundContextComments.parse(json, allowedLabels: [.abrasion, .bruise]) != nil)
        precondition(WoundContextComments.parse("```json\n" + json + "\n```") != nil)
        precondition(WoundContextComments.parse(json, allowedLabels: [.burn, .bruise]) == nil)
        precondition(WoundContextComments.parse(json.replacingOccurrences(of: "bruise", with: "abrasion")) == nil)
        precondition(WoundContextComments.parse("<html>fake result</html>") == nil)
        precondition(WoundContextComments.parse("{}") == nil)
        precondition(WoundContextComments.displayText(json).contains("Ask your care team."))
        precondition(!WoundContextComments.displayText(json).contains("candidate_labels"))
        let unsure = WoundContextComments(assessment: .unableToDetermine, candidate_labels: [],
            summary: "Insufficient evidence.", observations: [], care_questions: [], limitations: "Photo only.")
        let unsureJSON = String(decoding: try JSONEncoder().encode(unsure), as: UTF8.self)
        let decoded = WoundContextComments.parse(unsureJSON, allowedLabels: [.abrasion, .bruise])
        precondition(decoded?.isUnableToDetermine == true)
        precondition(WoundContextComments.displayText(unsureJSON).contains("Unable to determine"))
        precondition(WoundContextComments.parse(unsureJSON.replacingOccurrences(of: "unable_to_determine", with: "possible_matches")) == nil)
        let contradictory = WoundContextComments(assessment: .unableToDetermine, candidate_labels: [.abrasion, .bruise],
            summary: "Unsure", observations: [], care_questions: [], limitations: "")
        let contradictoryJSON = String(decoding: try JSONEncoder().encode(contradictory), as: UTF8.self)
        precondition(WoundContextComments.parse(contradictoryJSON) == nil)
        precondition(WoundContextComments.parse(unsureJSON.replacingOccurrences(of: "unable_to_determine", with: "unknown_status")) == nil)
        print("PASS: structured model comments, constrained labels, malformed output, and readable sharing")
    }
}
