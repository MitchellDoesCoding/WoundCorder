import SwiftUI

struct MeasurementLogListView: View {
    @EnvironmentObject var logManager: MeasurementLogManager

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Measurement Logs")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        CloseButton()
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        let items = logManager.items
        if items.isEmpty {
            ContentUnavailableView("No Logs", systemImage: "doc.text.magnifyingglass", description: Text("Logs you record will appear here."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
        } else {
            List {
                ForEach(items) { item in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.patientName?.isEmpty == false ? item.patientName! : item.title)
                                .font(.headline)
                            Text(summary(for: item))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 6) {
                            Text("\(item.severity ?? WoundSeverityScorer.score(area: item.area, volume: item.volume))/20")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle((item.severity ?? 1) >= 15 ? .red : .orange)

                            Menu {
                                ShareLink(item: logManager.shareText(for: item)) {
                                    Label("Share Text", systemImage: "square.and.arrow.up")
                                }
                                ShareLink(item: logManager.shareCSV(for: item)) {
                                    Label("Share CSV", systemImage: "tablecells")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
                .onDelete(perform: logManager.delete)
            }
        }
    }

    // Helper to create a compact description of a SavedMeasurement.
    private func summary(for item: SavedMeasurement) -> String {
        let side = item.laterality.map { "\($0) " } ?? ""
        let body = item.bodyArea ?? "Body area not set"
        return "\(side)\(body) • A \(String(format: "%.2f", item.area)) cm² • V \(String(format: "%.2f", item.volume)) cm³"
    }
}

private struct CloseButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button("Done") { dismiss() }
    }
}

#Preview {
    let manager = MeasurementLogManager()
    // Add a sample entry for preview
    manager.add(title: "Sample", perimeter: 12.34, area: 56.78, volume: 9.01)

    return MeasurementLogListView()
        .environmentObject(manager)
}
