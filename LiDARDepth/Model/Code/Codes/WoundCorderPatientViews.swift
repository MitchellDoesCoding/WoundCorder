import Charts
import Foundation
import SwiftUI

// MARK: - Patient list

/// Patient browsing for the professional workflow. Measurement history remains backed by
/// `SavedMeasurement`; these views only organize and present the values produced by capture.
struct WoundCorderPatientsView: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    @ObservedObject private var store: WoundCorderPatientStore

    let measurements: [SavedMeasurement]
    let onCapture: (WoundCorderPatient) -> Void

    @State private var searchText = ""
    @State private var isPresentingNewPatient = false
    @State private var pendingDelete: WoundCorderPatient?

    init(
        store: WoundCorderPatientStore,
        measurements: [SavedMeasurement],
        onCapture: @escaping (WoundCorderPatient) -> Void
    ) {
        _store = ObservedObject(wrappedValue: store)
        self.measurements = measurements
        self.onCapture = onCapture
    }

    private var filteredPatients: [WoundCorderPatient] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.patients }

        return store.patients.filter { patient in
            patient.displayName.localizedCaseInsensitiveContains(query)
                || patient.mrnOrPID.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
            if let error = store.storageError { WoundStorageRecoveryView(message: error, canRestore: store.canRestorePrevious, reload: store.reload, restore: store.restorePrevious) }
            ForEach(filteredPatients) { patient in
                NavigationLink {
                    WSPatientDetailView(
                        patient: patient,
                        measurements: WSMeasurementGrouping.measurements(
                            for: patient,
                            from: measurements
                        ),
                        onCapture: { onCapture(patient) }
                    )
                } label: {
                    WSPatientRow(
                        patient: patient,
                        measurements: WSMeasurementGrouping.measurements(
                            for: patient,
                            from: measurements
                        )
                    )
                    .padding(.vertical, WSTheme.Space.xxs)
                }
                .listRowSeparator(.hidden)
                .listRowInsets(
                    EdgeInsets(
                        top: WSTheme.Space.xxs,
                        leading: WSTheme.Space.md,
                        bottom: WSTheme.Space.xxs,
                        trailing: WSTheme.Space.md
                    )
                )
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        pendingDelete = patient
                    } label: {
                        Label(WoundL10n.text("Delete"), systemImage: "trash")
                    }
                    .tint(.red)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(WSTheme.Palette.paper.ignoresSafeArea())
        .overlay {
            if store.patients.isEmpty && store.storageError == nil {
                WSPatientListEmptyState {
                    isPresentingNewPatient = true
                }
            } else if filteredPatients.isEmpty && store.storageError == nil {
                WSNoSearchResultsState(query: searchText) {
                    searchText = ""
                }
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: WoundL10n.text("Name or MRN / patient ID")
        )
        .navigationTitle(WoundL10n.text("Patients"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingNewPatient = true
                } label: {
                    Label(WoundL10n.text("New patient"), systemImage: "person.badge.plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingNewPatient) {
            WSNewPatientSheet(store: store)
        }
        .confirmationDialog(WoundL10n.text(
            "Delete patient?"),
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(WoundL10n.text("Delete"), role: .destructive) {
                if let pendingDelete {
                    store.delete(pendingDelete)
                }
                pendingDelete = nil
            }
            Button(WoundL10n.text("Cancel"), role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text(WoundL10n.text("The patient profile will be removed. Existing measurement logs are not changed."))
        }
    }
}

private struct WSPatientRow: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let patient: WoundCorderPatient
    let measurements: [SavedMeasurement]

    private var woundCount: Int {
        WSMeasurementGrouping.wounds(from: measurements).count
    }

    private var latest: SavedMeasurement? {
        measurements.max { $0.date < $1.date }
    }

    var body: some View {
        HStack(spacing: WSTheme.Space.md) {
            WSAvatar(
                seed: patient.id.uuidString,
                initials: patient.initials,
                size: 48
            )

            VStack(alignment: .leading, spacing: WSTheme.Space.xxs) {
                Text(patient.displayName)
                    .font(.wsBodyBold)
                    .foregroundStyle(WSTheme.Palette.ink)
                    .lineLimit(1)

                if !patient.mrnOrPID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(WoundL10n.text("MRN / ID \(patient.mrnOrPID)"))
                        .font(.wsCaption)
                        .foregroundStyle(WSTheme.Palette.inkSecondary)
                        .lineLimit(1)
                }

                Text(WoundL10n.text(historySummary))
                    .font(.wsCaption)
                    .foregroundStyle(WSTheme.Palette.inkSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: WSTheme.Space.xs)


        }
        .padding(WSTheme.Space.md)
        .wsCard(padding: 0)
    }

    private var historySummary: String {
        guard let latest else { return "No saved encounters" }
        let wounds = "\(woundCount) wound\(woundCount == 1 ? "" : "s")"
        return "\(wounds) · \(latest.date.formatted(.relative(presentation: .named)))"
    }
}

private struct WSPatientListEmptyState: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let onAdd: () -> Void

    var body: some View {
        WSEmptyState(
            title: "No patients yet",
            message: "Add a patient to keep future wound captures and measurement history organized.",
            systemImage: "person.2",
            buttonTitle: "Add patient",
            buttonImage: "person.badge.plus",
            action: onAdd
        )
    }
}

private struct WSNoSearchResultsState: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let query: String
    let onClear: () -> Void

    var body: some View {
        WSEmptyState(
            title: "No matching patients",
            message: "No name or MRN / patient ID matches “\(query)”.",
            systemImage: "magnifyingglass",
            buttonTitle: "Clear search",
            buttonImage: "xmark.circle",
            action: onClear
        )
    }
}

// MARK: - New patient

private struct WSNewPatientSheet: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    @ObservedObject private var store: WoundCorderPatientStore
    @Environment(\.dismiss) private var dismiss

    @State private var profile = PatientProfile()

    init(store: WoundCorderPatientStore) {
        _store = ObservedObject(wrappedValue: store)
    }

    private var canSave: Bool {
        !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && profile.validationMessage == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error = store.storageError { WoundStorageRecoveryView(message: error, canRestore: store.canRestorePrevious, reload: store.reload, restore: store.restorePrevious) }
                Section(WoundL10n.text("Patient")) {
                    TextField(WoundL10n.text("Display name"), text: $profile.name)
                        .textInputAutocapitalization(.words)
                        .textContentType(.name)

                    TextField(WoundL10n.text("MRN or patient ID (optional)"), text: $profile.mrnOrPID)
                        .textInputAutocapitalization(.never)
                }

                Section(WoundL10n.text("Profile (optional)")) {
                    if let message = profile.validationMessage { Text(WoundL10n.text(message)).foregroundStyle(.red) }
                    Picker(WoundL10n.text("Gender"), selection: $profile.gender) {
                        ForEach(PatientGender.allCases) { gender in
                            Text(WoundL10n.text(WSProfileFormatting.genderName(gender.rawValue)))
                                .tag(gender)
                        }
                    }

                    HStack {
                        Text(WoundL10n.text("Age"))
                        Spacer()
                        TextField(WoundL10n.text("years"), text: $profile.age)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 110)
                    }

                    HStack {
                        Text(WoundL10n.text("Height (cm)"))
                        Spacer()
                        TextField(WoundL10n.text("cm"), text: $profile.height)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 110)
                    }

                    HStack {
                        Text(WoundL10n.text("Weight (kg)"))
                        Spacer()
                        TextField(WoundL10n.text("kg"), text: $profile.weight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 110)
                    }
                }

                Section {
                    Label(WoundL10n.text(
                        "Profile details organize saved scans; they do not change LiDAR measurement calculations."),
                        systemImage: "checkmark.shield"
                    )
                    .font(.wsCaption)
                    .foregroundStyle(WSTheme.Palette.inkSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(WSTheme.Palette.paper.ignoresSafeArea())
            .navigationTitle(WoundL10n.text("New patient"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(WoundL10n.text("Cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(WoundL10n.text("Save")) {
                        profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        profile.mrnOrPID = profile.mrnOrPID.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard store.add(from: profile) != nil else { return }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
    }
}

// MARK: - Patient detail

struct WSPatientDetailView: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    @ObservedObject private var photoChecks = WoundPhotoCheckStore.shared
    let patient: WoundCorderPatient
    let measurements: [SavedMeasurement]
    let onCapture: () -> Void

    private var wounds: [WSMeasurementWound] {
        WSMeasurementGrouping.wounds(from: measurements)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: WSTheme.Space.lg) {
                ForEach(photoChecks.items.filter { $0.patientID == patient.id }) { record in
                    NavigationLink { SavedPhotoCheckView(record: record) } label: {
                        Label(WoundL10n.text("Photo check • " + record.date.woundFormatted(date: .abbreviated, time: .shortened)), systemImage: "photo").frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).wsCard()
                    }
                }
                patientHeader
                if !WSProfileFormatting.summary(for: patient).isEmpty {
                    profileCard
                }
                woundsSection
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(WSTheme.Space.lg)
        }
        .background(WSTheme.Palette.paper.ignoresSafeArea())
        .navigationTitle(patient.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onCapture) {
                    Label(WoundL10n.text("New capture"), systemImage: "plus.viewfinder")
                }
            }
        }
    }

    private var patientHeader: some View {
        HStack(alignment: .top, spacing: WSTheme.Space.md) {
            WSAvatar(
                seed: patient.id.uuidString,
                initials: patient.initials,
                size: 64
            )

            VStack(alignment: .leading, spacing: WSTheme.Space.xxs) {
                Text(patient.displayName)
                    .font(.wsTitle)
                    .foregroundStyle(WSTheme.Palette.ink)

                if !patient.mrnOrPID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(WoundL10n.text("MRN / ID \(patient.mrnOrPID)"))
                        .font(.wsCaption)
                        .foregroundStyle(WSTheme.Palette.inkSecondary)
                }

                Text(WoundL10n.text("\(wounds.count) wound\(wounds.count == 1 ? "" : "s") · \(measurements.count) encounter\(measurements.count == 1 ? "" : "s")"))
                    .font(.wsCaption)
                    .foregroundStyle(WSTheme.Palette.inkSecondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profileCard: some View {
        WSPatientSectionCard(title: "Profile") {
            Text(WoundL10n.text(WSProfileFormatting.summary(for: patient).joined(separator: " · ")))
                .font(.wsBody)
                .foregroundStyle(WSTheme.Palette.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var woundsSection: some View {
        VStack(alignment: .leading, spacing: WSTheme.Space.sm) {
            WSSectionLabel(title: "Wounds", count: wounds.count)

            if wounds.isEmpty {
                VStack(spacing: WSTheme.Space.md) {
                    Image(systemName: "bandage")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(WSTheme.Palette.professionalPrimary)
                        .frame(width: 56, height: 56)
                        .background(
                            WSTheme.Palette.professionalSoft,
                            in: RoundedRectangle(
                                cornerRadius: WSTheme.Radius.md,
                                style: .continuous
                            )
                        )

                    VStack(spacing: WSTheme.Space.xxs) {
                        Text(WoundL10n.text("No wounds tracked yet"))
                            .font(.wsHeadline)
                            .foregroundStyle(WSTheme.Palette.ink)
                        Text(WoundL10n.text("Start a capture to create this patient’s first wound encounter."))
                            .font(.wsCaption)
                            .foregroundStyle(WSTheme.Palette.inkSecondary)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: onCapture) {
                        Label(WoundL10n.text("Start capture"), systemImage: "viewfinder")
                            .font(.wsBodyBold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, WSTheme.Space.sm)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WSTheme.Palette.professionalPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(WSTheme.Space.lg)
                .wsCard(padding: 0)
            } else {
                ForEach(wounds) { wound in
                    NavigationLink {
                        WSWoundDetailView(wound: wound)
                    } label: {
                        WSWoundRow(wound: wound)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Wound detail

private struct WSWoundRow: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let wound: WSMeasurementWound

    private var latest: SavedMeasurement? { wound.encounters.first }

    var body: some View {
        HStack(spacing: WSTheme.Space.md) {
            Image(systemName: wound.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(WSTheme.Palette.inkSecondary)
                .frame(width: 44, height: 44)
                .background(
                    WSTheme.Palette.inkSecondary.opacity(0.13),
                    in: RoundedRectangle(cornerRadius: WSTheme.Radius.md, style: .continuous)
                )

            VStack(alignment: .leading, spacing: WSTheme.Space.xxs) {
                Text(WoundL10n.text(wound.displayName))
                    .font(.wsBodyBold)
                    .foregroundStyle(WSTheme.Palette.ink)
                    .lineLimit(1)

                if let latest {
                    Text(WoundL10n.text("\(latest.area, specifier: "%.1f") cm² · \(wound.encounters.count) encounter\(wound.encounters.count == 1 ? "" : "s")"))
                        .font(.wsCaption)
                        .foregroundStyle(WSTheme.Palette.inkSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: WSTheme.Space.xs)

            if wound.encounters.count >= 2 {
                WSAreaSparkline(encounters: wound.encounters, tint: WSTheme.Palette.inkSecondary)
                    .frame(width: 58, height: 30)
            }



            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WSTheme.Palette.inkTertiary)
        }
        .padding(WSTheme.Space.md)
        .wsCard(padding: 0)
    }


}

private struct WSAreaSparkline: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let encounters: [SavedMeasurement]
    let tint: Color

    private var series: [SavedMeasurement] {
        encounters.sorted { $0.date < $1.date }
    }

    var body: some View {
        Chart(series) { encounter in
            LineMark(
                x: .value(WoundL10n.text("Date"), encounter.date),
                y: .value(WoundL10n.text("Area"), Double(encounter.area))
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(tint)
            .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityLabel(WoundL10n.text("Wound area trend"))
    }
}

private struct WSWoundDetailView: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let wound: WSMeasurementWound

    @State private var trendMetric: WSTrendMetric = .area

    private var encountersNewestFirst: [SavedMeasurement] {
        wound.encounters.sorted { $0.date > $1.date }
    }

    private var encountersOldestFirst: [SavedMeasurement] {
        wound.encounters.sorted { $0.date < $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: WSTheme.Space.lg) {
                woundHeader

                trendCard
                encounterSection
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(WSTheme.Space.lg)
        }
        .background(WSTheme.Palette.paper.ignoresSafeArea())
        .navigationTitle(WoundL10n.text(wound.displayName))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var woundHeader: some View {
        HStack(spacing: WSTheme.Space.md) {
            Image(systemName: wound.systemImage)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(WSTheme.Palette.professionalPrimary)
                .frame(width: 44, height: 44)
                .background(
                    WSTheme.Palette.professionalSoft,
                    in: RoundedRectangle(cornerRadius: WSTheme.Radius.md, style: .continuous)
                )

            VStack(alignment: .leading, spacing: WSTheme.Space.xxs) {
                Text(WoundL10n.text(wound.displayName))
                    .font(.wsHeadline)
                    .foregroundStyle(WSTheme.Palette.ink)
                Text(WoundL10n.text("\(wound.encounters.count) encounter\(wound.encounters.count == 1 ? "" : "s")"))
                    .font(.wsCaption)
                    .foregroundStyle(WSTheme.Palette.inkSecondary)
            }

            Spacer()

            WSTrajectoryChip(encounters: encountersOldestFirst)
        }
        .padding(WSTheme.Space.md)
        .wsCard(padding: 0)
    }

    private var trendCard: some View {
        WSPatientSectionCard(title: "Trend") {
            VStack(alignment: .leading, spacing: WSTheme.Space.sm) {
                Picker(WoundL10n.text("Metric"), selection: $trendMetric) {
                    ForEach(WSTrendMetric.allCases) { metric in
                        Text(WoundL10n.text(metric.rawValue)).tag(metric)
                    }
                }
                .pickerStyle(.segmented)

                if encountersOldestFirst.count >= 2 {
                    Chart(encountersOldestFirst) { encounter in
                        AreaMark(
                            x: .value(WoundL10n.text("Date"), encounter.date),
                            y: .value(
                                trendMetric.rawValue,
                                trendMetric.value(for: encounter)
                            )
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    WSTheme.Palette.professionalPrimary.opacity(0.28),
                                    WSTheme.Palette.professionalPrimary.opacity(0.02)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value(WoundL10n.text("Date"), encounter.date),
                            y: .value(
                                trendMetric.rawValue,
                                trendMetric.value(for: encounter)
                            )
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(WSTheme.Palette.professionalPrimary)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))

                        PointMark(
                            x: .value(WoundL10n.text("Date"), encounter.date),
                            y: .value(
                                trendMetric.rawValue,
                                trendMetric.value(for: encounter)
                            )
                        )
                        .foregroundStyle(WSTheme.Palette.professionalPrimary)
                        .symbolSize(54)
                    }
                    .frame(height: 190)
                    .chartYAxisLabel(trendMetric.unit)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine()
                                .foregroundStyle(WSTheme.Palette.hairline)
                            AxisTick()
                                .foregroundStyle(WSTheme.Palette.hairline)
                            AxisValueLabel()
                                .font(.wsMicro)
                                .foregroundStyle(WSTheme.Palette.inkSecondary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine()
                                .foregroundStyle(WSTheme.Palette.hairline)
                            AxisValueLabel {
                                if let numericValue = value.as(Double.self) {
                                    Text(numericValue, format: .number.precision(.fractionLength(0...1)))
                                        .font(.wsMicro)
                                        .foregroundStyle(WSTheme.Palette.inkSecondary)
                                }
                            }
                        }
                    }
                    .accessibilityLabel(WoundL10n.text("\(trendMetric.rawValue) trend in \(trendMetric.unit)"))
                } else {
                    VStack(spacing: WSTheme.Space.sm) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 25, weight: .medium))
                            .foregroundStyle(WSTheme.Palette.inkTertiary)
                        Text(WoundL10n.text("Capture at least two encounters to see a trend."))
                            .font(.wsCaption)
                            .foregroundStyle(WSTheme.Palette.inkSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, WSTheme.Space.lg)
                }
            }
        }
    }

    private var encounterSection: some View {
        VStack(alignment: .leading, spacing: WSTheme.Space.sm) {
            WSSectionLabel(title: "Encounters", count: encountersNewestFirst.count)

            if encountersNewestFirst.isEmpty {
                Text(WoundL10n.text("No saved encounters are available for this wound."))
                    .font(.wsCaption)
                    .foregroundStyle(WSTheme.Palette.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(WSTheme.Space.lg)
                    .wsCard(padding: 0)
            } else {
                ForEach(encountersNewestFirst) { encounter in
                    NavigationLink {
                        WSEncounterDetailView(
                            encounter: encounter,
                            woundName: wound.displayName
                        )
                    } label: {
                        WSEncounterCard(encounter: encounter)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private enum WSTrendMetric: String, CaseIterable, Identifiable {
    case area = "Area"
    case volume = "Volume"
    case depth = "Depth"

    var id: String { rawValue }

    var unit: String {
        switch self {
        case .area: return "cm²"
        case .volume: return "cm³"
        case .depth: return "cm"
        }
    }

    func value(for measurement: SavedMeasurement) -> Double {
        switch self {
        case .area:
            return Double(measurement.area)
        case .volume:
            return Double(measurement.volume)
        case .depth:
            return Double(
                WoundMeasurementMath.depthCM(
                    area: measurement.area,
                    volume: measurement.volume
                )
            )
        }
    }
}

private struct WSTrajectoryChip: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let encounters: [SavedMeasurement]

    private var trajectory: WSTrajectory {
        guard
            let first = encounters.first,
            let last = encounters.last,
            encounters.count >= 2,
            first.area > 0
        else {
            return .insufficient
        }

        let change = (last.area - first.area) / first.area
        if change <= -0.05 { return .decreasing }
        if change >= 0.05 { return .increasing }
        return .stable
    }

    var body: some View {
        Label(WoundL10n.text(trajectory.label), systemImage: trajectory.systemImage)
            .font(.wsCaption.weight(.semibold))
            .foregroundStyle(trajectory.color)
            .padding(.horizontal, WSTheme.Space.sm)
            .padding(.vertical, 6)
            .background(trajectory.color.opacity(0.12), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(trajectory.color.opacity(0.24), lineWidth: 0.5)
            }
    }
}

private enum WSTrajectory {
    case decreasing
    case stable
    case increasing
    case insufficient

    var label: String {
        switch self {
        case .decreasing: return "Area decreasing"
        case .stable: return "Area stable"
        case .increasing: return "Area increasing"
        case .insufficient: return "Trend pending"
        }
    }

    var systemImage: String {
        switch self {
        case .decreasing: return "arrow.down.right"
        case .stable: return "arrow.right"
        case .increasing: return "arrow.up.right"
        case .insufficient: return "minus"
        }
    }

    var color: Color {
        switch self {
        case .decreasing: return WSTheme.Palette.routine
        case .stable: return WSTheme.Palette.inkSecondary
        case .increasing: return WSTheme.Palette.clinical
        case .insufficient: return WSTheme.Palette.inkTertiary
        }
    }
}

// MARK: - Encounter detail

private struct WSEncounterCard: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let encounter: SavedMeasurement



    var body: some View {
        HStack(alignment: .top, spacing: WSTheme.Space.md) {
            ZStack {
                WSTheme.Palette.inkSecondary.opacity(0.13)
                Image(systemName: "bandage.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(WSTheme.Palette.inkSecondary)
            }
            .frame(width: 66, height: 66)
            .clipShape(
                RoundedRectangle(cornerRadius: WSTheme.Radius.md, style: .continuous)
            )

            VStack(alignment: .leading, spacing: WSTheme.Space.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(WoundL10n.text(encounter.date.woundFormatted(date: .abbreviated, time: .shortened)))
                        .font(.wsBodyBold)
                        .foregroundStyle(WSTheme.Palette.ink)
                    Spacer(minLength: WSTheme.Space.xs)
                }

                HStack(spacing: WSTheme.Space.xs) {
                    WSCompactMetric(
                        label: "Area",
                        value: String(format: "%.1f", encounter.area),
                        unit: "cm²"
                    )
                    WSCompactMetric(
                        label: "Vol",
                        value: String(format: "%.1f", encounter.volume),
                        unit: "cm³"
                    )
                    WSCompactMetric(
                        label: "Depth",
                        value: String(
                            format: "%.2f",
                            WoundMeasurementMath.depthCM(
                                area: encounter.area,
                                volume: encounter.volume
                            )
                        ),
                        unit: "cm"
                    )
                }
            }
        }
        .wsCard()
    }
}

private struct WSEncounterDetailView: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let encounter: SavedMeasurement
    let woundName: String



    private var depth: Float {
        WoundMeasurementMath.depthCM(area: encounter.area, volume: encounter.volume)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: WSTheme.Space.lg) {
                measurementHero
                measurementCard
                methodCard
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(WSTheme.Space.lg)
        }
        .background(WSTheme.Palette.paper.ignoresSafeArea())
        .navigationTitle(WoundL10n.text(encounter.date.woundFormatted(date: .abbreviated, time: .shortened)))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var measurementHero: some View {
        ZStack {
            LinearGradient(
                colors: [
                    WSTheme.Palette.inkSecondary.opacity(0.20),
                    WSTheme.Palette.lifted
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: WSTheme.Space.sm) {
                Image(systemName: "viewfinder.circle.fill")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(WSTheme.Palette.inkSecondary)
                Text(WoundL10n.text(woundName))
                    .font(.wsHeadline)
                    .foregroundStyle(WSTheme.Palette.ink)
                Text(WoundL10n.text("LiDAR measurement encounter"))
                    .font(.wsCaption)
                    .foregroundStyle(WSTheme.Palette.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 210)
        .clipShape(
            RoundedRectangle(cornerRadius: WSTheme.Radius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: WSTheme.Radius.card, style: .continuous)
                .strokeBorder(WSTheme.Palette.hairline, lineWidth: 0.5)
        }
    }

    private var measurementCard: some View {
        WSPatientSectionCard(title: "Measurements") {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: WSTheme.Space.sm),
                    GridItem(.flexible(), spacing: WSTheme.Space.sm)
                ],
                spacing: WSTheme.Space.md
            ) {
                WSMeasurementMetric(
                    label: "Perimeter",
                    value: String(format: "%.2f", encounter.perimeter),
                    unit: "cm"
                )
                WSMeasurementMetric(
                    label: "Area",
                    value: String(format: "%.2f", encounter.area),
                    unit: "cm²"
                )
                WSMeasurementMetric(
                    label: "Volume",
                    value: String(format: "%.2f", encounter.volume),
                    unit: "cm³"
                )
                WSMeasurementMetric(
                    label: "Depth",
                    value: String(format: "%.2f", depth),
                    unit: "cm"
                )
            }
        }
    }

    private var methodCard: some View {
        WSPatientSectionCard(title: "Measurement record") {
            VStack(spacing: WSTheme.Space.sm) {
                WSMetadataRow(
                    label: "Captured",
                    value: encounter.date.woundFormatted(date: .long, time: .shortened)
                )
                Divider()
                WSMetadataRow(label: "Source", value: "LiDAR / depth capture")


                Text(WoundL10n.text("Depth is displayed using the same saved-volume-to-area calculation as the capture results. No measurement value is recalculated by this screen."))
                    .font(.wsCaption)
                    .foregroundStyle(WSTheme.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, WSTheme.Space.xxs)
            }
        }
    }
}



// MARK: - Shared patient-view components

private struct WSPatientSectionCard<Content: View>: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let title: String
    private let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WSTheme.Space.sm) {
            Text(WoundL10n.text(title).uppercased())
                .font(.wsMicro)
                .tracking(0.8)
                .foregroundStyle(WSTheme.Palette.inkTertiary)
            content()
        }
        .wsCard()
    }
}

private struct WSSectionLabel: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(WoundL10n.text(title).uppercased())
                .font(.wsMicro)
                .tracking(0.8)
                .foregroundStyle(WSTheme.Palette.inkTertiary)
            Spacer()
            Text(WoundL10n.text("\(count)"))
                .font(.wsMicro.monospacedDigit())
                .foregroundStyle(WSTheme.Palette.inkSecondary)
        }
        .padding(.horizontal, WSTheme.Space.xs)
    }
}

private struct WSCompactMetric: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(WoundL10n.text(label.uppercased()))
                .font(.wsMicro)
                .tracking(0.5)
                .foregroundStyle(WSTheme.Palette.inkTertiary)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(WoundL10n.text(value))
                    .font(.wsCaption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(WSTheme.Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(WoundL10n.text(unit))
                    .font(.wsMicro)
                    .foregroundStyle(WSTheme.Palette.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, WSTheme.Space.xs)
        .padding(.vertical, 7)
        .background(
            WSTheme.Palette.sunken,
            in: RoundedRectangle(cornerRadius: WSTheme.Radius.sm, style: .continuous)
        )
    }
}

private struct WSMeasurementMetric: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: WSTheme.Space.xxs) {
            Text(WoundL10n.text(label.uppercased()))
                .font(.wsMicro)
                .tracking(0.6)
                .foregroundStyle(WSTheme.Palette.inkTertiary)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(WoundL10n.text(value))
                    .font(.wsMonoBig)
                    .foregroundStyle(WSTheme.Palette.ink)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(WoundL10n.text(unit))
                    .font(.wsCaption)
                    .foregroundStyle(WSTheme.Palette.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WSTheme.Space.sm)
        .background(
            WSTheme.Palette.sunken,
            in: RoundedRectangle(cornerRadius: WSTheme.Radius.md, style: .continuous)
        )
    }
}

private struct WSMetadataRow: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: WSTheme.Space.md) {
            Text(WoundL10n.text(label))
                .font(.wsCaption)
                .foregroundStyle(WSTheme.Palette.inkSecondary)
            Spacer()
            Text(WoundL10n.text(value))
                .font(.wsCaption.monospacedDigit())
                .foregroundStyle(WSTheme.Palette.ink)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct WSEmptyState: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let title: String
    let message: String
    let systemImage: String
    let buttonTitle: String
    let buttonImage: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: WSTheme.Space.md) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(WSTheme.Palette.professionalPrimary)
                .frame(width: 66, height: 66)
                .background(
                    WSTheme.Palette.professionalSoft,
                    in: RoundedRectangle(cornerRadius: WSTheme.Radius.lg, style: .continuous)
                )

            VStack(spacing: WSTheme.Space.xs) {
                Text(WoundL10n.text(title))
                    .font(.wsHeadline)
                    .foregroundStyle(WSTheme.Palette.ink)
                Text(WoundL10n.text(message))
                    .font(.wsBody)
                    .foregroundStyle(WSTheme.Palette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: action) {
                Label(WoundL10n.text(buttonTitle), systemImage: buttonImage)
                    .font(.wsBodyBold)
            }
            .buttonStyle(.borderedProminent)
            .tint(WSTheme.Palette.professionalPrimary)
        }
        .padding(WSTheme.Space.xl)
        .frame(maxWidth: 420)
        .wsCard(padding: 0)
        .padding(WSTheme.Space.lg)
    }
}

// MARK: - Saved measurement adapters

private struct WSMeasurementWound: Identifiable {
    let id: String
    let bodyArea: String
    let laterality: String?
    let fallbackTitle: String
    let encounters: [SavedMeasurement]

    var displayName: String {
        let side = WSMeasurementGrouping.expandedLaterality(laterality)
        if !bodyArea.isEmpty {
            return [side, bodyArea]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        return fallbackTitle.isEmpty ? "Unspecified wound" : fallbackTitle
    }

    var systemImage: String {
        BodyArea.allCases.first {
            $0.rawValue.caseInsensitiveCompare(bodyArea) == .orderedSame
        }?.systemImage ?? "bandage.fill"
    }
}

private enum WSMeasurementGrouping {
    static func measurements(
        for patient: WoundCorderPatient,
        from allMeasurements: [SavedMeasurement]
    ) -> [SavedMeasurement] {
        // Ambiguous legacy name-only records remain accessible in Saved records.
        return allMeasurements
            .filter { $0.patientID == patient.id }
            .sorted { $0.date > $1.date }
    }

    static func wounds(from measurements: [SavedMeasurement]) -> [WSMeasurementWound] {
        let grouped = Dictionary(grouping: measurements) { measurement in
            woundKey(for: measurement)
        }

        return grouped.compactMap { key, encounters in
            guard let latest = encounters.max(by: { $0.date < $1.date }) else { return nil }
            let bodyArea = latest.bodyArea?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let laterality = latest.laterality?.trimmingCharacters(in: .whitespacesAndNewlines)
            return WSMeasurementWound(
                id: key,
                bodyArea: bodyArea,
                laterality: laterality,
                fallbackTitle: latest.title.trimmingCharacters(in: .whitespacesAndNewlines),
                encounters: encounters.sorted { $0.date > $1.date }
            )
        }
        .sorted {
            let lhsDate = $0.encounters.first?.date ?? .distantPast
            let rhsDate = $1.encounters.first?.date ?? .distantPast
            return lhsDate > rhsDate
        }
    }



    static func expandedLaterality(_ value: String?) -> String {
        switch normalized(value ?? "") {
        case "l", "left": return "Left"
        case "r", "right": return "Right"
        default: return value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    private static func woundKey(for measurement: SavedMeasurement) -> String {
        let bodyArea = normalized(measurement.bodyArea ?? "")
        let laterality = normalized(measurement.laterality ?? "")

        if !bodyArea.isEmpty {
            return "location|\(laterality)|\(bodyArea)"
        }

        let title = normalized(measurement.title)
        return "title|\(title.isEmpty ? measurement.id.uuidString : title)"
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}



private enum WSProfileFormatting {
    static func summary(for patient: WoundCorderPatient) -> [String] {
        var values: [String] = []
        let gender = patient.genderRawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let age = patient.age.trimmingCharacters(in: .whitespacesAndNewlines)
        let height = patient.height.trimmingCharacters(in: .whitespacesAndNewlines)
        let weight = patient.weight.trimmingCharacters(in: .whitespacesAndNewlines)

        if !gender.isEmpty { values.append(genderName(gender)) }
        if !age.isEmpty { values.append(value(age, unit: "yr")) }
        if !height.isEmpty { values.append(value(height, unit: "cm")) }
        if !weight.isEmpty { values.append(value(weight, unit: "kg")) }
        return values
    }

    static func genderName(_ rawValue: String) -> String {
        switch rawValue.lowercased() {
        case "m", "male": return "Male"
        case "f", "female": return "Female"
        case "o", "other": return "Other"
        default: return rawValue
        }
    }

    private static func value(_ value: String, unit: String) -> String {
        let hasLetters = value.rangeOfCharacter(from: .letters) != nil
        return hasLetters ? value : "\(value) \(unit)"
    }
}
