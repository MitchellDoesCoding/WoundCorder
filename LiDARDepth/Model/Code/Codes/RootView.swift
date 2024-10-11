import PhotosUI
import SwiftUI

private enum RootScreen {
    case home
    case intake
}

struct RootView: View {
    @StateObject private var logManager = MeasurementLogManager()
    @StateObject private var voiceRecorder = VoiceNoteRecorder()

    @AppStorage("hasCompletedWelcomeConsent") private var hasCompletedWelcomeConsent = false
    @AppStorage("researchUsageConsent") private var researchUsageConsent = false

    @State private var selectedMode: WoundAppMode = .publicPatient
    @State private var patientProfile = PatientProfile()
    @State private var woundIntake = WoundIntakeData()
    @State private var screen: RootScreen = .home
    @State private var showScan = false
    @State private var showImageAnalysis = false
    @State private var showLogs = false
    @State private var showSettings = false
    @State private var selectedPrescriptionItem: PhotosPickerItem?

    private func logoImage() -> Image? {
        if let ui = UIImage(named: "WoundCorder (1)") {
            return Image(uiImage: ui)
        }
        if let url = Bundle.main.url(forResource: "WoundCorder (1)", withExtension: "png"),
           let data = try? Data(contentsOf: url),
           let ui = UIImage(data: data) {
            return Image(uiImage: ui)
        }
        if let url = Bundle.main.url(forResource: "WoundCorder (1)", withExtension: "png", subdirectory: "LiDARDepth/Model/Code/Codes"),
           let data = try? Data(contentsOf: url),
           let ui = UIImage(data: data) {
            return Image(uiImage: ui)
        }
        return nil
    }

    var body: some View {
        ZStack {
            NavigationStack {
                ScrollView {
                    VStack(spacing: screen == .home ? 18 : 14) {
                        rootContent
                    }
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle(screen == .home ? "Woundcorder" : "New Wound")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if screen == .home {
                            Button {
                                showLogs = true
                            } label: {
                                Label("Logs", systemImage: "chart.xyaxis.line")
                            }
                        } else {
                            Button {
                                screen = .home
                            } label: {
                                Label("Home", systemImage: "chevron.left")
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }

            if !hasCompletedWelcomeConsent {
                ConsentWelcomeView(
                    logoImage: logoImage(),
                    researchConsent: $researchUsageConsent,
                    onContinue: { hasCompletedWelcomeConsent = true }
                )
                .transition(.opacity)
            }
        }
        .fullScreenCover(isPresented: $showScan) {
            ContentView(patientProfile: patientProfile, woundIntake: woundIntake)
                .environmentObject(logManager)
                .toolbar(.hidden, for: .tabBar)
                .statusBarHidden(true)
        }
        .fullScreenCover(isPresented: $showImageAnalysis) {
            ARCameraTabView()
                .environmentObject(logManager)
                .toolbar(.hidden, for: .tabBar)
                .statusBarHidden(true)
        }
        .sheet(isPresented: $showLogs) {
            MeasurementLogListView()
                .environmentObject(logManager)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onChange(of: selectedPrescriptionItem) { _, newItem in
            guard newItem != nil else { return }
            woundIntake.prescriptionAttachmentName = "Prescription or note attached"
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        switch screen {
        case .home:
            WoundHomeView(
                logoImage: logoImage(),
                mode: $selectedMode,
                items: logManager.items,
                patientCount: patientCount,
                severeCount: severeCount,
                needsReviewCount: needsReviewCount,
                onNewWound: beginNewWound,
                onImageAnalysis: { showImageAnalysis = true },
                onViewLogs: { showLogs = true }
            )
        case .intake:
            PatientWorkflowView(
                profile: $patientProfile,
                intake: $woundIntake,
                selectedPrescriptionItem: $selectedPrescriptionItem,
                voiceRecorder: voiceRecorder,
                latestSeverity: latestSeverity,
                onScan: { showScan = true },
                onUploadImage: { showImageAnalysis = true }
            )
        }
    }

    private func beginNewWound() {
        patientProfile = PatientProfile()
        woundIntake = WoundIntakeData()
        selectedPrescriptionItem = nil
        screen = .intake
    }

    private var header: some View {
        HStack(spacing: 14) {
            if let logo = logoImage() {
                logo
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: "viewfinder.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Any visible wound")
                    .font(.title2.weight(.bold))
                Text("Depth-first scan, body-part agnostic intake, offline-friendly measurement.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Mode", selection: $selectedMode) {
                ForEach(WoundAppMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(selectedMode.displayName)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var latestSeverity: Int {
        guard let latest = logManager.items.first else { return 1 }
        return latest.severity ?? WoundSeverityScorer.score(area: latest.area, volume: latest.volume)
    }

    private var patientCount: Int {
        let namedPatients = Set(logManager.items.compactMap { item -> String? in
            guard let name = item.patientName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { return nil }
            return name
        })
        return max(namedPatients.count, logManager.items.isEmpty ? 0 : 1)
    }

    private var severeCount: Int {
        logManager.items.filter { ($0.severity ?? WoundSeverityScorer.score(area: $0.area, volume: $0.volume)) >= 15 }.count
    }

    private var needsReviewCount: Int {
        logManager.items.filter { ($0.severity ?? WoundSeverityScorer.score(area: $0.area, volume: $0.volume)) >= 12 }.count
    }
}

private struct WoundHomeView: View {
    let logoImage: Image?
    @Binding var mode: WoundAppMode
    let items: [SavedMeasurement]
    let patientCount: Int
    let severeCount: Int
    let needsReviewCount: Int
    let onNewWound: () -> Void
    let onImageAnalysis: () -> Void
    let onViewLogs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HomeHeader(
                logoImage: logoImage,
                mode: mode,
                woundCount: items.count,
                severeCount: severeCount
            )

            HomeModePicker(mode: $mode)

            if mode == .publicPatient {
                PatientHomeOverview(
                    items: items,
                    onNewWound: onNewWound,
                    onImageAnalysis: onImageAnalysis,
                    onViewLogs: onViewLogs
                )
            } else {
                ProfessionalHomeOverview(
                    items: items,
                    patientCount: patientCount,
                    severeCount: severeCount,
                    needsReviewCount: needsReviewCount,
                    onAddPatient: onNewWound,
                    onScanPatient: onNewWound,
                    onViewLogs: onViewLogs
                )
            }
        }
    }
}

private struct HomeHeader: View {
    let logoImage: Image?
    let mode: WoundAppMode
    let woundCount: Int
    let severeCount: Int

    var body: some View {
        HStack(spacing: 14) {
            if let logoImage {
                logoImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: "viewfinder.circle")
                    .font(.system(size: 38))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(mode == .professional ? "Clinical wound dashboard" : "Your wound dashboard")
                    .font(.title3.weight(.bold))
                Text("\(woundCount) saved wounds • \(severeCount) severe")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct HomeModePicker: View {
    @Binding var mode: WoundAppMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Mode", selection: $mode) {
                ForEach(WoundAppMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(mode == .professional ? "Professional overview" : "Patient overview")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct PatientHomeOverview: View {
    let items: [SavedMeasurement]
    let onNewWound: () -> Void
    let onImageAnalysis: () -> Void
    let onViewLogs: () -> Void

    private var latestSeverity: Int {
        guard let latest = items.first else { return 1 }
        return latest.severity ?? WoundSeverityScorer.score(area: latest.area, volume: latest.volume)
    }

    private var bodyAreaCount: Int {
        Set(items.compactMap(\.bodyArea)).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                CompactStatTile(title: "Saved Wounds", value: "\(items.count)", systemImage: "list.clipboard", color: .blue)
                CompactStatTile(title: "Latest Score", value: "\(latestSeverity)/20", systemImage: "waveform.path.ecg", color: woundSeverityColor(latestSeverity))
                CompactStatTile(title: "Body Areas", value: "\(bodyAreaCount)", systemImage: "figure.arms.open", color: .green)
                CompactStatTile(title: "Needs Review", value: "\(items.filter { woundSeverity(for: $0) >= 12 }.count)", systemImage: "exclamationmark.triangle", color: .orange)
            }

            HomeActionGrid(
                primaryTitle: "New Wound",
                primaryIcon: "plus.circle.fill",
                secondaryTitle: "Upload Image",
                secondaryIcon: "photo.on.rectangle",
                tertiaryTitle: "All Wounds",
                tertiaryIcon: "folder",
                onPrimary: onNewWound,
                onSecondary: onImageAnalysis,
                onTertiary: onViewLogs
            )

            RecentWoundsSection(
                title: "Recent Wounds",
                emptyTitle: "No wounds yet",
                emptyMessage: "Start a new wound scan to see healing history here.",
                items: Array(items.prefix(6)),
                onViewAll: onViewLogs
            )
        }
    }
}

private struct ProfessionalHomeOverview: View {
    let items: [SavedMeasurement]
    let patientCount: Int
    let severeCount: Int
    let needsReviewCount: Int
    let onAddPatient: () -> Void
    let onScanPatient: () -> Void
    let onViewLogs: () -> Void

    private var reviewItems: [SavedMeasurement] {
        Array(items.filter { woundSeverity(for: $0) >= 12 }.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                CompactStatTile(title: "Patients", value: "\(patientCount)", systemImage: "person.2", color: .blue)
                CompactStatTile(title: "Total Wounds", value: "\(items.count)", systemImage: "list.clipboard", color: .green)
                CompactStatTile(title: "Severe", value: "\(severeCount)", systemImage: "cross.case", color: .red)
                CompactStatTile(title: "Review", value: "\(needsReviewCount)", systemImage: "stethoscope", color: .orange)
            }

            HomeActionGrid(
                primaryTitle: "Add Patient",
                primaryIcon: "person.badge.plus",
                secondaryTitle: "Start Scan",
                secondaryIcon: "viewfinder",
                tertiaryTitle: "All Wounds",
                tertiaryIcon: "folder",
                onPrimary: onAddPatient,
                onSecondary: onScanPatient,
                onTertiary: onViewLogs
            )

            RecentWoundsSection(
                title: "Needs Review",
                emptyTitle: "No review queue",
                emptyMessage: "Moderate and severe wounds will appear here.",
                items: reviewItems,
                onViewAll: onViewLogs
            )

            RecentWoundsSection(
                title: "All Recent Wounds",
                emptyTitle: "No patient wounds yet",
                emptyMessage: "Scans saved by the team will appear here.",
                items: Array(items.prefix(6)),
                onViewAll: onViewLogs
            )
        }
    }
}

private struct HomeActionGrid: View {
    let primaryTitle: String
    let primaryIcon: String
    let secondaryTitle: String
    let secondaryIcon: String
    let tertiaryTitle: String
    let tertiaryIcon: String
    let onPrimary: () -> Void
    let onSecondary: () -> Void
    let onTertiary: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            WorkflowActionButton(title: primaryTitle, systemImage: primaryIcon, prominence: .primary, action: onPrimary)
            WorkflowActionButton(title: secondaryTitle, systemImage: secondaryIcon, prominence: .secondary, action: onSecondary)
            WorkflowActionButton(title: tertiaryTitle, systemImage: tertiaryIcon, prominence: .secondary, action: onTertiary)
        }
    }
}

private struct RecentWoundsSection: View {
    let title: String
    let emptyTitle: String
    let emptyMessage: String
    let items: [SavedMeasurement]
    let onViewAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("View All", action: onViewAll)
                    .font(.subheadline.weight(.semibold))
                    .disabled(items.isEmpty)
            }

            if items.isEmpty {
                EmptyWoundState(title: emptyTitle, message: emptyMessage)
            } else {
                VStack(spacing: 10) {
                    ForEach(items) { item in
                        WoundSummaryCard(item: item)
                    }
                }
            }
        }
    }
}

private struct EmptyWoundState: View {
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct WoundSummaryCard: View {
    let item: SavedMeasurement

    private var severity: Int { woundSeverity(for: item) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: bodyAreaIcon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(woundSeverityColor(severity))
                .frame(width: 42, height: 42)
                .background(woundSeverityColor(severity).opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(locationText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(item.date.formatted(date: .abbreviated, time: .shortened)) • A \(item.area, specifier: "%.1f") cm² • V \(item.volume, specifier: "%.1f") cm³")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            SeverityBadge(score: severity)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var displayName: String {
        if let patientName = item.patientName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !patientName.isEmpty {
            return patientName
        }
        return item.title
    }

    private var locationText: String {
        let side = item.laterality.map { "\($0) " } ?? ""
        return "\(side)\(item.bodyArea ?? "Body area not set")"
    }

    private var bodyAreaIcon: String {
        switch item.bodyArea {
        case BodyArea.head.rawValue: return BodyArea.head.systemImage
        case BodyArea.upperLimbs.rawValue: return BodyArea.upperLimbs.systemImage
        case BodyArea.torso.rawValue: return BodyArea.torso.systemImage
        case BodyArea.lowerLimbs.rawValue: return BodyArea.lowerLimbs.systemImage
        case BodyArea.hands.rawValue: return BodyArea.hands.systemImage
        case BodyArea.feet.rawValue: return BodyArea.feet.systemImage
        case BodyArea.joints.rawValue: return BodyArea.joints.systemImage
        default: return "bandage"
        }
    }
}

private struct CompactStatTile: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(value)
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SeverityBadge: View {
    let score: Int

    var body: some View {
        Text("\(score)/20")
            .font(.headline.monospacedDigit())
            .foregroundStyle(woundSeverityColor(score))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(woundSeverityColor(score).opacity(0.12), in: Capsule())
    }
}

private func woundSeverity(for item: SavedMeasurement) -> Int {
    item.severity ?? WoundSeverityScorer.score(area: item.area, volume: item.volume)
}

private func woundSeverityColor(_ score: Int) -> Color {
    if score >= 15 { return .red }
    if score >= 10 { return .orange }
    return .green
}

private struct ConsentWelcomeView: View {
    let logoImage: Image?
    @Binding var researchConsent: Bool
    let onContinue: () -> Void

    @State private var measurementConsent = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    if let logoImage {
                        logoImage
                            .resizable()
                            .scaledToFit()
                            .frame(width: 54, height: 54)
                    } else {
                        Image(systemName: "cross.case")
                            .font(.system(size: 42))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Welcome")
                            .font(.title.weight(.bold))
                        Text("Public and Pro wound monitoring")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Skin tone and body area are stored as context, not as calibration requirements.", systemImage: "checkmark.seal")
                    Label("LiDAR/depth measurement can run offline; image analysis is optional.", systemImage: "wifi.slash")
                    Label("Mesh export supports 3D review of visible or covered surfaces.", systemImage: "cube.transparent")
                }
                .font(.subheadline)

                Toggle("I agree to capture and store wound measurements on this device.", isOn: $measurementConsent)
                    .toggleStyle(.switch)

                Toggle("Allow de-identified usage data to support research.", isOn: $researchConsent)
                    .toggleStyle(.switch)

                Button {
                    onContinue()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!measurementConsent)
            }
            .padding(20)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(24)
        }
    }
}

private struct PatientWorkflowView: View {
    @Binding var profile: PatientProfile
    @Binding var intake: WoundIntakeData
    @Binding var selectedPrescriptionItem: PhotosPickerItem?
    @ObservedObject var voiceRecorder: VoiceNoteRecorder

    let latestSeverity: Int
    let onScan: () -> Void
    let onUploadImage: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            BodyPartStatusPanel(
                bodyArea: intake.bodyArea,
                laterality: intake.laterality,
                severity: latestSeverity
            )

            PatientProfileSection(profile: $profile)
            WoundImageSection(intake: $intake)
            WoundContextSection(intake: $intake)
            NotesAndMedicineSection(
                intake: $intake,
                selectedPrescriptionItem: $selectedPrescriptionItem,
                voiceRecorder: voiceRecorder
            )

            HStack(spacing: 10) {
                WorkflowActionButton(
                    title: "Open LiDAR View",
                    systemImage: "viewfinder.circle",
                    prominence: .primary,
                    action: onScan
                )

                WorkflowActionButton(
                    title: "Upload Image",
                    systemImage: "photo.on.rectangle",
                    prominence: .secondary,
                    action: onUploadImage
                )
            }
        }
    }
}

private struct PatientProfileSection: View {
    @Binding var profile: PatientProfile

    var body: some View {
        SectionPanel(title: "Patient") {
            VStack(spacing: 10) {
                TextField("Name", text: $profile.name)
                    .textFieldStyle(.roundedBorder)

                TextField("MRN / PID", text: $profile.mrnOrPID)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    TextField("Age", text: $profile.age)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)

                    TextField("Height", text: $profile.height)
                        .textFieldStyle(.roundedBorder)

                    TextField("Weight", text: $profile.weight)
                        .textFieldStyle(.roundedBorder)
                }

                Picker("Gender", selection: $profile.gender) {
                    ForEach(PatientGender.allCases) { gender in
                        Text(gender.rawValue).tag(gender)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Monk Skin Tone \(profile.monkSkinTone)")
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 6) {
                        ForEach(1...10, id: \.self) { tone in
                            Button {
                                profile.monkSkinTone = tone
                            } label: {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(MonkSkinTonePalette.colors[tone - 1])
                                    .frame(height: 30)
                                    .overlay {
                                        if profile.monkSkinTone == tone {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(tone > 6 ? .white : .black)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Monk skin tone \(tone)")
                        }
                    }
                }
            }
        }
    }
}

private struct WoundImageSection: View {
    @Binding var intake: WoundIntakeData

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        SectionPanel(title: "Image") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Side", selection: $intake.laterality) {
                    ForEach(Laterality.allCases) { side in
                        Text(side.rawValue).tag(side)
                    }
                }
                .pickerStyle(.segmented)

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(BodyArea.allCases) { area in
                        SelectableChip(
                            title: area.rawValue,
                            systemImage: area.systemImage,
                            isSelected: intake.bodyArea == area
                        ) {
                            intake.bodyArea = area
                        }
                    }
                }
            }
        }
    }
}

private struct WoundContextSection: View {
    @Binding var intake: WoundIntakeData

    private let columns = [
        GridItem(.adaptive(minimum: 130), spacing: 8)
    ]

    var body: some View {
        SectionPanel(title: "Context") {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(WoundContext.allCases) { context in
                        SelectableChip(
                            title: context.rawValue,
                            systemImage: nil,
                            isSelected: intake.contexts.contains(context)
                        ) {
                            if intake.contexts.contains(context) {
                                intake.contexts.remove(context)
                            } else {
                                intake.contexts.insert(context)
                            }
                        }
                    }
                }

                Picker("Date Wounded", selection: $intake.dateWounded) {
                    ForEach(WoundedDateOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }
}

private struct NotesAndMedicineSection: View {
    @Binding var intake: WoundIntakeData
    @Binding var selectedPrescriptionItem: PhotosPickerItem?
    @ObservedObject var voiceRecorder: VoiceNoteRecorder

    @State private var medicineDraft = ""

    var body: some View {
        SectionPanel(title: "Notes & Medicines") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Type wound notes or care instructions", text: $intake.notes, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button {
                        voiceRecorder.toggleRecording()
                    } label: {
                        Label(
                            voiceRecorder.isRecording ? "Stop" : "Record",
                            systemImage: voiceRecorder.isRecording ? "stop.circle.fill" : "mic.circle"
                        )
                    }
                    .buttonStyle(.bordered)

                    Text(voiceRecorder.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                PhotosPicker(selection: $selectedPrescriptionItem, matching: .images) {
                    Label(
                        intake.prescriptionAttachmentName.isEmpty ? "Upload Prescription / Notes" : intake.prescriptionAttachmentName,
                        systemImage: "doc.badge.plus"
                    )
                }
                .buttonStyle(.bordered)

                HStack(spacing: 8) {
                    TextField("Medicine tracker", text: $medicineDraft)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        addMedicine()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(medicineDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if !intake.medicineEntries.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(intake.medicineEntries, id: \.self) { medicine in
                                Button {
                                    intake.medicineEntries.removeAll { $0 == medicine }
                                } label: {
                                    Label(medicine, systemImage: "pills")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(Color.green.opacity(0.14), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private func addMedicine() {
        let trimmed = medicineDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        intake.medicineEntries.append(trimmed)
        medicineDraft = ""
    }
}

private struct BodyPartStatusPanel: View {
    let bodyArea: BodyArea
    let laterality: Laterality
    let severity: Int

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            SeverityGraphBackground(score: severity)

            HStack(alignment: .center, spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color(.systemBackground).opacity(0.88))
                        .frame(width: 112, height: 112)

                    Image(systemName: bodyArea.systemImage)
                        .font(.system(size: 58, weight: .medium))
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("\(laterality.rawValue) \(bodyArea.rawValue)")
                        .font(.title3.weight(.bold))
                    Text("Severity score")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(severity)/20")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(severity >= 15 ? .red : severity >= 10 ? .orange : .green)
                }

                Spacer()
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 170)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipped()
    }
}

private struct SeverityGraphBackground: View {
    let score: Int

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let points = samplePoints(width: width, height: height)

            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(Color.blue.opacity(0.24), lineWidth: 3)

            Path { path in
                path.move(to: CGPoint(x: 0, y: height))
                for point in points {
                    path.addLine(to: point)
                }
                path.addLine(to: CGPoint(x: width, y: height))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [Color.blue.opacity(0.16), Color.green.opacity(0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .allowsHitTesting(false)
    }

    private func samplePoints(width: CGFloat, height: CGFloat) -> [CGPoint] {
        let normalized = CGFloat(min(max(score, 1), 20)) / 20
        return (0..<7).map { index in
            let x = width * CGFloat(index) / 6
            let wobble = sin(CGFloat(index) * 1.2) * 14
            let trend = height * (0.75 - normalized * 0.45)
            return CGPoint(x: x, y: trend + wobble)
        }
    }
}

private struct ProfessionalDashboardView: View {
    let patientCount: Int
    let severeCount: Int
    let needsReviewCount: Int
    let reviewItems: [SavedMeasurement]
    let onAddPatient: () -> Void
    let onScanPatient: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                DashboardMetric(title: "Patients", value: "\(patientCount)", color: .blue)
                DashboardMetric(title: "Severe", value: "\(severeCount)", color: .red)
                DashboardMetric(title: "Needs Review", value: "\(needsReviewCount)", color: .orange)
                DashboardMetric(title: "Queue", value: "\(reviewItems.count)", color: .purple)
            }

            SectionPanel(title: "Review Queue") {
                if reviewItems.isEmpty {
                    ContentUnavailableView("No patients in review", systemImage: "checkmark.seal")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else {
                    VStack(spacing: 10) {
                        ForEach(reviewItems) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.patientName?.isEmpty == false ? item.patientName! : item.title)
                                        .font(.headline)
                                    Text("\(item.bodyArea ?? "Body area not set") • Area \(item.area, specifier: "%.2f") cm² • Volume \(item.volume, specifier: "%.2f") cm³")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(item.severity ?? WoundSeverityScorer.score(area: item.area, volume: item.volume))/20")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle((item.severity ?? 1) >= 15 ? .red : .orange)
                            }
                            .padding(10)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                WorkflowActionButton(title: "Add Patient", systemImage: "person.badge.plus", prominence: .secondary, action: onAddPatient)
                WorkflowActionButton(title: "Scan Patient", systemImage: "viewfinder", prominence: .primary, action: onScanPatient)
            }
        }
    }
}

private struct DashboardMetric: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private enum WorkflowButtonProminence {
    case primary
    case secondary
}

private struct WorkflowActionButton: View {
    let title: String
    let systemImage: String
    let prominence: WorkflowButtonProminence
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
        }
        .buttonStyle(.borderedProminent)
        .tint(prominence == .primary ? .blue : .gray)
    }
}

private struct SectionPanel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SelectableChip: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(isSelected ? Color.blue.opacity(0.16) : Color(.tertiarySystemGroupedBackground), in: Capsule())
            .overlay {
                Capsule().stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RootView()
}
