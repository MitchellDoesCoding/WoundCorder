import SwiftUI
import Charts

struct WoundCheckInHistoryView: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    @ObservedObject private var store = WoundPhotoCheckStore.shared
    @State private var selectedWound: UUID?
    @State private var metric = "Area"
    private var wounds: [SavedPhotoCheck] {
        var seen = Set<UUID>()
        return store.items.filter { seen.insert($0.woundID ?? $0.id).inserted }
    }
    private var records: [SavedPhotoCheck] {
        store.items.filter { selectedWound == nil || ($0.woundID ?? $0.id) == selectedWound }
            .sorted { $0.date < $1.date }
    }
    private var measured: [SavedPhotoCheck] {
        records.filter { $0.measurement != nil }
    }
    private var days: [(date: Date, count: Int)] {
        Dictionary(grouping: records, by: { Calendar.current.startOfDay(for: $0.date) })
            .map { (date: $0.key, count: $0.value.count) }.sorted { $0.date < $1.date }
    }
    var body: some View {
        List {
            Section {
                Picker(WoundL10n.text("Wound"), selection: $selectedWound) {
                    Text(WoundL10n.text("All check-ins")).tag(nil as UUID?)
                    ForEach(wounds) { record in
                        Text("\(record.profile.displayName) · \(record.intake.laterality.rawValue) \(record.intake.bodyArea.rawValue) · \(record.date.woundFormatted(date: .abbreviated, time: .omitted))")
                            .tag(Optional(record.woundID ?? record.id))
                    }
                }
                if selectedWound != nil {
                    Picker(WoundL10n.text("Measurement"), selection: $metric) {
                        Text(WoundL10n.text("Area")).tag("Area")
                        Text(WoundL10n.text("Volume")).tag("Volume")
                    }.pickerStyle(.segmented)
                    if !measured.isEmpty {
                        Chart(measured) { record in
                            BarMark(x: .value(WoundL10n.text("Check-in"), record.date),
                                    y: .value(WoundL10n.text(metric), metric == "Area" ? record.measurement!.areaCM2 : record.measurement!.volumeCM3),
                                    width: .fixed(12))
                        }
                        .chartYAxisLabel(metric == "Area" ? "cm²" : "cm³")
                        .frame(height: 200)
                        .accessibilityLabel(WoundL10n.text("Dated \(metric.lowercased()) measurements for this wound"))
                    } else {
                        Text(WoundL10n.text("No measurements attached yet. Photo-only check-ins are listed below."))
                    }
                    Text(WoundL10n.text("Changes in measurements alone do not confirm healing. Compare photos, symptoms, and capture quality."))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Chart(days, id: \.date) { day in
                        BarMark(x: .value(WoundL10n.text("Date"), day.date, unit: .day), y: .value(WoundL10n.text("Check-ins"), day.count))
                    }.frame(height: 200).chartYAxisLabel(WoundL10n.text("Check-ins"))
                    Text(WoundL10n.text("All check-ins by date. Select one wound to compare its area or volume."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(WoundL10n.text("Dated check-ins")) {
                ForEach(records.reversed()) { record in
                    NavigationLink {
                        SavedPhotoCheckView(record: record)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.title).font(.headline)
                            Text(WoundL10n.text(record.date.woundFormatted(date: .abbreviated, time: .shortened)))
                            Text(WoundL10n.text("\(record.intake.laterality.rawValue) \(record.intake.bodyArea.rawValue)"))
                            if let m = record.measurement {
                                Text(WoundL10n.text("Area \(m.areaCM2, specifier: "%.2f") cm² · Volume \(m.volumeCM3, specifier: "%.2f") cm³"))
                                Text(WoundL10n.text("\(m.quality) · \(m.isPreliminary ? "Preliminary" : "Finalized")")).font(.caption)
                            } else { Text(WoundL10n.text("Photo only")).font(.caption) }
                        }
                    }
                }
            }
        }
        .navigationTitle(WoundL10n.text("Wound progress"))
        .overlay { if store.items.isEmpty { ContentUnavailableView(WoundL10n.text("No check-ins yet"), systemImage: "chart.bar", description: Text(WoundL10n.text("Saved photo checks and attached measurements will appear here."))) } }
    }
}
