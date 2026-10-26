import Foundation
import SwiftUI
import UIKit

struct SavedPhotoCheck: Codable, Identifiable {
    let id: UUID
    var woundID: UUID? = nil
    let date: Date
    let title: String
    let patientID: UUID?
    let profile: PatientProfile
    let intake: WoundIntakeData
    let modeRaw: String
    let combined: Bool
    let comments: String
    let predictions: [RankedWoundPrediction]
    let tissues: [String: Float]
    let measurement: WoundAnalysisContext?
    let photoFilename: String

    var result: WoundSemanticResult {
        WoundSemanticResult(rankedClasses: predictions,
            semanticProbabilities: Dictionary(uniqueKeysWithValues: tissues.compactMap { key, value in
                WoundSemanticAttribute(rawValue: key).map { ($0, value) }
            }), embedding: [], isClassificationUncertain: (predictions.first?.probability ?? 0) < WoundModelContract.confidenceThreshold)
    }
    var mode: WoundAppMode { WoundAppMode(rawValue: modeRaw) ?? .publicPatient }
}

@MainActor
final class WoundPhotoCheckStore: ObservableObject {
    static let shared = WoundPhotoCheckStore()
    @Published private(set) var items: [SavedPhotoCheck] = []
    @Published private(set) var loadError: String?
    private let directory: URL
    private var expectedIndex: Data?
    private var indexURL: URL { directory.appendingPathComponent("records.json") }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WoundCorderPhotoChecks", isDirectory: true)
        reload()
    }
    func reload() {
        do {
            let data = FileManager.default.fileExists(atPath: indexURL.path) ? try Data(contentsOf: indexURL) : nil
            let decoded = try data.map { try JSONDecoder().decode([SavedPhotoCheck].self, from: $0) } ?? []
            items = decoded; expectedIndex = data; loadError = nil
        } catch { loadError = "Saved photo checks could not be read. The existing records have been kept. " + error.localizedDescription }
    }
    private func checkCurrentIndex() throws {
        guard loadError == nil else { throw WoundRecordFile<SavedPhotoCheck>.Failure.notLoaded }
        let actual = FileManager.default.fileExists(atPath: indexURL.path) ? try Data(contentsOf: indexURL) : nil
        guard actual == expectedIndex else {
            loadError = "Saved photo checks changed. Reload them before making changes."
            throw WoundRecordFile<SavedPhotoCheck>.Failure.changedElsewhere
        }
    }
    func save(title: String, patientID: UUID?, profile: PatientProfile, intake: WoundIntakeData,
              mode: WoundAppMode, combined: Bool, comments: String, result: WoundSemanticResult,
              measurement: WoundAnalysisContext?, image: UIImage, recordID: UUID = UUID(), woundID: UUID? = nil) throws {
        try checkCurrentIndex()
        if items.contains(where: { $0.id == recordID }) { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        let id = recordID, filename = UUID().uuidString + ".jpg"
        guard let data = image.scaled(maxDimension: 1600).jpegData(compressionQuality: 0.88) else { throw CocoaError(.fileWriteUnknown) }
        let imageURL = directory.appendingPathComponent(filename)
        try data.write(to: imageURL, options: [.atomic, .completeFileProtection])
        let record = SavedPhotoCheck(id: id, woundID: woundID, date: Date(), title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Photo check" : title,
            patientID: patientID, profile: profile, intake: intake, modeRaw: mode.rawValue, combined: combined,
            comments: comments, predictions: result.rankedClasses, tissues: Dictionary(uniqueKeysWithValues: result.semanticProbabilities.map { ($0.key.rawValue, $0.value) }),
            measurement: measurement, photoFilename: filename)
        let updated = [record] + items
        do {
            let data = try JSONEncoder().encode(updated)
            try data.write(to: indexURL, options: [.atomic, .completeFileProtection])
            expectedIndex = data
        }
        catch { try? FileManager.default.removeItem(at: imageURL); throw error }
        items = updated
    }
    func image(for record: SavedPhotoCheck) -> UIImage? { UIImage(contentsOfFile: directory.appendingPathComponent(record.photoFilename).path) }
    func delete(_ record: SavedPhotoCheck) throws {
        try checkCurrentIndex()
        let updated = items.filter { $0.id != record.id }
        let data = try JSONEncoder().encode(updated)
        try data.write(to: indexURL, options: [.atomic, .completeFileProtection])
        expectedIndex = data
        items = updated
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(record.photoFilename))
    }
}

struct SavedPhotoCheckView: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let record: SavedPhotoCheck
    @ObservedObject private var store = WoundPhotoCheckStore.shared
    @State private var share = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(record.profile.displayName).font(.title2.bold())
                Text(WoundL10n.text(record.date.formatted())).foregroundStyle(.secondary)
                if let image = store.image(for: record) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 300).clipShape(RoundedRectangle(cornerRadius: 12)) }
                WoundEducationResults(result: record.result, mode: record.mode, combined: record.combined, contextComments: record.comments)
                if !record.comments.isEmpty, !record.result.isClassificationUncertain { WoundContextCommentsView(raw: record.comments) }
                if let measurement = record.measurement {
                    GroupBox(WoundL10n.text("Attached measurements")) { Text(WoundL10n.text("Area: \(measurement.areaCM2, specifier: "%.2f") cm² • Volume: \(measurement.volumeCM3, specifier: "%.2f") cm³\nQuality: \(measurement.quality) • \(measurement.isPreliminary ? "Preliminary" : "Finalized")\nSource: \(measurement.volumeSource)")) }
                }
                Button(WoundL10n.text("Share with WoundCorder")) { share = true }.buttonStyle(.borderedProminent).frame(minHeight: 48)
            }.padding()
        }.navigationTitle(record.title).navigationBarTitleDisplayMode(.inline)
        .tint(record.mode.wsPrimary)
        .sheet(isPresented: $share) {
            WoundEmailShareView(photo: store.image(for: record), profile: record.profile, intake: record.intake,
                analysis: WoundEducationResults.shareText(result: record.result, mode: record.mode, combined: record.combined, contextComments: record.comments) + "\n" + (record.result.isClassificationUncertain ? "" : WoundContextComments.displayText(record.comments)) + (record.measurement.map { "\n\n" + $0.shareText } ?? ""))
        }
    }
}
