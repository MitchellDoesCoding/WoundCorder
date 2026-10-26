import Foundation
@main struct WoundSemanticMathTests {
    static func main() {
        let probabilities = WoundSemanticMath.probabilities(logits: [1000,1000,-1000], temperature: 1)!
        precondition(probabilities == [0.5,0.5,0])
        precondition(WoundSemanticMath.probabilities(logits: [.nan], temperature: 1) == nil)
        precondition(WoundSemanticMath.probabilities(logits: [1], temperature: 0) == nil)
        precondition(WoundSemanticMath.normalized([0,0]) == nil)
        let vector = WoundSemanticMath.normalized([Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude])!
        precondition(abs(vector.reduce(0) { $0 + $1 * $1 } - 1) < 0.00001)
        precondition(WoundSemanticMath.sigmoid(1000) == 1 && WoundSemanticMath.sigmoid(-1000) == 0)
        precondition(WoundSemanticMath.sigmoid(0) == 0.5)
        print("PASS: calibrated stable probabilities, invalid input rejection, overflow-safe embeddings, semantic sigmoid")
    }
}
