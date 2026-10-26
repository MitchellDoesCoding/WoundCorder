import Foundation
@main struct WoundWorkflowPolicyTests {
    static func main() {
        assert(WoundWorkflowPolicy.candidateCount(topProbability: 0.49, combined: false) == 2)
        assert(WoundWorkflowPolicy.candidateCount(topProbability: 0.5, combined: false) == 1)
        assert(WoundWorkflowPolicy.candidateCount(topProbability: 0.99, combined: true) == 2)
        assert(WoundWorkflowPolicy.candidateCount(topProbability: .nan, combined: false) == 2)
        assert(WoundWorkflowPolicy.bmi(heightCM: "200", weightKG: "100") == 25)
        for value in ["", "0", "-2", "nan", "inf", "abc"] {
            assert(WoundWorkflowPolicy.bmi(heightCM: value, weightKG: "80") == nil)
            assert(WoundWorkflowPolicy.bmi(heightCM: "180", weightKG: value) == nil)
        }
        assert(WoundWorkflowPolicy.bmi(heightCM: "200,0", weightKG: "100,0") == 25)
        assert(WoundWorkflowPolicy.decimalInput("70,5") == 70.5)
        assert(WoundWorkflowPolicy.decimalInput("70.5") == 70.5)
        assert(WoundWorkflowPolicy.decimalInput("1,234.5") == nil)
        assert(WoundWorkflowPolicy.decimalInput("1,2,3") == nil)
        let unknown = ComorbidityChecklist()
        assert(unknown.asDictionary().values.allSatisfy { $0 == "unknown" })
        var selected = unknown
        selected.diabetes_mellitus = .yes
        selected.obesity = .no
        assert(selected.asDictionary()["diabetes_mellitus"] == "yes")
        assert(selected.asDictionary()["obesity"] == "no")
        assert(selected.asDictionary()["DVT_or_VTE"] == "unknown")
        print("WoundWorkflowPolicyTests passed")
    }
}
