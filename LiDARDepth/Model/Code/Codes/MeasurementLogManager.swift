import Foundation
import SwiftUI

@MainActor
final class MeasurementLogManager: ObservableObject {
    @Published private(set) var items: [SavedMeasurement] = []
    @Published private(set) var storageError: String?
    private let records: WoundRecordFile<SavedMeasurement>
    var canRestorePrevious: Bool { records.hasBackup }

    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        records = WoundRecordFile(name: "measurements", legacyKey: "savedMeasurements", defaults: defaults, directory: directory)
        reload()
    }
    func reload() {
        do { items = try records.load(); storageError = nil }
        catch { storageError = error.localizedDescription }
    }
    func restorePrevious() {
        do { items = try records.restorePrevious(); storageError = nil }
        catch { storageError = error.localizedDescription }
    }
    @discardableResult private func commit(_ updated: [SavedMeasurement]) -> Bool {
        do { try records.commit(updated); items = updated; storageError = nil; return true }
        catch { storageError = error.localizedDescription; return false }
    }

    @discardableResult
    func add(
        title: String,
        perimeter: Float,
        area: Float,
        volume: Float,
        patientID: UUID? = nil,
        patientName: String? = nil,
        bodyArea: String? = nil,
        laterality: String? = nil,
        context: WoundAnalysisContext? = nil
    ) -> Bool {
        guard perimeter.isFinite, perimeter > 0, area.isFinite, area > 0, volume.isFinite, volume >= 0 else {
            storageError = "Only a valid, completed measurement can be saved."
            return false
        }
        let newItem = SavedMeasurement(
            title: title,
            perimeter: perimeter,
            area: area,
            volume: volume,
            patientID: patientID,
            patientName: patientName,
            bodyArea: bodyArea,
            laterality: laterality,
            context: context
        )
        return commit([newItem] + items)
    }

    func delete(_ indexSet: IndexSet) {
        var updated = items; updated.remove(atOffsets: indexSet); commit(updated)
    }

    func delete(item: SavedMeasurement) {
        commit(items.filter { $0.id != item.id })
    }

    func rename(item: SavedMeasurement, to newTitle: String) {
        guard let idx = items.firstIndex(of: item) else { return }
        var updated = items; updated[idx].title = newTitle; commit(updated)
    }

    func shareText(for item: SavedMeasurement) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = WoundLanguage.current.locale
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let dateString = dateFormatter.string(from: item.date)
        var lines = [
            "\(item.title) — \(dateString)",
            "Perimeter: \(String(format: "%.2f", item.perimeter)) cm",
            "Area: \(String(format: "%.2f", item.area)) cm²",
            "Volume: \(String(format: "%.2f", item.volume)) cm³"
        ]

        if let patientName = item.patientName, !patientName.isEmpty {
            lines.append("Patient: \(patientName)")
        }
        if let bodyArea = item.bodyArea {
            let side = item.laterality.map { "\($0) " } ?? ""
            lines.append("Body area: \(side)\(bodyArea)")
        }
        if let context = item.context {
            lines.append("Source: \(context.volumeSource)")
            lines.append("Quality: \(context.quality) • Preliminary: \(context.isPreliminary ? "Yes" : "No")")
        } else { lines.append("Legacy measurement: quality and source were not recorded.") }
        return lines.map { WoundL10n.text($0) }.joined(separator: "\n")
    }

    func shareCSV(for item: SavedMeasurement) -> String {
        // CSV header + single row for this item
        let header = "id,title,date,perimeter_cm,area_cm2,volume_cm3,patient_name,body_area,laterality\n"
        let iso = ISO8601DateFormatter().string(from: item.date)
        let row = [
            item.id.uuidString,
            "\"\(item.title.replacingOccurrences(of: "\"", with: "\"\""))\"",
            iso,
            String(format: "%.2f", item.perimeter),
            String(format: "%.2f", item.area),
            String(format: "%.2f", item.volume),
            "\"\((item.patientName ?? "").replacingOccurrences(of: "\"", with: "\"\""))\"",
            "\"\((item.bodyArea ?? "").replacingOccurrences(of: "\"", with: "\"\""))\"",
            item.laterality ?? ""
        ].joined(separator: ",") + "\n"
        return header + row
    }

}
