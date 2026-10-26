import ARKit
import SwiftUI

/// The redesigned application shell. Measurement work is deliberately delegated to
/// `ContentView` and the existing ARKit pipeline; this type only owns navigation and UI state.
struct WoundCorderAppShell: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    @StateObject private var logManager = MeasurementLogManager()
    @StateObject private var patientStore = WoundCorderPatientStore()

    @AppStorage("woundcorderConsent.v2") private var hasCompletedWelcomeConsent = false
    @AppStorage("researchUsageConsent") private var researchUsageConsent = false
    @AppStorage("homeAppearanceMode") private var appearanceRaw = HomeAppearanceMode.light.rawValue
    @AppStorage("woundAppMode") private var modeRaw = WoundAppMode.publicPatient.rawValue

    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: Tab = .home
    @State private var showCapture = false
    @State private var capturePatient: WoundCorderPatient?
    @State private var showImageAnalysis = false
    @State private var showMeasurementLog = false
    @State private var showNewPatient = false

    private enum Tab: Hashable {
        case home
        case patients
        case device
        case reference
        case progress
        case settings
    }

    private var selectedMode: WoundAppMode {
        WoundAppMode(rawValue: modeRaw) ?? .publicPatient
    }

    private var appearance: HomeAppearanceMode {
        HomeAppearanceMode(rawValue: appearanceRaw) ?? .light
    }

    var body: some View {
        ZStack {
            mainTabs
                .allowsHitTesting(hasCompletedWelcomeConsent)
                .accessibilityHidden(!hasCompletedWelcomeConsent)

            if !hasCompletedWelcomeConsent {
                WoundCorderOnboardingView(
                    modeRaw: $modeRaw,
                    researchConsent: $researchUsageConsent,
                    onFinish: { hasCompletedWelcomeConsent = true }
                )
                .transition(.opacity)
                .zIndex(2)
            }

            if hasCompletedWelcomeConsent && scenePhase != .active {
                WoundCorderPrivacyCover(mode: selectedMode)
                    .zIndex(3)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WoundWorkflowCompleted"))) { _ in
            showCapture = false
            showImageAnalysis = false
            selectedTab = .home
        }
        .preferredColorScheme(appearance.colorScheme)
        .wsAppMode(selectedMode)
        .tint(selectedMode.wsPrimary)
        .fullScreenCover(isPresented: $showCapture) {
            WoundCorderCaptureFlow(
                patientStore: patientStore,
                prefilledPatient: capturePatient,
                photoOnly: !ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
            )
            .environmentObject(logManager)
        }
        .fullScreenCover(isPresented: $showImageAnalysis) {
            WoundCorderCaptureFlow(patientStore: patientStore, photoOnly: true)
                .environmentObject(logManager)
                .statusBarHidden(true)
        }
        .sheet(isPresented: $showMeasurementLog) {
            MeasurementLogListView()
                .environmentObject(logManager)
        }
        .sheet(isPresented: $showNewPatient) {
            WoundCorderQuickPatientSheet(store: patientStore)
        }

    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {

            NavigationStack {
                WoundCorderHomeView(
                    mode: selectedMode,
                    patients: patientStore.patients,
                    measurements: logManager.items,
                    onCapture: { startCapture(for: nil) },
                    onNewPatient: { showNewPatient = true },
                    onImportPhoto: { showImageAnalysis = true },
                    onShowLogs: { showMeasurementLog = true },
                    onShowPatients: { selectedTab = .patients },
                    onCapturePatient: startCapture(for:)
                )
            }
            .tabItem { Label(WoundL10n.text("Home"), systemImage: "house.fill") }
            .tag(Tab.home)

            NavigationStack { WoundCheckInHistoryView() }
                .tabItem { Label(WoundL10n.text("Progress"), systemImage: "chart.bar") }
                .tag(Tab.progress)

            NavigationStack {
                WoundCorderPatientsView(
                    store: patientStore,
                    measurements: logManager.items,
                    onCapture: startCapture(for:)
                )
            }
            .tabItem { Label(WoundL10n.text(selectedMode == .professional ? "Patients" : "My records"), systemImage: "person.2.fill") }
            .tag(Tab.patients)

            NavigationStack {
                WoundReferenceLibraryView(mode: selectedMode)
            }
            .tabItem { Label(WoundL10n.text("Reference"), systemImage: "photo.on.rectangle.angled") }
            .tag(Tab.reference)

            NavigationStack {
                WoundCorderDeviceView()
            }
            .tabItem { Label(WoundL10n.text("Device"), systemImage: "sensor.tag.radiowaves.forward.fill") }
            .tag(Tab.device)

            NavigationStack {
                WoundCorderSettingsDashboard(
                    patientCount: patientStore.patients.count,
                    measurementCount: logManager.items.count,
                    onShowLogs: { showMeasurementLog = true }
                )
            }
            .tabItem { Label(WoundL10n.text("Settings"), systemImage: "gearshape.fill") }
            .tag(Tab.settings)
        }
    }

    private func startCapture(for patient: WoundCorderPatient?) {
        capturePatient = patient
        showCapture = true
    }


}

// MARK: - Home

private struct WoundCorderHomeView: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let mode: WoundAppMode
    let patients: [WoundCorderPatient]
    let measurements: [SavedMeasurement]
    let onCapture: () -> Void
    let onNewPatient: () -> Void
    let onImportPhoto: () -> Void
    let onShowLogs: () -> Void
    let onShowPatients: () -> Void
    let onCapturePatient: (WoundCorderPatient) -> Void

    private var woundCount: Int {
        Set(measurements.map { item in
            [item.patientName ?? "", item.laterality ?? "", item.bodyArea ?? ""].joined(separator: "|")
        }).count
    }

    private var thisWeekCount: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
        return measurements.filter { $0.date >= cutoff }.count
    }





    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WSTheme.Space.lg) {
                header

                if mode == .professional {
                    professionalStats
                }

                woundStats
                captureButton
                quickActions

                if !measurements.isEmpty {
                    recentCaptures
                }

                patientSection

                Text(WoundL10n.text("Developed by Mitchell Liu"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(WSTheme.Palette.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, WSTheme.Space.sm)
            }
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
            .padding(WSTheme.Space.lg)
        }
        .background(WSTheme.Palette.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 7) {
                    Image("WoundCorder").resizable().scaledToFit().frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(WoundL10n.text("WoundCorder"))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(WSTheme.Palette.ink)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: WSTheme.Space.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(WoundL10n.text(greeting))
                    .font(.caption)
                    .foregroundStyle(WSTheme.Palette.secondary)
                Text(WoundL10n.text(mode == .professional ? "Capture or review" : "Your wound photos"))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(WSTheme.Palette.ink)
            }
            Spacer()
            WSModeChip(mode: mode)
        }
    }

    private var professionalStats: some View {
        HStack(spacing: WSTheme.Space.sm) {
            WSStatTile(title: "Patients", value: "\(patients.count)", systemImage: "person.2.fill", color: mode.wsPrimary)
            WSStatTile(title: "Measurements", value: "\(measurements.count)", systemImage: "ruler", color: mode.wsPrimary)
        }
    }

    private var woundStats: some View {
        HStack(spacing: WSTheme.Space.sm) {
            WSStatTile(title: "Active", value: "\(woundCount)", systemImage: "bandage.fill", color: mode.wsPrimary)
            WSStatTile(title: "This week", value: "\(thisWeekCount)", systemImage: "calendar", color: .green)
        }
    }

    private var captureButton: some View {
        Button(action: onCapture) {
            HStack(spacing: WSTheme.Space.md) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 25, weight: .semibold))
                    .frame(width: 56, height: 56)
                    .foregroundStyle(.white)
                    .background(.white.opacity(0.18), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(WoundL10n.text("Check a wound"))
                        .font(.title3.weight(.bold))
                    Text(WoundL10n.text("Add details, scan with LiDAR, then check with AI"))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.84))
                }

                Spacer()
                Image(systemName: "arrow.right")
                    .font(.headline.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(WSTheme.Space.lg)
            .background(mode.wsGradient)
            .clipShape(RoundedRectangle(cornerRadius: WSTheme.Radius.card, style: .continuous))
            .shadow(color: mode.wsPrimary.opacity(0.32), radius: 20, x: 0, y: 11)
        }
        .buttonStyle(.plain)
        .accessibilityHint(WoundL10n.text("Opens the guided intake before the LiDAR scanner"))
    }

    private var quickActions: some View {
        HStack(spacing: WSTheme.Space.md) {
            quickAction(icon: "viewfinder", title: "Measure wound", action: onCapture)
            quickAction(icon: "photo.on.rectangle", title: "Check photo", action: onImportPhoto)
        }
    }

    private func quickAction(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: WSTheme.Space.md) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(mode.wsPrimary)
                    .frame(width: 44, height: 44)
                    .background(mode.wsSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                Text(WoundL10n.text(title))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(WSTheme.Palette.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .wsCard()
        }
        .buttonStyle(.plain)
    }

    private var recentCaptures: some View {
        VStack(alignment: .leading, spacing: WSTheme.Space.sm) {
            WSSectionLabel("Recent captures")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WSTheme.Space.sm) {
                    ForEach(measurements.prefix(8)) { item in
                        Button(action: onShowLogs) {
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(mode.wsPrimary.opacity(0.14))
                                    Image(systemName: "bandage.fill")
                                        .font(.system(size: 30))
                                        .foregroundStyle(mode.wsPrimary)
                                }
                                .frame(width: 112, height: 112)

                                Text(WoundL10n.text(item.patientName.nilIfBlank ?? "Unassigned"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(WSTheme.Palette.ink)
                                    .lineLimit(1)
                                Text(WoundL10n.text(item.date.formatted(.relative(presentation: .named))))
                                    .font(.caption2)
                                    .foregroundStyle(WSTheme.Palette.secondary)
                            }
                            .frame(width: 112, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .wsAppMode(mode)
    }

    private var patientSection: some View {
        VStack(alignment: .leading, spacing: WSTheme.Space.sm) {
            HStack {
                WSSectionLabel("Patients")
                Spacer()
                Button(WoundL10n.text("View all"), action: onShowPatients)
                    .font(.subheadline.weight(.semibold))
            }

            if patients.isEmpty {
                VStack(spacing: WSTheme.Space.md) {
                    Image(systemName: "person.crop.circle.dashed")
                        .font(.system(size: 34))
                        .foregroundStyle(mode.wsPrimary)
                    Text(WoundL10n.text("No patients yet"))
                        .font(.headline)
                    Text(WoundL10n.text("Add a patient first, or start a capture and assign one during intake."))
                        .font(.subheadline)
                        .foregroundStyle(WSTheme.Palette.secondary)
                        .multilineTextAlignment(.center)
                    Button(WoundL10n.text("Add patient"), action: onNewPatient)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .wsCard()
            } else {
                VStack(spacing: WSTheme.Space.sm) {
                    ForEach(patients.prefix(5)) { patient in
                        NavigationLink {
                            WSPatientDetailView(
                                patient: patient,
                                measurements: measurements(for: patient),
                                onCapture: { onCapturePatient(patient) }
                            )
                        } label: {
                            HStack(spacing: WSTheme.Space.md) {
                                WSAvatar(initials: patient.initials, seed: patient.id.uuidString)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(patient.displayName)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(WSTheme.Palette.ink)
                                    Text(WoundL10n.text(patientSubtitle(patient)))
                                        .font(.caption)
                                        .foregroundStyle(WSTheme.Palette.secondary)
                                }
                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(WSTheme.Palette.secondary)
                            }
                            .wsCard()
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(WoundL10n.text("Shows this patient's wound history"))
                    }
                }
            }
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Hello"
        }
    }

    private func measurements(for patient: WoundCorderPatient) -> [SavedMeasurement] {
        measurements
            .filter { measurement in
                if let patientID = measurement.patientID {
                    return patientID == patient.id
                }
                return false // Unlinked legacy records stay in Saved records; names are not identities.
            }
            .sorted { $0.date > $1.date }
    }

    private func patientSubtitle(_ patient: WoundCorderPatient) -> String {
        let entries = measurements(for: patient)
        guard let latest = entries.first else {
            return "Added \(patient.createdAt.woundFormatted(date: .abbreviated, time: .omitted))"
        }
        let woundKeys = Set(entries.map { "\($0.laterality ?? "")|\($0.bodyArea ?? "")" })
        return "\(woundKeys.count) wound\(woundKeys.count == 1 ? "" : "s") · \(latest.date.formatted(.relative(presentation: .named)))"
    }
}

// MARK: - Device status

private struct WoundCorderDeviceView: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue

    private var supportsLiDAR: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
            && ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WSTheme.Space.lg) {
                Text(WoundL10n.text("Device"))
                    .font(.largeTitle.bold())

                HStack(spacing: WSTheme.Space.md) {
                    Image(systemName: supportsLiDAR ? "sensor.fill" : "sensor")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(supportsLiDAR ? .green : .orange)
                        .frame(width: 58, height: 58)
                        .background((supportsLiDAR ? Color.green : Color.orange).opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(WoundL10n.text(supportsLiDAR ? "LiDAR ready" : "LiDAR unavailable"))
                            .font(.title3.weight(.bold))
                        Label(WoundL10n.text(
                            supportsLiDAR ? "Scene depth and mesh reconstruction supported" : "Use a LiDAR-capable iPhone Pro or iPad Pro"),
                            systemImage: supportsLiDAR ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .font(.subheadline)
                        .foregroundStyle(WSTheme.Palette.secondary)
                    }
                    Spacer()
                }
                .wsCard()

                VStack(alignment: .leading, spacing: WSTheme.Space.md) {
                    WSSectionLabel("Measurement pipeline")
                    deviceRow(icon: "camera.metering.center.weighted", title: "RGB + scene depth", detail: "Captured together by ARKit")
                    Divider()
                    deviceRow(icon: "square.dashed", title: "On-device segmentation", detail: "Defines the current wound boundary")
                    Divider()
                    deviceRow(icon: "cube.transparent", title: "LiDAR mesh", detail: "Provides surface geometry and depth")
                    Divider()
                    deviceRow(icon: "function", title: "Area and volume", detail: "Computed by the existing measurement engine")
                }
                .wsCard()

                Text(WoundL10n.text("Measurement accuracy depends on lighting, distance, angle, motion, and visible wound boundaries. Review every result before clinical use."))
                    .font(.caption)
                    .foregroundStyle(WSTheme.Palette.secondary)
                    .padding(.horizontal, WSTheme.Space.sm)
            }
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
            .padding(WSTheme.Space.lg)
        }
        .background(WSTheme.Palette.paper.ignoresSafeArea())
        .navigationTitle(WoundL10n.text("Device"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func deviceRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: WSTheme.Space.md) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(.blue)
                .frame(width: 36, height: 36)
                .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(WoundL10n.text(title)).font(.body.weight(.semibold))
                Text(WoundL10n.text(detail)).font(.caption).foregroundStyle(WSTheme.Palette.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - Settings

private struct WoundCorderSettingsDashboard: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let patientCount: Int
    let measurementCount: Int
    let onShowLogs: () -> Void

    @AppStorage("woundLanguage") private var language = WoundLanguage.english.rawValue
    @AppStorage("woundAppMode") private var modeRaw = WoundAppMode.publicPatient.rawValue
    @AppStorage("homeAppearanceMode") private var appearanceRaw = HomeAppearanceMode.light.rawValue
    @AppStorage("woundAnalysisProvider") private var providerRaw = WoundAnalysisProvider.semanticCNN.rawValue
    @AppStorage("offlineFriendlyMode") private var offlineFriendlyMode = true
    @AppStorage("researchUsageConsent") private var researchUsageConsent = false

    private var mode: WoundAppMode {
        WoundAppMode(rawValue: modeRaw) ?? .publicPatient
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WSTheme.Space.lg) {
                appHeader
                languageCard
                modeCard
                analysisCard
                measurementCard
                privacyCard
                dataCard
            }
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
            .padding(WSTheme.Space.lg)
        }
        .background(WSTheme.Palette.paper.ignoresSafeArea())
        .navigationTitle(WoundL10n.text("Settings"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appHeader: some View {
        HStack(spacing: WSTheme.Space.md) {
            Image(systemName: "waveform.path.ecg.rectangle.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 62, height: 62)
                .background(mode.wsGradient, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .shadow(color: mode.wsPrimary.opacity(0.28), radius: 12, x: 0, y: 7)
            VStack(alignment: .leading, spacing: 3) {
                Text(WoundL10n.text("WoundCorder")).font(.title3.bold())
                Text(WoundL10n.text("On-device wound measurement"))
                    .font(.caption)
                    .foregroundStyle(WSTheme.Palette.secondary)
            }
            Spacer()
            WSModeChip(mode: mode)
        }
    }

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            WSSectionLabel("Language")
            Picker(WoundL10n.text("Language"), selection: $language) {
                ForEach(WoundLanguage.allCases) { option in
                    Text(verbatim: option.nativeName).tag(option.rawValue)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("settings.language")
            Text(WoundL10n.text("Changes the app language immediately. Your saved records and current check stay in place."))
                .font(.caption)
                .foregroundStyle(WSTheme.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(WoundL10n.text("Your notes and previously saved AI comments keep their original language."))
                .font(.caption)
                .foregroundStyle(WSTheme.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .wsCard()
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: WSTheme.Space.md) {
            WSSectionLabel("Mode")
            Picker(WoundL10n.text("Care mode"), selection: $modeRaw) {
                ForEach(WoundAppMode.allCases) { option in
                    Text(WoundL10n.text(option.displayName)).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
            Text(WoundL10n.text(mode.shortDetail))
                .font(.caption)
                .foregroundStyle(WSTheme.Palette.secondary)
            Divider()
            Picker(WoundL10n.text("Appearance"), selection: $appearanceRaw) {
                ForEach(HomeAppearanceMode.allCases) { option in
                    Label(WoundL10n.text(option.rawValue), systemImage: option.systemImage).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
        }
        .wsCard()
    }

    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: WSTheme.Space.md) {
            WSSectionLabel("Wound AI")
            NavigationLink {
                WoundAIModelView()
            } label: {
                settingsRow(icon: "brain.head.profile", title: "Models & privacy", value: "Manage")
            }
            .buttonStyle(.plain)

            Text(WoundL10n.text("Photo checks run on this device. You choose what to share."))
                .font(.caption)
                .foregroundStyle(WSTheme.Palette.secondary)
        }
        .wsCard()
    }

    private var measurementCard: some View {
        VStack(alignment: .leading, spacing: WSTheme.Space.md) {
            WSSectionLabel("Measurement")
            Toggle(WoundL10n.text("Offline-friendly LiDAR measurement"), isOn: $offlineFriendlyMode)
            Divider()
            settingsRow(icon: "cube.transparent", title: "Method", value: "ARKit LiDAR mesh + depth")
            settingsRow(icon: "square.dashed", title: "Boundary", value: "On-device segmentation")
            settingsRow(icon: "ruler", title: "Saved measurements", value: "\(measurementCount)")
        }
        .wsCard()
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: WSTheme.Space.md) {
            WSSectionLabel("Privacy")
            Toggle(WoundL10n.text("Allow de-identified usage data for research"), isOn: $researchUsageConsent)
            Text(WoundL10n.text("Research consent is optional and can be changed at any time. Wound images are not included by this setting."))
                .font(.caption)
                .foregroundStyle(WSTheme.Palette.secondary)
        }
        .wsCard()
    }

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: WSTheme.Space.md) {
            WSSectionLabel("Data")
            settingsRow(icon: "person.2", title: "Patients", value: "\(patientCount)")
            Button(action: onShowLogs) {
                settingsRow(icon: "chart.xyaxis.line", title: "Measurement history", value: "Open")
            }
            .buttonStyle(.plain)
        }
        .wsCard()
    }

    private func settingsRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: WSTheme.Space.md) {
            Image(systemName: icon)
                .foregroundStyle(mode.wsPrimary)
                .frame(width: 28)
            Text(WoundL10n.text(title))
                .foregroundStyle(WSTheme.Palette.ink)
            Spacer()
            Text(WoundL10n.text(value))
                .font(.subheadline)
                .foregroundStyle(WSTheme.Palette.secondary)
                .multilineTextAlignment(.trailing)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(WSTheme.Palette.secondary.opacity(0.7))
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Onboarding and privacy

private struct WoundCorderOnboardingView: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    @Binding var modeRaw: String
    @Binding var researchConsent: Bool
    let onFinish: () -> Void
    @State private var accepted = false
    @State private var step = 0
    @AppStorage("woundAnalysisProvider") private var providerRaw = WoundAnalysisProvider.semanticCNN.rawValue
    @AppStorage("woundOnDeviceModelID") private var modelID = OnDeviceModelStore.defaultModelID
    @ObservedObject private var modelStore = OnDeviceModelStore.shared
    private var ready: Bool {
        providerRaw == WoundAnalysisProvider.semanticCNN.rawValue ||
        (WoundDeviceCapacity.canRunContext && modelStore.model(withID: modelID).map { modelStore.isInstalled($0) } == true)
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if step == 0 {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Image("WoundCorder").resizable().scaledToFit().frame(height: 150).frame(maxWidth: .infinity)
                            Text(WoundL10n.text("Welcome to WoundCorder")).font(.largeTitle.bold())
                            Text(WoundL10n.text("AI Wound Tracking & Analysis")).font(.headline)
                            Text(WoundL10n.text("Take photos and keep track of a wound. The app can make mistakes. It cannot tell you for sure what a wound is, choose treatment, or replace your doctor or nurse."))
                            Text(WoundL10n.text("Get medical help if the wound gets worse, or you have fever, spreading redness, or bleeding that will not stop."))
                            Text(WoundL10n.text("Your photos and health details are stored on this device. You decide whether to share them. Email sharing sends only the items you choose."))
                            Picker(WoundL10n.text("Who is using the app?"), selection: $modeRaw) {
                                ForEach(WoundAppMode.allCases) { Text(WoundL10n.text($0.displayName)).tag($0.rawValue) }
                            }.pickerStyle(.segmented)
                            Toggle(WoundL10n.text("I understand these limits and agree to store my wound photos and health details on this device."), isOn: $accepted)
                            Toggle(WoundL10n.text("Optional: allow de-identified usage data for research"), isOn: $researchConsent)
                        }.padding()
                    }
                    Button { step = 1 } label: { Text(WoundL10n.text("Agree and continue")).frame(minHeight: 44) }.buttonStyle(.borderedProminent).disabled(!accepted)
                } else {
                    WoundAIModelView()
                    Text(WoundL10n.text("You can change this choice in Settings.")).font(.footnote)
                    if !ready { Text(WoundL10n.text("Choose Photo Check to start now, or finish downloading a supported model.")).font(.footnote).padding(.horizontal) }
                    HStack {
                        Button(WoundL10n.text("Back")) { step = 0 }.frame(minHeight: 48)
                        Button(action: onFinish) { Text(WoundL10n.text("Start using WoundCorder")).frame(minHeight: 44) }.buttonStyle(.borderedProminent).disabled(!ready)
                    }
                }
            }.padding(.bottom).background(WSTheme.Palette.paper)
        }.onAppear {
            if !WoundDeviceCapacity.canRunContext || WoundAnalysisProvider(rawValue: providerRaw) == nil { providerRaw = WoundAnalysisProvider.semanticCNN.rawValue }
        }
    }
}

private struct WoundCorderPrivacyCover: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let mode: WoundAppMode

    var body: some View {
        ZStack {
            WSTheme.Palette.paper.ignoresSafeArea()
            Image(systemName: "waveform.path.ecg.rectangle.fill")
                .font(.system(size: 45, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 100, height: 100)
                .background(mode.wsGradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .accessibilityHidden(true)
    }
}

private struct WoundCorderQuickPatientSheet: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    @ObservedObject var store: WoundCorderPatientStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var mrn = ""
    @State private var age = ""
    @State private var height = ""
    @State private var weight = ""
    @State private var genderRaw = PatientGender.unknown.rawValue

    var body: some View {
        NavigationStack {
            Form {
                if let error = store.storageError { WoundStorageRecoveryView(message: error, canRestore: store.canRestorePrevious, reload: store.reload, restore: store.restorePrevious) }
                Section(WoundL10n.text("Patient")) {
                    TextField(WoundL10n.text("Name or pseudonym"), text: $name)
                    TextField(WoundL10n.text("MRN / PID (optional)"), text: $mrn)
                    TextField(WoundL10n.text("Age"), text: $age).keyboardType(.numberPad)
                    Picker(WoundL10n.text("Gender"), selection: $genderRaw) {
                        ForEach(PatientGender.allCases) { gender in
                            Text(WoundL10n.text(gender.displayName)).tag(gender.rawValue)
                        }
                    }
                }
                Section(WoundL10n.text("Optional measurements")) {
                    if let message = draftProfile.validationMessage { Text(WoundL10n.text(message)).foregroundStyle(.red) }
                    TextField(WoundL10n.text("Height (cm)"), text: $height).keyboardType(.decimalPad)
                    TextField(WoundL10n.text("Weight (kg)"), text: $weight).keyboardType(.decimalPad)
                }
            }
            .navigationTitle(WoundL10n.text("New Patient"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(WoundL10n.text("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(WoundL10n.text("Save"), action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draftProfile.validationMessage != nil)
                }
            }
        }
    }

    private var draftProfile: PatientProfile { PatientProfile(name: name, height: height, weight: weight, age: age) }

    private func save() {
        var profile = PatientProfile()
        profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.mrnOrPID = mrn.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.age = age
        profile.height = height
        profile.weight = weight
        profile.gender = PatientGender(rawValue: genderRaw) ?? .unknown
        guard store.ensure(from: profile) != nil else { return }
        dismiss()
    }
}

private struct WSSectionLabel: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(WoundL10n.text(title).uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(WSTheme.Palette.tertiary)
    }
}



private extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

#if DEBUG
@MainActor func woundLanguageSettingsFixture() -> some View {
    WoundCorderSettingsDashboard(patientCount: 3, measurementCount: 12, onShowLogs: {})
}
#endif
