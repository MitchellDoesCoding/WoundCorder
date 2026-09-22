import ARKit
import SwiftUI

/// The redesigned application shell. Measurement work is deliberately delegated to
/// `ContentView` and the existing ARKit pipeline; this type only owns navigation and UI state.
struct WoundScopeAppShell: View {
    @StateObject private var logManager = MeasurementLogManager()
    @StateObject private var patientStore = WoundScopePatientStore()

    @AppStorage("hasCompletedWelcomeConsent") private var hasCompletedWelcomeConsent = false
    @AppStorage("researchUsageConsent") private var researchUsageConsent = false
    @AppStorage("homeAppearanceMode") private var appearanceRaw = HomeAppearanceMode.light.rawValue
    @AppStorage("woundAppMode") private var modeRaw = WoundAppMode.publicPatient.rawValue

    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: Tab = .home
    @State private var showCapture = false
    @State private var capturePatient: WoundScopePatient?
    @State private var showImageAnalysis = false
    @State private var showMeasurementLog = false
    @State private var showNewPatient = false

    private enum Tab: Hashable {
        case home
        case patients
        case device
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

            if !hasCompletedWelcomeConsent {
                WoundScopeOnboardingView(
                    modeRaw: $modeRaw,
                    researchConsent: $researchUsageConsent,
                    onFinish: { hasCompletedWelcomeConsent = true }
                )
                .transition(.opacity)
                .zIndex(2)
            }

            if hasCompletedWelcomeConsent && scenePhase != .active {
                WoundScopePrivacyCover(mode: selectedMode)
                    .zIndex(3)
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .wsAppMode(selectedMode)
        .tint(selectedMode.wsPrimary)
        .fullScreenCover(isPresented: $showCapture) {
            WoundScopeCaptureFlow(
                patientStore: patientStore,
                prefilledPatient: capturePatient
            )
            .environmentObject(logManager)
        }
        .fullScreenCover(isPresented: $showImageAnalysis) {
            ARCameraTabView()
                .environmentObject(logManager)
                .statusBarHidden(true)
        }
        .sheet(isPresented: $showMeasurementLog) {
            MeasurementLogListView()
                .environmentObject(logManager)
        }
        .sheet(isPresented: $showNewPatient) {
            WoundScopeQuickPatientSheet(store: patientStore)
        }
        .onAppear(perform: synchronizePatientsFromMeasurements)
        .onChange(of: logManager.items) { _, _ in
            synchronizePatientsFromMeasurements()
        }
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                WoundScopeHomeView(
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
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(Tab.home)

            NavigationStack {
                WoundScopePatientsView(
                    store: patientStore,
                    measurements: logManager.items,
                    onCapture: startCapture(for:)
                )
            }
            .tabItem { Label("Patients", systemImage: "person.2.fill") }
            .tag(Tab.patients)

            NavigationStack {
                WoundScopeDeviceView(onStartCapture: { startCapture(for: nil) })
            }
            .tabItem { Label("Device", systemImage: "sensor.tag.radiowaves.forward.fill") }
            .tag(Tab.device)

            NavigationStack {
                WoundScopeSettingsDashboard(
                    patientCount: patientStore.patients.count,
                    measurementCount: logManager.items.count,
                    onShowLogs: { showMeasurementLog = true }
                )
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(Tab.settings)
        }
    }

    private func startCapture(for patient: WoundScopePatient?) {
        capturePatient = patient
        showCapture = true
    }

    private func synchronizePatientsFromMeasurements() {
        let names = Set(logManager.items.compactMap { measurement -> String? in
            guard measurement.patientID == nil else { return nil }
            guard let name = measurement.patientName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty,
                  name.caseInsensitiveCompare("New Patient") != .orderedSame else {
                return nil
            }
            return name
        })

        for name in names {
            guard patientStore.patient(named: name) == nil else { continue }
            var profile = PatientProfile()
            profile.name = name
            patientStore.add(from: profile)
        }
    }
}

// MARK: - Home

private struct WoundScopeHomeView: View {
    let mode: WoundAppMode
    let patients: [WoundScopePatient]
    let measurements: [SavedMeasurement]
    let onCapture: () -> Void
    let onNewPatient: () -> Void
    let onImportPhoto: () -> Void
    let onShowLogs: () -> Void
    let onShowPatients: () -> Void
    let onCapturePatient: (WoundScopePatient) -> Void

    private var woundCount: Int {
        Set(measurements.map { item in
            [item.patientName ?? "", item.laterality ?? "", item.bodyArea ?? ""].joined(separator: "|")
        }).count
    }

    private var thisWeekCount: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
        return measurements.filter { $0.date >= cutoff }.count
    }

    private var severeCount: Int {
        measurements.filter { severity(for: $0) >= 15 }.count
    }

    private var reviewCount: Int {
        measurements.filter { severity(for: $0) >= 12 }.count
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

                Text("Developed by Mitchell Liu")
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
                    Image(systemName: "waveform.path.ecg.rectangle.fill")
                        .foregroundStyle(mode.wsPrimary)
                    Text("WoundScope")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(WSTheme.Palette.ink)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: WSTheme.Space.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.caption)
                    .foregroundStyle(WSTheme.Palette.secondary)
                Text("Capture or review")
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
            WSStatTile(title: "Severe", value: "\(severeCount)", systemImage: "exclamationmark.octagon.fill", color: severeCount > 0 ? .red : WSTheme.Palette.secondary)
            WSStatTile(title: "Needs review", value: "\(reviewCount)", systemImage: "stethoscope", color: reviewCount > 0 ? .orange : WSTheme.Palette.secondary)
        }
    }

    private var woundStats: some View {
        HStack(spacing: WSTheme.Space.sm) {
            WSStatTile(title: "Active", value: "\(woundCount)", systemImage: "bandage.fill", color: mode.wsPrimary)
            WSStatTile(title: "This week", value: "\(thisWeekCount)", systemImage: "calendar", color: .green)
            WSStatTile(title: "Needs review", value: "\(reviewCount)", systemImage: "exclamationmark.triangle.fill", color: reviewCount > 0 ? .orange : WSTheme.Palette.secondary)
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
                    Text("New capture")
                        .font(.title3.weight(.bold))
                    Text("LiDAR scan + analysis")
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
        .accessibilityHint("Opens the guided intake before the LiDAR scanner")
    }

    private var quickActions: some View {
        HStack(spacing: WSTheme.Space.md) {
            quickAction(icon: "person.crop.circle.badge.plus", title: "New patient", action: onNewPatient)
            quickAction(icon: "photo.on.rectangle", title: "Import photo", action: onImportPhoto)
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
                Text(title)
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
                                        .fill(WSTier(severity: severity(for: item)).color.opacity(0.14))
                                    Image(systemName: "bandage.fill")
                                        .font(.system(size: 30))
                                        .foregroundStyle(WSTier(severity: severity(for: item)).color)
                                }
                                .frame(width: 112, height: 112)

                                Text(item.patientName.nilIfBlank ?? "Unassigned")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(WSTheme.Palette.ink)
                                    .lineLimit(1)
                                Text(item.date.formatted(.relative(presentation: .named)))
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
                Button("View all", action: onShowPatients)
                    .font(.subheadline.weight(.semibold))
            }

            if patients.isEmpty {
                VStack(spacing: WSTheme.Space.md) {
                    Image(systemName: "person.crop.circle.dashed")
                        .font(.system(size: 34))
                        .foregroundStyle(mode.wsPrimary)
                    Text("No patients yet")
                        .font(.headline)
                    Text("Add a patient first, or start a capture and assign one during intake.")
                        .font(.subheadline)
                        .foregroundStyle(WSTheme.Palette.secondary)
                        .multilineTextAlignment(.center)
                    Button("Add patient", action: onNewPatient)
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
                                    Text(patientSubtitle(patient))
                                        .font(.caption)
                                        .foregroundStyle(WSTheme.Palette.secondary)
                                }
                                Spacer()
                                if let mostRecent = measurements(for: patient).first {
                                    WSTierBadge(tier: WSTier(severity: severity(for: mostRecent)), compact: true)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(WSTheme.Palette.secondary)
                            }
                            .wsCard()
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows this patient's wound history")
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

    private func measurements(for patient: WoundScopePatient) -> [SavedMeasurement] {
        measurements
            .filter { measurement in
                if let patientID = measurement.patientID {
                    return patientID == patient.id
                }
                return measurement.patientName?.caseInsensitiveCompare(patient.displayName) == .orderedSame
            }
            .sorted { $0.date > $1.date }
    }

    private func patientSubtitle(_ patient: WoundScopePatient) -> String {
        let entries = measurements(for: patient)
        guard let latest = entries.first else {
            return "Added \(patient.createdAt.formatted(date: .abbreviated, time: .omitted))"
        }
        let woundKeys = Set(entries.map { "\($0.laterality ?? "")|\($0.bodyArea ?? "")" })
        return "\(woundKeys.count) wound\(woundKeys.count == 1 ? "" : "s") · \(latest.date.formatted(.relative(presentation: .named)))"
    }
}

// MARK: - Device status

private struct WoundScopeDeviceView: View {
    let onStartCapture: () -> Void

    private var supportsLiDAR: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
            && ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WSTheme.Space.lg) {
                Text("Device")
                    .font(.largeTitle.bold())

                HStack(spacing: WSTheme.Space.md) {
                    Image(systemName: supportsLiDAR ? "sensor.fill" : "sensor")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(supportsLiDAR ? .green : .orange)
                        .frame(width: 58, height: 58)
                        .background((supportsLiDAR ? Color.green : Color.orange).opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(supportsLiDAR ? "LiDAR ready" : "LiDAR unavailable")
                            .font(.title3.weight(.bold))
                        Label(
                            supportsLiDAR ? "Scene depth and mesh reconstruction supported" : "Use a LiDAR-capable iPhone Pro or iPad Pro",
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

                WSPrimaryButton(
                    title: supportsLiDAR ? "Start LiDAR capture" : "Open capture preview",
                    icon: "viewfinder",
                    action: onStartCapture
                )

                Text("Measurement accuracy depends on lighting, distance, angle, motion, and visible wound boundaries. Review every result before clinical use.")
                    .font(.caption)
                    .foregroundStyle(WSTheme.Palette.secondary)
                    .padding(.horizontal, WSTheme.Space.sm)
            }
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
            .padding(WSTheme.Space.lg)
        }
        .background(WSTheme.Palette.paper.ignoresSafeArea())
        .navigationTitle("Device")
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
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(WSTheme.Palette.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - Settings

private struct WoundScopeSettingsDashboard: View {
    let patientCount: Int
    let measurementCount: Int
    let onShowLogs: () -> Void

    @AppStorage("woundAppMode") private var modeRaw = WoundAppMode.publicPatient.rawValue
    @AppStorage("homeAppearanceMode") private var appearanceRaw = HomeAppearanceMode.light.rawValue
    @AppStorage("woundAnalysisProvider") private var providerRaw = WoundAnalysisProvider.onDevice.rawValue
    @AppStorage("offlineFriendlyMode") private var offlineFriendlyMode = true
    @AppStorage("researchUsageConsent") private var researchUsageConsent = false
    @AppStorage("woundServerBaseURL") private var baseURL = ""

    private var mode: WoundAppMode {
        WoundAppMode(rawValue: modeRaw) ?? .publicPatient
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WSTheme.Space.lg) {
                appHeader
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
        .navigationTitle("Settings")
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
                Text("WoundScope").font(.title3.bold())
                Text("On-device wound measurement")
                    .font(.caption)
                    .foregroundStyle(WSTheme.Palette.secondary)
            }
            Spacer()
            WSModeChip(mode: mode)
        }
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: WSTheme.Space.md) {
            WSSectionLabel("Mode")
            Picker("Care mode", selection: $modeRaw) {
                ForEach(WoundAppMode.allCases) { option in
                    Text(option.displayName).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
            Text(mode.shortDetail)
                .font(.caption)
                .foregroundStyle(WSTheme.Palette.secondary)
            Divider()
            Picker("Appearance", selection: $appearanceRaw) {
                ForEach(HomeAppearanceMode.allCases) { option in
                    Label(option.rawValue, systemImage: option.systemImage).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
        }
        .wsCard()
    }

    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: WSTheme.Space.md) {
            WSSectionLabel("Wound AI")
            Picker("Processing", selection: $providerRaw) {
                ForEach(WoundAnalysisProvider.allCases) { provider in
                    Text(provider.title).tag(provider.rawValue)
                }
            }
            .pickerStyle(.segmented)

            NavigationLink {
                WoundAIModelView()
            } label: {
                settingsRow(icon: "brain.head.profile", title: "Models & privacy", value: "Manage")
            }
            .buttonStyle(.plain)

            if providerRaw == WoundAnalysisProvider.legacyRemote.rawValue {
                TextField("Legacy server URL", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
            }

            Text(providerRaw == WoundAnalysisProvider.onDevice.rawValue
                 ? "Image analysis stays on this device when the selected model is installed."
                 : "Legacy server processing sends the selected image to the configured endpoint.")
                .font(.caption)
                .foregroundStyle(WSTheme.Palette.secondary)
        }
        .wsCard()
    }

    private var measurementCard: some View {
        VStack(alignment: .leading, spacing: WSTheme.Space.md) {
            WSSectionLabel("Measurement")
            Toggle("Offline-friendly LiDAR measurement", isOn: $offlineFriendlyMode)
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
            Toggle("Allow de-identified usage data for research", isOn: $researchUsageConsent)
            Text("Research consent is optional and can be changed at any time. Wound images are not included by this setting.")
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
            Text(title)
                .foregroundStyle(WSTheme.Palette.ink)
            Spacer()
            Text(value)
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

private struct WoundScopeOnboardingView: View {
    @Binding var modeRaw: String
    @Binding var researchConsent: Bool
    let onFinish: () -> Void

    @State private var page = 0
    @State private var measurementConsent = false

    private var mode: WoundAppMode {
        WoundAppMode(rawValue: modeRaw) ?? .publicPatient
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [WSTheme.Palette.paper, mode.wsSoft],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: WSTheme.Space.lg) {
                HStack(spacing: 7) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(index <= page ? mode.wsPrimary : WSTheme.Palette.hairline)
                            .frame(width: index == page ? 34 : 12, height: 7)
                            .animation(.spring(response: 0.35), value: page)
                    }
                }

                TabView(selection: $page) {
                    onboardingPage(
                        icon: "waveform.path.ecg.rectangle.fill",
                        title: "Clearer wound tracking",
                        message: "WoundScope combines guided documentation with your device's real LiDAR depth and mesh data.",
                        bullets: ["Repeatable measurements", "Patient and wound history", "Clinician review remains essential"]
                    )
                    .tag(0)

                    onboardingPage(
                        icon: "lock.shield.fill",
                        title: "Designed for privacy",
                        message: "LiDAR measurement works on device. Image analysis can stay local when an on-device model is installed.",
                        bullets: ["No account required", "Explicit sharing only", "Research use is optional"]
                    )
                    .tag(1)

                    rolePage
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                if page < 2 {
                    WSPrimaryButton(title: "Continue", icon: "arrow.right") {
                        withAnimation { page += 1 }
                    }
                } else {
                    WSPrimaryButton(title: "Start using WoundScope", icon: "checkmark") {
                        onFinish()
                    }
                    .disabled(!measurementConsent)
                }
            }
            .frame(maxWidth: 620)
            .padding(WSTheme.Space.xl)
        }
    }

    private func onboardingPage(icon: String, title: String, message: String, bullets: [String]) -> some View {
        VStack(spacing: WSTheme.Space.lg) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 112, height: 112)
                .background(mode.wsGradient, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: mode.wsPrimary.opacity(0.32), radius: 24, x: 0, y: 13)
            Text(title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.body)
                .foregroundStyle(WSTheme.Palette.secondary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: WSTheme.Space.md) {
                ForEach(bullets, id: \.self) { bullet in
                    Label(bullet, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(WSTheme.Palette.ink)
                }
            }
            .frame(maxWidth: 420, alignment: .leading)
            .wsCard()
            Spacer()
        }
    }

    private var rolePage: some View {
        ScrollView {
            VStack(spacing: WSTheme.Space.lg) {
                Image(systemName: "person.2.badge.gearshape.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(mode.wsPrimary)
                Text("Choose your workspace")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("You can change this later in Settings.")
                    .foregroundStyle(WSTheme.Palette.secondary)

                Picker("Workspace", selection: $modeRaw) {
                    ForEach(WoundAppMode.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: WSTheme.Space.md) {
                    Toggle("I agree to capture and store wound measurements on this device.", isOn: $measurementConsent)
                    Divider()
                    Toggle("Allow de-identified usage data to support research.", isOn: $researchConsent)
                }
                .wsCard()

                Text("WoundScope is a documentation and measurement aid. It does not replace clinical judgment, diagnosis, or urgent medical care.")
                    .font(.caption)
                    .foregroundStyle(WSTheme.Palette.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, WSTheme.Space.lg)
        }
    }
}

private struct WoundScopePrivacyCover: View {
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

private struct WoundScopeQuickPatientSheet: View {
    @ObservedObject var store: WoundScopePatientStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var mrn = ""
    @State private var age = ""
    @State private var height = ""
    @State private var weight = ""
    @State private var genderRaw = PatientGender.other.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section("Patient") {
                    TextField("Name or pseudonym", text: $name)
                    TextField("MRN / PID (optional)", text: $mrn)
                    TextField("Age", text: $age).keyboardType(.numberPad)
                    Picker("Gender", selection: $genderRaw) {
                        ForEach(PatientGender.allCases) { gender in
                            Text(gender.rawValue).tag(gender.rawValue)
                        }
                    }
                }
                Section("Optional measurements") {
                    TextField("Height", text: $height)
                    TextField("Weight", text: $weight)
                }
            }
            .navigationTitle("New Patient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        var profile = PatientProfile()
        profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.mrnOrPID = mrn.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.age = age
        profile.height = height
        profile.weight = weight
        profile.gender = PatientGender(rawValue: genderRaw) ?? .other
        store.ensure(from: profile)
        dismiss()
    }
}

private struct WSSectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(WSTheme.Palette.tertiary)
    }
}

private func severity(for measurement: SavedMeasurement) -> Int {
    measurement.severity ?? WoundSeverityScorer.score(area: measurement.area, volume: measurement.volume)
}

private extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
