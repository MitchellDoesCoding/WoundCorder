import Foundation
import SwiftUI

@MainActor
final class MeasurementLogManager: ObservableObject {
    @AppStorage("savedMeasurements") private var storedJSON: String = ""

    @Published private(set) var items: [SavedMeasurement] = [] {
        didSet { persist() }
    }

    init() {
        load()
    }

    func add(
        title: String,
        perimeter: Float,
        area: Float,
        volume: Float,
        severity: Int? = nil,
        patientName: String? = nil,
        bodyArea: String? = nil,
        laterality: String? = nil
    ) {
        let newItem = SavedMeasurement(
            title: title,
            perimeter: perimeter,
            area: area,
            volume: volume,
            severity: severity,
            patientName: patientName,
            bodyArea: bodyArea,
            laterality: laterality
        )
        items.insert(newItem, at: 0)
    }

    func delete(_ indexSet: IndexSet) {
        items.remove(atOffsets: indexSet)
    }

    func delete(item: SavedMeasurement) {
        if let idx = items.firstIndex(of: item) { items.remove(at: idx) }
    }

    func rename(item: SavedMeasurement, to newTitle: String) {
        guard let idx = items.firstIndex(of: item) else { return }
        items[idx].title = newTitle
    }

    func shareText(for item: SavedMeasurement) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let dateString = dateFormatter.string(from: item.date)
        var lines = [
            "\(item.title) — \(dateString)",
            "Perimeter: \(String(format: "%.2f", item.perimeter)) cm",
            "Area: \(String(format: "%.2f", item.area)) cm²",
            "Volume: \(String(format: "%.2f", item.volume)) cm³"
        ]
        if let severity = item.severity {
            lines.append("Severity: \(severity)/20")
        }
        if let patientName = item.patientName, !patientName.isEmpty {
            lines.append("Patient: \(patientName)")
        }
        if let bodyArea = item.bodyArea {
            let side = item.laterality.map { "\($0) " } ?? ""
            lines.append("Body area: \(side)\(bodyArea)")
        }
        return lines.joined(separator: "\n")
    }

    func shareCSV(for item: SavedMeasurement) -> String {
        // CSV header + single row for this item
        let header = "id,title,date,perimeter_cm,area_cm2,volume_cm3,severity,patient_name,body_area,laterality\n"
        let iso = ISO8601DateFormatter().string(from: item.date)
        let row = [
            item.id.uuidString,
            "\"\(item.title.replacingOccurrences(of: "\"", with: "\"\""))\"",
            iso,
            String(format: "%.2f", item.perimeter),
            String(format: "%.2f", item.area),
            String(format: "%.2f", item.volume),
            item.severity.map(String.init) ?? "",
            "\"\((item.patientName ?? "").replacingOccurrences(of: "\"", with: "\"\""))\"",
            "\"\((item.bodyArea ?? "").replacingOccurrences(of: "\"", with: "\"\""))\"",
            item.laterality ?? ""
        ].joined(separator: ",") + "\n"
        return header + row
    }

    // MARK: - Persistence

    private func load() {
        guard !storedJSON.isEmpty, let data = storedJSON.data(using: .utf8) else {
            items = []
            return
        }
        do {
            items = try JSONDecoder().decode([SavedMeasurement].self, from: data)
        } catch {
            items = []
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(items)
            storedJSON = String(data: data, encoding: .utf8) ?? ""
        } catch {
            // If encoding fails, keep previous storage
        }
    }
}
