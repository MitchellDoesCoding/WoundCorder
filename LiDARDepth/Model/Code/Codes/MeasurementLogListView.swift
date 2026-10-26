import SwiftUI

struct MeasurementLogListView: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    @EnvironmentObject var logManager: MeasurementLogManager
    @ObservedObject private var photoChecks = WoundPhotoCheckStore.shared
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(WoundL10n.text("Saved records"))
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
        if items.isEmpty && photoChecks.items.isEmpty && photoChecks.loadError == nil && logManager.storageError == nil {
            ContentUnavailableView(WoundL10n.text("No Logs"), systemImage: "doc.text.magnifyingglass", description: Text(WoundL10n.text("Logs you record will appear here.")))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
        } else {
            List {
                NavigationLink(WoundL10n.text("Wound progress"), destination: WoundCheckInHistoryView())
                if let error = logManager.storageError { WoundStorageRecoveryView(message: error, canRestore: logManager.canRestorePrevious, reload: logManager.reload, restore: logManager.restorePrevious) }
                if let error = photoChecks.loadError { WoundStorageRecoveryView(message: error, canRestore: false, reload: photoChecks.reload, restore: {}) }
                if let deleteError { Text(WoundL10n.text(deleteError)).foregroundStyle(.red) }
                Section(WoundL10n.text("Photo checks")) {
                    ForEach(photoChecks.items) { record in
                        NavigationLink { SavedPhotoCheckView(record: record) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(record.profile.displayName).font(.headline)
                                Text(record.title + " • " + record.date.woundFormatted(date: .abbreviated, time: .shortened)).font(.subheadline)
                            }
                        }.swipeActions { Button(WoundL10n.text("Delete"), role: .destructive) { do { try photoChecks.delete(record) } catch { deleteError = error.localizedDescription } } }
                    }
                }
                Section {
                    Text(WoundL10n.text("Older measurements without a patient ID remain here. They are not matched to a person by name.")).font(.footnote)
                }
                Section(WoundL10n.text("Measurements")) {
                ForEach(items) { item in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.patientName?.isEmpty == false ? item.patientName! : item.title)
                                .font(.headline)
                            Text(WoundL10n.text(item.context.map { "\($0.quality) quality • \($0.isPreliminary ? "Preliminary" : "Finalized")" } ?? "Legacy record • quality not recorded")).font(.caption).foregroundStyle(.secondary)
                            Text(WoundL10n.text(summary(for: item)))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 6) {
                            Menu {
                                ShareLink(item: logManager.shareText(for: item)) {
                                    Label(WoundL10n.text("Share Text"), systemImage: "square.and.arrow.up")
                                }
                                ShareLink(item: logManager.shareCSV(for: item)) {
                                    Label(WoundL10n.text("Share CSV"), systemImage: "tablecells")
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
    }

    // Helper to create a compact description of a SavedMeasurement.
    private func summary(for item: SavedMeasurement) -> String {
        let side = item.laterality.map { "\($0) " } ?? ""
        let body = item.bodyArea ?? "Body area not set"
        return "\(side)\(body) • A \(String(format: "%.2f", item.area)) cm² • V \(String(format: "%.2f", item.volume)) cm³"
    }
}

private struct CloseButton: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button(WoundL10n.text("Done")) { dismiss() }
    }
}

#Preview {
    let manager = MeasurementLogManager()
    // Add a sample entry for preview
    manager.add(title: "Sample", perimeter: 12.34, area: 56.78, volume: 9.01)

    return MeasurementLogListView()
        .environmentObject(manager)
}
