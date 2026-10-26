#if DEBUG
import SwiftUI

/// Explicit developer-only launch fixture. Never compiled into Release builds.
struct WoundReviewHarness: View {
    @State private var status = "Running checks"
    private let result = WoundSemanticResult(rankedClasses: [.init(label: .abrasion, probability: 0.6), .init(label: .bruise, probability: 0.3)], semanticProbabilities: [.granulation: 0.7, .backgroundNonSkin: 0.01], embedding: [], isClassificationUncertain: false)
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(status).font(.caption)
                    WoundEducationResults(result: result, mode: .publicPatient, combined: false)
                }.padding()
            }.navigationTitle("Photo check review")
        }.task { verify(); await verifyModel() }
    }
    @MainActor private func verifyModel() async {
        struct Reference: Decodable { let woundType: String; let assetName: String }
        do {
            let url = Bundle.main.url(forResource: "wound-reference-photos", withExtension: "json", subdirectory: "WoundReferenceExamples")!
            let references = try JSONDecoder().decode([Reference].self, from: Data(contentsOf: url))
            let service = WoundSemanticService()
            for type in WoundClass.allCases {
                let reference = references.first { $0.woundType == type.rawValue }!
                let file = Bundle.main.url(forResource: reference.assetName, withExtension: "jpg", subdirectory: "WoundReferenceExamples")!
                let prediction = try await service.predict(image: UIImage(contentsOfFile: file.path)!)
                precondition(prediction.rankedClasses.count == 9 && prediction.semanticProbabilities.count == 8)
                precondition(abs(prediction.rankedClasses.reduce(0) { $0 + $1.probability } - 1) < 0.0001)
                precondition(prediction.embedding.count == 1280 && abs(prediction.embedding.reduce(0) { $0 + $1 * $1 } - 1) < 0.0001)
            }
            status += "\nPASS: production CNN pipeline on nine bundled images (output validity, not diagnostic accuracy)"
            print("PASS: production CNN pipeline on nine bundled images")
        } catch { status = "FAIL: " + error.localizedDescription; assertionFailure(status) }
    }
    @MainActor private func verify() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try WoundReviewChecks.run(directory: folder)
            let profile = PatientProfile(name: "Review Fixture", height: "170", weight: "70", age: "45")
            var intake = WoundIntakeData(); intake.comorbidities.diabetes_mellitus = .yes
            let photo = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in UIColor.gray.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 32)) }
            let store = WoundPhotoCheckStore(directory: folder)
            try store.save(title: "Review", patientID: nil, profile: profile, intake: intake, mode: .publicPatient, combined: false, comments: "Saved comment", result: result, measurement: nil, image: photo)
            let recordID = UUID(), woundID = UUID()
            for _ in 0..<2 {
                try store.save(title: "Follow-up", patientID: nil, profile: profile, intake: intake,
                    mode: .publicPatient, combined: false, comments: "Saved comment", result: result,
                    measurement: nil, image: photo, recordID: recordID, woundID: woundID)
            }
            precondition(store.items.count == 2 && store.items.first?.woundID == woundID)
            try store.delete(store.items.first!)
            let reloaded = WoundPhotoCheckStore(directory: folder)
            precondition(reloaded.items.count == 1)
            let record = reloaded.items[0]
            precondition(record.comments == "Saved comment" && record.measurement == nil)
            precondition(record.profile == profile && record.intake == intake)
            precondition(record.predictions == result.rankedClasses && reloaded.image(for: record) != nil)
            let uncertain = WoundSemanticResult(rankedClasses: result.rankedClasses,
                semanticProbabilities: result.semanticProbabilities, embedding: [], isClassificationUncertain: true)
            precondition(uncertain.displayedPredictions(combined: true).isEmpty)
            precondition(WoundEducationResults.shareText(result: uncertain, mode: .publicPatient, combined: true).contains("Unable to determine"))
            let unsure = WoundContextComments(assessment: .unableToDetermine, candidate_labels: [],
                summary: "Insufficient evidence", observations: [], care_questions: [], limitations: "")
            let unsureJSON = String(decoding: try JSONEncoder().encode(unsure), as: UTF8.self)
            let withheld = WoundEducationResults.shareText(result: result, mode: .publicPatient, combined: true, contextComments: unsureJSON)
            precondition(withheld.contains("Unable to determine") && !withheld.contains("photo match"))
            precondition(result.displayedPredictions(combined: false).count == 1)
            precondition(result.displayedPredictions(combined: true).count == 2)
            for level in WoundShareLevel.allCases {
                let body = level.body(profile: profile, intake: intake, analysis: "Unique result")
                precondition(!body.contains("Review Fixture"))
                precondition(body.contains("diabetes mellitus: yes") == (level.rawValue >= 2))
                precondition(body.contains("Unique result") == (level == .analysis))
            }
            precondition(WoundEducationLibrary.wounds.count == 9)
            precondition(Bundle.main.url(forResource: "wound-reference-photos", withExtension: "json", subdirectory: "WoundReferenceExamples") != nil)
            try reloaded.delete(record)
            precondition(WoundPhotoCheckStore(directory: folder).items.isEmpty)
            status = "PASS: storage migration/recovery, image orientation, save/reload/delete, share privacy, result counts, education resources"
            print(status)
        } catch { status = "FAIL: " + error.localizedDescription; assertionFailure(status) }
    }
}
#endif
