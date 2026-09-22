import Charts
import Foundation
import SwiftUI

// MARK: - Patient list

/// Patient browsing for the professional workflow. Measurement history remains backed by
/// `SavedMeasurement`; these views only organize and present the values produced by capture.
struct WoundScopePatientsView: View {
    @ObservedObject private var store: WoundScopePatientStore

    let measurements: [SavedMeasurement]
    let onCapture: (WoundScopePatient) -> Void

    @State private var searchText = ""
    @State private var isPresentingNewPatient = false
    @State private var pendingDelete: WoundScopePatient?

    init(
        store: WoundScopePatientStore,
        measurements: [SavedMeasurement],
        onCapture: @escaping (WoundScopePatient) -> Void
    ) {
        _store = ObservedObject(wrappedValue: store)
        self.measurements = measurements
        self.onCapture = onCapture
    }

    private var filteredPatients: [WoundScopePatient] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.patients }

        return store.patients.filter { patient in
            patient.displayName.localizedCaseInsensitiveContains(query)
                || patient.mrnOrPID.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
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
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(WSTheme.Palette.paper.ignoresSafeArea())
        .overlay {
            if store.patients.isEmpty {
                WSPatientListEmptyState {
                    isPresentingNewPatient = true
                }
            } else if filteredPatients.isEmpty {
                WSNoSearchResultsState(query: searchText) {
                    searchText = ""
                }
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Name or MRN / patient ID"
        )
        .navigationTitle("Patients")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingNewPatient = true
                } label: {
                    Label("New patient", systemImage: "person.badge.plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingNewPatient) {
            WSNewPatientSheet(store: store)
        }
        .confirmationDialog(
            "Delete patient?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDelete {
                    store.delete(pendingDelete)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("The patient profile will be removed. Existing measurement logs are not changed.")
        }
    }
}

private struct WSPatientRow: View {
    let patient: WoundScopePatient
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
                    Text("MRN / ID \(patient.mrnOrPID)")
                        .font(.wsCaption)
                        .foregroundStyle(WSTheme.Palette.inkSecondary)
                        .lineLimit(1)
                }

                Text(historySummary)
                    .font(.wsCaption)
                    .foregroundStyle(WSTheme.Palette.inkSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: WSTheme.Space.xs)

            if let latest {
                let severity = WSMeasurementGrouping.severity(for: latest)
                Text("\(severity)")
                    .font(.wsCaption.weight(.bold).monospacedDigit())
                    .foregroundStyle(WSMeasurementStyling.color(for: severity))
                    .frame(width: 30, height: 30)
                    .background(
                        WSMeasurementStyling.color(for: severity).opacity(0.13),
                        in: Circle()
                    )
                    .accessibilityLabel("Latest severity \(severity) of 20")
            }
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
    @ObservedObject private var store: WoundScopePatientStore
    @Environment(\.dismiss) private var dismiss

    @State private var profile = PatientProfile()

    init(store: WoundScopePatientStore) {
        _store = ObservedObject(wrappedValue: store)
    }

    private var canSave: Bool {
        !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Patient") {
                    TextField("Display name", text: $profile.name)
                        .textInputAutocapitalization(.words)
                        .textContentType(.name)

                    TextField("MRN or patient ID (optional)", text: $profile.mrnOrPID)
                        .textInputAutocapitalization(.never)
                }

                Section("Profile (optional)") {
                    Picker("Gender", selection: $profile.gender) {
                        ForEach(PatientGender.allCases) { gender in
                            Text(WSProfileFormatting.genderName(gender.rawValue))
                                .tag(gender)
                        }
                    }

                    HStack {
                        Text("Age")
                        Spacer()
                        TextField("years", text: $profile.age)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 110)
                    }

                    HStack {
                        Text("Height")
                        Spacer()
                        TextField("cm", text: $profile.height)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 110)
                    }

                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField("kg", text: $profile.weight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 110)
                    }
                }

                Section {
                    Label(
                        "Profile details organize saved scans; they do not change LiDAR measurement calculations.",
                        systemImage: "checkmark.shield"
                    )
                    .font(.wsCaption)
                    .foregroundStyle(WSTheme.Palette.inkSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(WSTheme.Palette.paper.ignoresSafeArea())
            .navigationTitle("New patient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        profile.mrnOrPID = profile.mrnOrPID.trimmingCharacters(in: .whitespacesAndNewlines)
                        _ = store.add(from: profile)
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
    let patient: WoundScopePatient
    let measurements: [SavedMeasurement]
    let onCapture: () -> Void

    private var wounds: [WSMeasurementWound] {
        WSMeasurementGrouping.wounds(from: measurements)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: WSTheme.Space.lg) {
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
                    Label("New capture", systemImage: "plus.viewfinder")
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
                    Text("MRN / ID \(patient.mrnOrPID)")
                        .font(.wsCaption)
                        .foregroundStyle(WSTheme.Palette.inkSecondary)
                }

                Text("\(wounds.count) wound\(wounds.count == 1 ? "" : "s") · \(measurements.count) encounter\(measurements.count == 1 ? "" : "s")")
                    .font(.wsCaption)
                    .foregroundStyle(WSTheme.Palette.inkSecondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profileCard: some View {
        WSPatientSectionCard(title: "Profile") {
            Text(WSProfileFormatting.summary(for: patient).joined(separator: " · "))
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
                        Text("No wounds tracked yet")
                            .font(.wsHeadline)
                            .foregroundStyle(WSTheme.Palette.ink)
                        Text("Start a capture to create this patient’s first wound encounter.")
                            .font(.wsCaption)
                            .foregroundStyle(WSTheme.Palette.inkSecondary)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: onCapture) {
                        Label("Start capture", systemImage: "viewfinder")
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
    let wound: WSMeasurementWound

    private var latest: SavedMeasurement? { wound.encounters.first }

    var body: some View {
        HStack(spacing: WSTheme.Space.md) {
            Image(systemName: wound.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(severityColor)
                .frame(width: 44, height: 44)
                .background(
                    severityColor.opacity(0.13),
                    in: RoundedRectangle(cornerRadius: WSTheme.Radius.md, style: .continuous)
                )

            VStack(alignment: .leading, spacing: WSTheme.Space.xxs) {
                Text(wound.displayName)
                    .font(.wsBodyBold)
                    .foregroundStyle(WSTheme.Palette.ink)
                    .lineLimit(1)

                if let latest {
                    Text("\(latest.area, specifier: "%.1f") cm² · \(wound.encounters.count) encounter\(wound.encounters.count == 1 ? "" : "s")")
                        .font(.wsCaption)
                        .foregroundStyle(WSTheme.Palette.inkSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: WSTheme.Space.xs)

            if wound.encounters.count >= 2 {
                WSAreaSparkline(encounters: wound.encounters, tint: severityColor)
                    .frame(width: 58, height: 30)
            }

            if let latest {
                WSTierBadge(
                    tier: WSTier(severity: WSMeasurementGrouping.severity(for: latest)),
                    compact: true
                )
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WSTheme.Palette.inkTertiary)
        }
        .padding(WSTheme.Space.md)
        .wsCard(padding: 0)
    }

    private var severityColor: Color {
        guard let latest else { return WSTheme.Palette.inkTertiary }
        return WSMeasurementStyling.color(
            for: WSMeasurementGrouping.severity(for: latest)
        )
    }
}

private struct WSAreaSparkline: View {
    let encounters: [SavedMeasurement]
    let tint: Color

    private var series: [SavedMeasurement] {
        encounters.sorted { $0.date < $1.date }
    }

    var body: some View {
        Chart(series) { encounter in
            LineMark(
                x: .value("Date", encounter.date),
                y: .value("Area", Double(encounter.area))
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(tint)
            .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityLabel("Wound area trend")
    }
}

private struct WSWoundDetailView: View {
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
                if let latest = encountersNewestFirst.first {
                    WSTierSummaryCard(measurement: latest)
                }
                trendCard
                encounterSection
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(WSTheme.Space.lg)
        }
        .background(WSTheme.Palette.paper.ignoresSafeArea())
        .navigationTitle(wound.displayName)
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
                Text(wound.displayName)
                    .font(.wsHeadline)
                    .foregroundStyle(WSTheme.Palette.ink)
                Text("\(wound.encounters.count) encounter\(wound.encounters.count == 1 ? "" : "s")")
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
                Picker("Metric", selection: $trendMetric) {
                    ForEach(WSTrendMetric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .pickerStyle(.segmented)

                if encountersOldestFirst.count >= 2 {
                    Chart(encountersOldestFirst) { encounter in
                        AreaMark(
                            x: .value("Date", encounter.date),
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
                            x: .value("Date", encounter.date),
                            y: .value(
                                trendMetric.rawValue,
                                trendMetric.value(for: encounter)
                            )
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(WSTheme.Palette.professionalPrimary)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))

                        PointMark(
                            x: .value("Date", encounter.date),
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
                    .accessibilityLabel("\(trendMetric.rawValue) trend in \(trendMetric.unit)")
                } else {
                    VStack(spacing: WSTheme.Space.sm) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 25, weight: .medium))
                            .foregroundStyle(WSTheme.Palette.inkTertiary)
                        Text("Capture at least two encounters to see a trend.")
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
                Text("No saved encounters are available for this wound.")
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
                WoundSeverityScorer.depthCM(
                    area: measurement.area,
                    volume: measurement.volume
                )
            )
        }
    }
}

private struct WSTrajectoryChip: View {
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
        Label(trajectory.label, systemImage: trajectory.systemImage)
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
    let encounter: SavedMeasurement

    private var severity: Int {
        WSMeasurementGrouping.severity(for: encounter)
    }

    var body: some View {
        HStack(alignment: .top, spacing: WSTheme.Space.md) {
            ZStack {
                WSMeasurementStyling.color(for: severity).opacity(0.13)
                Image(systemName: "bandage.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(WSMeasurementStyling.color(for: severity))
            }
            .frame(width: 66, height: 66)
            .clipShape(
                RoundedRectangle(cornerRadius: WSTheme.Radius.md, style: .continuous)
            )

            VStack(alignment: .leading, spacing: WSTheme.Space.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(encounter.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.wsBodyBold)
                        .foregroundStyle(WSTheme.Palette.ink)
                    Spacer(minLength: WSTheme.Space.xs)
                    WSTierBadge(tier: WSTier(severity: severity), compact: true)
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
                            WoundSeverityScorer.depthCM(
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
    let encounter: SavedMeasurement
    let woundName: String

    private var severity: Int {
        WSMeasurementGrouping.severity(for: encounter)
    }

    private var depth: Float {
        WoundSeverityScorer.depthCM(area: encounter.area, volume: encounter.volume)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: WSTheme.Space.lg) {
                measurementHero
                WSTierSummaryCard(measurement: encounter)
                measurementCard
                methodCard
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(WSTheme.Space.lg)
        }
        .background(WSTheme.Palette.paper.ignoresSafeArea())
        .navigationTitle(encounter.date.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var measurementHero: some View {
        ZStack {
            LinearGradient(
                colors: [
                    WSMeasurementStyling.color(for: severity).opacity(0.20),
                    WSTheme.Palette.lifted
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: WSTheme.Space.sm) {
                Image(systemName: "viewfinder.circle.fill")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(WSMeasurementStyling.color(for: severity))
                Text(woundName)
                    .font(.wsHeadline)
                    .foregroundStyle(WSTheme.Palette.ink)
                Text("LiDAR measurement encounter")
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
                    value: encounter.date.formatted(date: .long, time: .shortened)
                )
                Divider()
                WSMetadataRow(label: "Source", value: "LiDAR / depth capture")
                Divider()
                WSMetadataRow(
                    label: "Severity",
                    value: "\(severity) / 20"
                )

                Text("Depth is displayed using the same saved-volume-to-area calculation as the capture results. No measurement value is recalculated by this screen.")
                    .font(.wsCaption)
                    .foregroundStyle(WSTheme.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, WSTheme.Space.xxs)
            }
        }
    }
}

private struct WSTierSummaryCard: View {
    let measurement: SavedMeasurement

    private var severity: Int {
        WSMeasurementGrouping.severity(for: measurement)
    }

    var body: some View {
        HStack(spacing: WSTheme.Space.md) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(WSMeasurementStyling.color(for: severity))
                .frame(width: 46, height: 46)
                .background(
                    WSMeasurementStyling.color(for: severity).opacity(0.13),
                    in: RoundedRectangle(cornerRadius: WSTheme.Radius.md, style: .continuous)
                )

            VStack(alignment: .leading, spacing: WSTheme.Space.xxs) {
                WSTierBadge(tier: WSTier(severity: severity))
                Text("Measurement severity score \(severity) of 20")
                    .font(.wsCaption)
                    .foregroundStyle(WSTheme.Palette.inkSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(WSTheme.Space.md)
        .background(
            WSMeasurementStyling.color(for: severity).opacity(0.055),
            in: RoundedRectangle(cornerRadius: WSTheme.Radius.lg, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: WSTheme.Radius.lg, style: .continuous)
                .strokeBorder(
                    WSMeasurementStyling.color(for: severity).opacity(0.22),
                    lineWidth: 1
                )
        }
    }
}

// MARK: - Shared patient-view components

private struct WSPatientSectionCard<Content: View>: View {
    let title: String
    private let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WSTheme.Space.sm) {
            Text(title.uppercased())
                .font(.wsMicro)
                .tracking(0.8)
                .foregroundStyle(WSTheme.Palette.inkTertiary)
            content()
        }
        .wsCard()
    }
}

private struct WSSectionLabel: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.wsMicro)
                .tracking(0.8)
                .foregroundStyle(WSTheme.Palette.inkTertiary)
            Spacer()
            Text("\(count)")
                .font(.wsMicro.monospacedDigit())
                .foregroundStyle(WSTheme.Palette.inkSecondary)
        }
        .padding(.horizontal, WSTheme.Space.xs)
    }
}

private struct WSCompactMetric: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.wsMicro)
                .tracking(0.5)
                .foregroundStyle(WSTheme.Palette.inkTertiary)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.wsCaption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(WSTheme.Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(unit)
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
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: WSTheme.Space.xxs) {
            Text(label.uppercased())
                .font(.wsMicro)
                .tracking(0.6)
                .foregroundStyle(WSTheme.Palette.inkTertiary)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.wsMonoBig)
                    .foregroundStyle(WSTheme.Palette.ink)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(unit)
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
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: WSTheme.Space.md) {
            Text(label)
                .font(.wsCaption)
                .foregroundStyle(WSTheme.Palette.inkSecondary)
            Spacer()
            Text(value)
                .font(.wsCaption.monospacedDigit())
                .foregroundStyle(WSTheme.Palette.ink)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct WSEmptyState: View {
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
                Text(title)
                    .font(.wsHeadline)
                    .foregroundStyle(WSTheme.Palette.ink)
                Text(message)
                    .font(.wsBody)
                    .foregroundStyle(WSTheme.Palette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: action) {
                Label(buttonTitle, systemImage: buttonImage)
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
        for patient: WoundScopePatient,
        from allMeasurements: [SavedMeasurement]
    ) -> [SavedMeasurement] {
        let patientNames = Set(
            [patient.name, patient.displayName]
                .map(normalized)
                .filter { !$0.isEmpty }
        )

        return allMeasurements
            .filter { measurement in
                if let patientID = measurement.patientID {
                    return patientID == patient.id
                }
                guard let recordedName = measurement.patientName else { return false }
                return patientNames.contains(normalized(recordedName))
            }
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

    static func severity(for measurement: SavedMeasurement) -> Int {
        measurement.severity
            ?? WoundSeverityScorer.score(area: measurement.area, volume: measurement.volume)
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

private enum WSMeasurementStyling {
    static func color(for severity: Int) -> Color {
        switch severity {
        case ...5: return WSTheme.Palette.routine
        case 6...9: return WSTheme.Palette.monitor
        case 10...14: return WSTheme.Palette.clinical
        default: return WSTheme.Palette.urgent
        }
    }
}

private enum WSProfileFormatting {
    static func summary(for patient: WoundScopePatient) -> [String] {
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
