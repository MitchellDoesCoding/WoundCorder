import AVFoundation
import SwiftUI
import UIKit

/// Collects wound context before handing the session to the existing LiDAR scanner.
///
/// This flow intentionally owns no capture or measurement behavior. `ContentView` remains
/// the single source of truth for scanning, segmentation, and LiDAR measurements.
struct WoundCorderCaptureFlow: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    @ObservedObject private var patientStore: WoundCorderPatientStore
    @EnvironmentObject private var logManager: MeasurementLogManager
    @Environment(\.dismiss) private var dismiss

    @AppStorage("woundAppMode") private var selectedModeRaw = WoundAppMode.publicPatient.rawValue

    var photoOnly: Bool = false
    @State private var comorbidities = ComorbidityChecklist()
    @State private var step: WSCFCaptureStep
    @State private var selectedPatientID: UUID?
    @State private var isCreatingNewPatient: Bool
    @State private var profile: PatientProfile
    @State private var bodyArea: BodyArea?
    @State private var laterality: Laterality?
    @State private var hasConfirmedLaterality = false
    @State private var contexts: Set<WoundContext> = []
    @State private var dateWounded: WoundedDateOption = .unknown
    @State private var notes = ""
    @State private var medicineEntries: [String] = []
    @State private var medicineDraft = ""

    @State private var scannerProfile = PatientProfile()
    @State private var scannerPatientID: UUID?
    @State private var scannerIntake = WoundIntakeData()
    @State private var isPresentingScanner = false
    @State private var didCompleteMeasurement = false
    @State private var isRequestingCameraPermission = false
    @State private var isShowingCameraPermissionAlert = false

    init(
        patientStore: WoundCorderPatientStore,
        prefilledPatient: WoundCorderPatient? = nil,
        photoOnly: Bool = false
    ) {
        self.photoOnly = photoOnly
        _patientStore = ObservedObject(wrappedValue: patientStore)
        _selectedPatientID = State(initialValue: prefilledPatient?.id)
        _profile = State(initialValue: prefilledPatient?.profile ?? PatientProfile())
        _isCreatingNewPatient = State(
            initialValue: prefilledPatient == nil && patientStore.patients.isEmpty
        )
        _step = State(initialValue: prefilledPatient == nil ? .patient : .details)
        _bodyArea = State(initialValue: nil)
        _laterality = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                WSCFProgressHeader(step: step, accent: mode.wsPrimary)

                Divider()

                ScrollView {
                    stepContent
                        .frame(maxWidth: 680, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, WSTheme.Space.md)
                        .padding(.vertical, WSTheme.Space.lg)
                }
                .scrollDismissesKeyboard(.interactively)

                Divider()
                navigationFooter
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(WoundL10n.text(step.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(WoundL10n.text("Close")) { dismiss() }
                        .accessibilityHint(WoundL10n.text("Closes wound intake"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    WSModeChip(mode: mode)
                        .accessibilityLabel(WoundL10n.text("\(mode.displayName) mode"))
                }
            }
        }
        .tint(mode.wsPrimary)
        .wsAppMode(mode)
        .onChange(of: laterality) { _, _ in
            hasConfirmedLaterality = false
        }
        .onChange(of: bodyArea) { _, _ in
            hasConfirmedLaterality = false
        }
        .safeAreaInset(edge: .top) {
            if let error = patientStore.storageError { WoundStorageRecoveryView(message: error, canRestore: patientStore.canRestorePrevious, reload: patientStore.reload, restore: patientStore.restorePrevious).padding().background(.regularMaterial) }
        }
        .fullScreenCover(isPresented: $isPresentingScanner, onDismiss: {
            if didCompleteMeasurement {
                dismiss()
            }
        }) {
            if photoOnly {
                ARCameraTabView(patientID: scannerPatientID, patientName: scannerProfile.displayName, patientProfile: scannerProfile, woundIntake: scannerIntake)
                    .environmentObject(logManager)
            } else {
            ContentView(
                patientID: scannerPatientID,
                patientProfile: scannerProfile,
                woundIntake: scannerIntake,
                onMeasurementSaved: {
                    didCompleteMeasurement = true
                }
            )
                .environmentObject(logManager)
                .toolbar(.hidden, for: .tabBar)
                .statusBarHidden(true)
            }
        }
        .alert(WoundL10n.text("Camera Access Needed"), isPresented: $isShowingCameraPermissionAlert) {
            Button(WoundL10n.text("Not Now"), role: .cancel) {}
            Button(WoundL10n.text("Open Settings")) {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
        } message: {
            Text(WoundL10n.text("Enable Camera access for WoundCorder in Settings, then return here to start the LiDAR scan."))
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .patient:
            WSCFPatientStep(
                patients: patientStore.patients,
                selectedPatientID: selectedPatientID,
                isCreatingNewPatient: isCreatingNewPatient,
                profile: $profile,
                accent: mode.wsPrimary,
                onSelectPatient: selectPatient,
                onCreateNew: beginNewPatient
            )

        case .location:
            WSCFLocationStep(
                bodyArea: $bodyArea,
                laterality: $laterality,
                accent: mode.wsPrimary
            )

        case .confirmLaterality:
            WSCFLateralityConfirmationStep(
                bodyArea: bodyArea,
                laterality: laterality,
                isConfirmed: $hasConfirmedLaterality,
                accent: mode.wsPrimary
            )

        case .details:
            VStack(spacing: 24) {
            ComorbidityChecklistFields(checklist: $comorbidities)
            WSCFDetailsStep(
                notes: $notes,
                medicineEntries: $medicineEntries,
                medicineDraft: $medicineDraft,
                accent: mode.wsPrimary,
                onAddMedicine: addMedicine
            )
            }

        case .review:
            WSCFReviewStep(
                profile: profile,
                bodyArea: bodyArea,
                laterality: laterality,
                contexts: contexts,
                dateWounded: dateWounded,
                notes: notes,
                medicineEntries: medicineEntries,
                accent: mode.wsPrimary,
                onEdit: { step = $0 }
            )
        }
    }

    private var navigationFooter: some View {
        VStack(spacing: WSTheme.Space.sm) {
            HStack(spacing: WSTheme.Space.sm) {
                if step != .patient {
                    WSSecondaryButton(title: "Back", icon: "chevron.left") {
                        goBack()
                    }
                }

                WSPrimaryButton(
                    title: step == .review ? (photoOnly ? "Take or choose a photo" : "Start wound scan") : "Continue",
                    icon: step == .review ? "viewfinder" : "arrow.right"
                ) {
                    advance()
                }
                .disabled(!canContinue)
                .opacity(canContinue ? 1 : 0.48)
            }
        }
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, WSTheme.Space.md)
        .padding(.vertical, WSTheme.Space.sm)
        .background(.bar)
    }

    private var mode: WoundAppMode {
        WoundAppMode(rawValue: selectedModeRaw) ?? .publicPatient
    }

    private var patientIsValid: Bool {
        !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && profile.validationMessage == nil
    }

    private var canContinue: Bool {
        switch step {
        case .patient:
            return patientIsValid && (isCreatingNewPatient || selectedPatientID != nil)
        case .location:
            return bodyArea != nil && laterality != nil
        case .confirmLaterality:
            return hasConfirmedLaterality
        case .details:
            return true
        case .review:
            return patientIsValid
                && bodyArea != nil
                && laterality != nil
                && hasConfirmedLaterality
                && !isRequestingCameraPermission
        }
    }

    private func selectPatient(_ patient: WoundCorderPatient) {
        selectedPatientID = patient.id
        profile = patient.profile
        isCreatingNewPatient = false
    }

    private func beginNewPatient() {
        selectedPatientID = nil
        profile = PatientProfile()
        isCreatingNewPatient = true
    }

    private func addMedicine() {
        let trimmed = medicineDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        medicineEntries.append(trimmed)
        medicineDraft = ""
    }

    private func advance() {
        guard canContinue else { return }

        if step == .review {
            launchScanner()
            return
        }

        guard let next = WSCFCaptureStep(rawValue: step.rawValue + 1) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            step = next
        }
    }

    private func goBack() {
        guard let previous = WSCFCaptureStep(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            step = previous
        }
    }

    private func launchScanner() {
        guard let bodyArea, let laterality else { return }

        if photoOnly {
            presentScanner(bodyArea: bodyArea, laterality: laterality)
            return // Photo selection remains usable when camera permission is denied.
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            presentScanner(bodyArea: bodyArea, laterality: laterality)

        case .notDetermined:
            guard !isRequestingCameraPermission else { return }
            isRequestingCameraPermission = true
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    isRequestingCameraPermission = false
                    if granted {
                        presentScanner(bodyArea: bodyArea, laterality: laterality)
                    } else {
                        isShowingCameraPermissionAlert = true
                    }
                }
            }

        case .denied, .restricted:
            isShowingCameraPermissionAlert = true

        @unknown default:
            isShowingCameraPermissionAlert = true
        }
    }

    private func presentScanner(bodyArea: BodyArea, laterality: Laterality) {

        // Persist the selected/entered patient before opening the scanner so measurements
        // and future sessions can resolve the same profile.
        let saved: WoundCorderPatient?
        if let selectedPatientID, !isCreatingNewPatient {
            saved = patientStore.update(id: selectedPatientID, from: profile)
        } else {
            saved = patientStore.ensure(from: profile)
        }
        guard let persistedPatient = saved else { return }
        selectedPatientID = persistedPatient.id
        profile = persistedPatient.profile

        var intake = WoundIntakeData()
        intake.bodyArea = bodyArea
        intake.laterality = laterality
        intake.comorbidities = comorbidities
        intake.contexts = contexts
        intake.dateWounded = dateWounded
        intake.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        intake.medicineEntries = medicineEntries

        scannerProfile = persistedPatient.profile
        scannerPatientID = persistedPatient.id
        scannerIntake = intake
        didCompleteMeasurement = false
        isPresentingScanner = true
    }
}

private enum WSCFCaptureStep: Int, CaseIterable, Identifiable {
    case patient
    case details
    case location
    case confirmLaterality
    case review

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .patient: return "Patient"
        case .location: return "Wound Location"
        case .confirmLaterality: return "Confirm Side"
        case .details: return "Your health"
        case .review: return "Review"
        }
    }

    var shortTitle: String {
        switch self {
        case .patient: return "Patient"
        case .location: return "Location"
        case .confirmLaterality: return "Side"
        case .details: return "Details"
        case .review: return "Review"
        }
    }
}

private struct WSCFProgressHeader: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let step: WSCFCaptureStep
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: WSTheme.Space.xs) {
            HStack {
                Text(WoundL10n.text("Step \(step.rawValue + 1) of \(WSCFCaptureStep.allCases.count)"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(WoundL10n.text(step.shortTitle))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
            }

            ProgressView(
                value: Double(step.rawValue + 1),
                total: Double(WSCFCaptureStep.allCases.count)
            )
            .tint(accent)
            .accessibilityLabel(WoundL10n.text("Intake progress"))
            .accessibilityValue(WoundL10n.text("Step \(step.rawValue + 1) of \(WSCFCaptureStep.allCases.count)"))
        }
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, WSTheme.Space.md)
        .padding(.vertical, WSTheme.Space.sm)
        .background(Color(.secondarySystemGroupedBackground))
    }
}

private struct WSCFPatientStep: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let patients: [WoundCorderPatient]
    let selectedPatientID: UUID?
    let isCreatingNewPatient: Bool
    @Binding var profile: PatientProfile
    let accent: Color
    let onSelectPatient: (WoundCorderPatient) -> Void
    let onCreateNew: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WSTheme.Space.lg) {
            WSCFStepIntroduction(
                title: "Who is this scan for?",
                detail: "Select an existing patient or create a profile for this wound record.",
                systemImage: "person.text.rectangle",
                accent: accent
            )

            if !patients.isEmpty {
                VStack(alignment: .leading, spacing: WSTheme.Space.sm) {
                    WSCFSectionLabel("Existing patients")

                    ForEach(patients) { patient in
                        Button {
                            onSelectPatient(patient)
                        } label: {
                            HStack(spacing: WSTheme.Space.sm) {
                                Text(WoundL10n.text(patient.initials))
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(accent)
                                    .frame(width: 42, height: 42)
                                    .background(accent.opacity(0.12), in: Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(patient.displayName)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    if !patient.mrnOrPID.isEmpty {
                                        Text(WoundL10n.text("ID: \(patient.mrnOrPID)"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: selectedPatientID == patient.id ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedPatientID == patient.id ? accent : .secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .wsCard(padding: WSTheme.Space.sm)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(selectedPatientID == patient.id ? .isSelected : [])
                    }
                }

                HStack {
                    Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
                    Text(WoundL10n.text("OR"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
                }

                WSSecondaryButton(title: "Create New Patient", icon: "person.badge.plus") {
                    onCreateNew()
                }
            }

            if isCreatingNewPatient {
                WSCFPatientForm(profile: $profile, accent: accent)
                    .wsCard()
            }
        }
    }
}

private struct WSCFPatientForm: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    @Binding var profile: PatientProfile
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: WSTheme.Space.md) {
            HStack(spacing: WSTheme.Space.sm) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .foregroundStyle(accent)
                Text(WoundL10n.text("New patient profile"))
                    .font(.headline)
            }

            WSCFLabeledField(label: "Full name", required: true) {
                TextField(WoundL10n.text("Patient name"), text: $profile.name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
            }

            WSCFLabeledField(label: "Medical record or patient ID") {
                TextField(WoundL10n.text("Optional"), text: $profile.mrnOrPID)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }

            HStack(alignment: .top, spacing: WSTheme.Space.sm) {
                WSCFLabeledField(label: "Age") {
                    TextField(WoundL10n.text("Years"), text: $profile.age)
                        .keyboardType(.numberPad)
                }

                WSCFLabeledField(label: "Gender") {
                    Picker(WoundL10n.text("Gender"), selection: $profile.gender) {
                        ForEach(PatientGender.allCases) { gender in
                            Text(WoundL10n.text(gender.displayName)).tag(gender)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            HStack(alignment: .top, spacing: WSTheme.Space.sm) {
                WSCFLabeledField(label: "Height (cm)") {
                    TextField(WoundL10n.text("Optional"), text: $profile.height)
                        .keyboardType(.decimalPad)
                }
                WSCFLabeledField(label: "Weight (kg)") {
                    TextField(WoundL10n.text("Optional"), text: $profile.weight)
                        .keyboardType(.decimalPad)
                }
            }

            if let message = profile.validationMessage { Text(WoundL10n.text(message)).foregroundStyle(.red).accessibilityLabel(WoundL10n.text(message)) }

            Text(WoundL10n.text("Only the patient name is required. You can complete the remaining details later."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WSCFLabeledField<Content: View>: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let label: String
    var required = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                Text(WoundL10n.text(label))
                if required {
                    Text(WoundL10n.text("Required"))
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            content
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WSCFLocationStep: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    @Binding var bodyArea: BodyArea?
    @Binding var laterality: Laterality?
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: WSTheme.Space.lg) {
            WSCFStepIntroduction(
                title: "Where is the wound?",
                detail: "Tap the diagram using the patient's left or right—not the side of the screen.",
                systemImage: "figure.stand",
                accent: accent
            )

            WSCFBodyDiagram(bodyArea: $bodyArea, laterality: $laterality, accent: accent)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
                .wsCard()

            VStack(alignment: .leading, spacing: WSTheme.Space.md) {
                WSCFSectionLabel("Detailed body region")

                ForEach(BodyArea.selectionGroups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(WoundL10n.text(group.title))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                            ForEach(group.areas) { area in
                                WSCFSelectionChip(
                                    title: area.rawValue,
                                    systemImage: area.systemImage,
                                    isSelected: bodyArea == area,
                                    accent: accent
                                ) {
                                    bodyArea = area
                                }
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: WSTheme.Space.sm) {
                WSCFSectionLabel("Patient side")
                HStack(spacing: WSTheme.Space.sm) {
                    WSCFLateralityButton(
                        side: .right,
                        isSelected: laterality == .right,
                        accent: accent
                    ) { laterality = .right }
                    WSCFLateralityButton(
                        side: .left,
                        isSelected: laterality == .left,
                        accent: accent
                    ) { laterality = .left }
                }
            }

            if let bodyArea, let laterality {
                Label(WoundL10n.text(
                    "Selected: Patient's \(laterality == .right ? "right" : "left") \(bodyArea.rawValue.lowercased())"),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
                .accessibilityLabel(WoundL10n.text("Selected patient's \(laterality == .right ? "right" : "left") \(bodyArea.rawValue)"))
            }
        }
    }
}

private struct WSCFBodyDiagram: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    @Binding var bodyArea: BodyArea?
    @Binding var laterality: Laterality?
    let accent: Color

    private let zones = WSCFDiagramZone.all

    var body: some View {
        VStack(spacing: WSTheme.Space.sm) {
            HStack {
                Text(WoundL10n.text("PATIENT'S RIGHT"))
                Spacer()
                Text(WoundL10n.text("PATIENT'S LEFT"))
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)

            GeometryReader { geometry in
                let size = geometry.size

                ZStack {
                    WSCFBodyFigure()
                        .fill(Color.secondary.opacity(0.11))
                        .overlay {
                            WSCFBodyFigure()
                                .stroke(Color.secondary.opacity(0.45), lineWidth: 1.5)
                        }

                    Path { path in
                        path.move(to: CGPoint(x: size.width / 2, y: 4))
                        path.addLine(to: CGPoint(x: size.width / 2, y: size.height - 4))
                    }
                    .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))

                    ZStack {
                        ForEach(zones) { zone in
                            let selected = bodyArea == zone.area && laterality == zone.side
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selected ? accent.opacity(0.34) : accent.opacity(0.035))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(
                                            selected ? accent : Color.secondary.opacity(0.18),
                                            lineWidth: selected ? 2 : 0.7
                                        )
                                }
                                .frame(width: zone.width * size.width, height: zone.height * size.height)
                                .position(x: zone.x * size.width, y: zone.y * size.height)
                        }
                    }
                    .mask(WSCFBodyFigure())
                    .allowsHitTesting(false)

                    ForEach(zones) { zone in
                        let selected = bodyArea == zone.area && laterality == zone.side
                        Text(WoundL10n.text(zone.diagramLabel))
                            .font(.system(size: 8, weight: selected ? .bold : .medium, design: .rounded))
                            .foregroundStyle(selected ? accent : Color.secondary.opacity(0.82))
                            .lineLimit(2)
                            .minimumScaleFactor(0.55)
                            .multilineTextAlignment(.center)
                            .frame(
                                width: max(22, zone.width * size.width - 4),
                                height: max(18, zone.height * size.height - 2)
                            )
                            .position(x: zone.x * size.width, y: zone.y * size.height)
                            .allowsHitTesting(false)
                    }

                    Text(WoundL10n.text("Neck"))
                        .font(.system(size: 7, weight: bodyArea == .neck ? .bold : .medium, design: .rounded))
                        .foregroundStyle(bodyArea == .neck ? accent : Color.secondary.opacity(0.82))
                        .position(x: size.width * 0.5, y: size.height * 0.14)
                        .allowsHitTesting(false)

                    Text(WoundL10n.text("R"))
                        .font(.caption.weight(.black))
                        .foregroundStyle(accent)
                        .position(x: 16, y: 14)
                        .accessibilityHidden(true)
                    Text(WoundL10n.text("L"))
                        .font(.caption.weight(.black))
                        .foregroundStyle(accent)
                        .position(x: size.width - 16, y: 14)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            selectZone(at: value.location, in: size)
                        }
                )
            }
            .aspectRatio(0.62, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(WoundL10n.text("Anterior body location diagram"))
            .accessibilityHint(WoundL10n.text("Tap a labeled region, or use the detailed body region buttons below."))

            Text(WoundL10n.text("Front view • screen sides are mirrored to match the patient"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func selectZone(at location: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let normalized = CGPoint(x: location.x / size.width, y: location.y / size.height)
        let exactMatches = zones.filter { $0.rect.contains(normalized) }

        let candidates: [WSCFDiagramZone]
        if !exactMatches.isEmpty {
            candidates = exactMatches
        } else {
            let minimumWidth = 44 / size.width
            let minimumHeight = 44 / size.height
            candidates = zones.filter { zone in
                let targetWidth = max(zone.rect.width, minimumWidth)
                let targetHeight = max(zone.rect.height, minimumHeight)
                let expanded = CGRect(
                    x: zone.rect.midX - targetWidth / 2,
                    y: zone.rect.midY - targetHeight / 2,
                    width: targetWidth,
                    height: targetHeight
                )
                return expanded.contains(normalized)
            }
        }

        guard let selected = candidates.min(by: { lhs, rhs in
            let lhsExact = lhs.rect.contains(normalized)
            let rhsExact = rhs.rect.contains(normalized)
            if lhsExact != rhsExact { return lhsExact }
            if lhsExact {
                return lhs.rect.width * lhs.rect.height < rhs.rect.width * rhs.rect.height
            }
            let lhsDistance = hypot(
                (lhs.x - normalized.x) * size.width,
                (lhs.y - normalized.y) * size.height
            )
            let rhsDistance = hypot(
                (rhs.x - normalized.x) * size.width,
                (rhs.y - normalized.y) * size.height
            )
            return lhsDistance < rhsDistance
        }) else { return }

        bodyArea = selected.area
        laterality = selected.side
    }
}

/// Normalized geometry shared by the visible silhouette and its interactive zones.
///
/// In an anterior (front-facing) view, the patient's right side is drawn on the
/// left side of the screen. Keeping these rectangles in one place prevents the
/// tappable regions from drifting away from the body as the diagram is resized.
private enum WSCFBodyGeometry {
    static let head = CGRect(x: 0.41, y: 0.015, width: 0.18, height: 0.105)
    static let neck = CGRect(x: 0.46, y: 0.115, width: 0.08, height: 0.05)
    static let torso = CGRect(x: 0.31, y: 0.155, width: 0.38, height: 0.37)

    static let rightShoulder = CGRect(x: 0.235, y: 0.165, width: 0.115, height: 0.10)
    static let leftShoulder = CGRect(x: 0.65, y: 0.165, width: 0.115, height: 0.10)
    static let rightArm = CGRect(x: 0.15, y: 0.215, width: 0.13, height: 0.395)
    static let leftArm = CGRect(x: 0.72, y: 0.215, width: 0.13, height: 0.395)
    static let rightHand = CGRect(x: 0.145, y: 0.595, width: 0.14, height: 0.075)
    static let leftHand = CGRect(x: 0.715, y: 0.595, width: 0.14, height: 0.075)

    static let rightLeg = CGRect(x: 0.32, y: 0.515, width: 0.15, height: 0.42)
    static let leftLeg = CGRect(x: 0.53, y: 0.515, width: 0.15, height: 0.42)

    static let rightFoot = CGRect(x: 0.285, y: 0.925, width: 0.185, height: 0.065)
    static let leftFoot = CGRect(x: 0.53, y: 0.925, width: 0.185, height: 0.065)

    static var rightHeadZone: CGRect { leadingHalf(of: head) }
    static var leftHeadZone: CGRect { trailingHalf(of: head) }
    static var rightNeckZone: CGRect { leadingHalf(of: neck) }
    static var leftNeckZone: CGRect { trailingHalf(of: neck) }

    static let rightUpperArmZone = CGRect(x: 0.15, y: 0.235, width: 0.13, height: 0.13)
    static let leftUpperArmZone = CGRect(x: 0.72, y: 0.235, width: 0.13, height: 0.13)
    static let rightElbowZone = CGRect(x: 0.15, y: 0.365, width: 0.13, height: 0.075)
    static let leftElbowZone = CGRect(x: 0.72, y: 0.365, width: 0.13, height: 0.075)
    static let rightForearmZone = CGRect(x: 0.15, y: 0.44, width: 0.13, height: 0.115)
    static let leftForearmZone = CGRect(x: 0.72, y: 0.44, width: 0.13, height: 0.115)
    static let rightWristZone = CGRect(x: 0.15, y: 0.555, width: 0.13, height: 0.055)
    static let leftWristZone = CGRect(x: 0.72, y: 0.555, width: 0.13, height: 0.055)

    static let chest = CGRect(x: 0.31, y: 0.155, width: 0.38, height: 0.175)
    static let abdomen = CGRect(x: 0.32, y: 0.33, width: 0.36, height: 0.12)
    static let hip = CGRect(x: 0.32, y: 0.45, width: 0.36, height: 0.075)
    static var rightChestZone: CGRect { leadingHalf(of: chest) }
    static var leftChestZone: CGRect { trailingHalf(of: chest) }
    static var rightAbdomenZone: CGRect { leadingHalf(of: abdomen) }
    static var leftAbdomenZone: CGRect { trailingHalf(of: abdomen) }
    static var rightHipZone: CGRect { leadingHalf(of: hip) }
    static var leftHipZone: CGRect { trailingHalf(of: hip) }

    static let rightThighZone = CGRect(x: 0.32, y: 0.525, width: 0.15, height: 0.17)
    static let leftThighZone = CGRect(x: 0.53, y: 0.525, width: 0.15, height: 0.17)
    static let rightKneeZone = CGRect(x: 0.32, y: 0.695, width: 0.15, height: 0.075)
    static let leftKneeZone = CGRect(x: 0.53, y: 0.695, width: 0.15, height: 0.075)
    static let rightLowerLegZone = CGRect(x: 0.32, y: 0.77, width: 0.15, height: 0.12)
    static let leftLowerLegZone = CGRect(x: 0.53, y: 0.77, width: 0.15, height: 0.12)
    static let rightAnkleZone = CGRect(x: 0.32, y: 0.89, width: 0.15, height: 0.045)
    static let leftAnkleZone = CGRect(x: 0.53, y: 0.89, width: 0.15, height: 0.045)

    static func scaled(_ normalizedRect: CGRect, in rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX + normalizedRect.minX * rect.width,
            y: rect.minY + normalizedRect.minY * rect.height,
            width: normalizedRect.width * rect.width,
            height: normalizedRect.height * rect.height
        )
    }

    private static func leadingHalf(of rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: rect.minY, width: rect.width / 2, height: rect.height)
    }

    private static func trailingHalf(of rect: CGRect) -> CGRect {
        CGRect(x: rect.midX, y: rect.minY, width: rect.width / 2, height: rect.height)
    }

}

private struct WSCFBodyFigure: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.addEllipse(in: WSCFBodyGeometry.scaled(WSCFBodyGeometry.head, in: rect))
        path.addRoundedRect(
            in: WSCFBodyGeometry.scaled(WSCFBodyGeometry.neck, in: rect),
            cornerSize: CGSize(width: 8, height: 8)
        )
        path.addRoundedRect(
            in: WSCFBodyGeometry.scaled(WSCFBodyGeometry.torso, in: rect),
            cornerSize: CGSize(width: 20, height: 20)
        )
        path.addRoundedRect(
            in: WSCFBodyGeometry.scaled(WSCFBodyGeometry.rightShoulder, in: rect),
            cornerSize: CGSize(width: 14, height: 14)
        )
        path.addRoundedRect(
            in: WSCFBodyGeometry.scaled(WSCFBodyGeometry.leftShoulder, in: rect),
            cornerSize: CGSize(width: 14, height: 14)
        )
        path.addRoundedRect(
            in: WSCFBodyGeometry.scaled(WSCFBodyGeometry.rightArm, in: rect),
            cornerSize: CGSize(width: 14, height: 14)
        )
        path.addRoundedRect(
            in: WSCFBodyGeometry.scaled(WSCFBodyGeometry.leftArm, in: rect),
            cornerSize: CGSize(width: 14, height: 14)
        )
        path.addRoundedRect(
            in: WSCFBodyGeometry.scaled(WSCFBodyGeometry.rightHand, in: rect),
            cornerSize: CGSize(width: 10, height: 10)
        )
        path.addRoundedRect(
            in: WSCFBodyGeometry.scaled(WSCFBodyGeometry.leftHand, in: rect),
            cornerSize: CGSize(width: 10, height: 10)
        )
        path.addRoundedRect(
            in: WSCFBodyGeometry.scaled(WSCFBodyGeometry.rightLeg, in: rect),
            cornerSize: CGSize(width: 14, height: 14)
        )
        path.addRoundedRect(
            in: WSCFBodyGeometry.scaled(WSCFBodyGeometry.leftLeg, in: rect),
            cornerSize: CGSize(width: 14, height: 14)
        )
        path.addRoundedRect(
            in: WSCFBodyGeometry.scaled(WSCFBodyGeometry.rightFoot, in: rect),
            cornerSize: CGSize(width: 8, height: 8)
        )
        path.addRoundedRect(
            in: WSCFBodyGeometry.scaled(WSCFBodyGeometry.leftFoot, in: rect),
            cornerSize: CGSize(width: 8, height: 8)
        )
        return path
    }
}

private struct WSCFDiagramZone: Identifiable {
    let id: String
    let area: BodyArea
    let side: Laterality
    let rect: CGRect
    let diagramLabel: String
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(id: String, area: BodyArea, side: Laterality, rect: CGRect, diagramLabel: String? = nil) {
        self.id = id
        self.area = area
        self.side = side
        self.rect = rect
        self.diagramLabel = diagramLabel ?? area.rawValue
        x = rect.midX
        y = rect.midY
        width = rect.width
        height = rect.height
    }

    static let all: [WSCFDiagramZone] = [
        // Front view: the patient's right is the screen's left.
        .init(id: "head-r", area: .head, side: .right, rect: WSCFBodyGeometry.rightHeadZone),
        .init(id: "head-l", area: .head, side: .left, rect: WSCFBodyGeometry.leftHeadZone),
        .init(id: "neck-r", area: .neck, side: .right, rect: WSCFBodyGeometry.rightNeckZone, diagramLabel: ""),
        .init(id: "neck-l", area: .neck, side: .left, rect: WSCFBodyGeometry.leftNeckZone, diagramLabel: ""),

        .init(id: "shoulder-r", area: .shoulder, side: .right, rect: WSCFBodyGeometry.rightShoulder, diagramLabel: "Shoulder"),
        .init(id: "shoulder-l", area: .shoulder, side: .left, rect: WSCFBodyGeometry.leftShoulder, diagramLabel: "Shoulder"),
        .init(id: "upper-arm-r", area: .upperArm, side: .right, rect: WSCFBodyGeometry.rightUpperArmZone, diagramLabel: "Upper\narm"),
        .init(id: "upper-arm-l", area: .upperArm, side: .left, rect: WSCFBodyGeometry.leftUpperArmZone, diagramLabel: "Upper\narm"),
        .init(id: "elbow-r", area: .elbow, side: .right, rect: WSCFBodyGeometry.rightElbowZone),
        .init(id: "elbow-l", area: .elbow, side: .left, rect: WSCFBodyGeometry.leftElbowZone),
        .init(id: "forearm-r", area: .forearm, side: .right, rect: WSCFBodyGeometry.rightForearmZone),
        .init(id: "forearm-l", area: .forearm, side: .left, rect: WSCFBodyGeometry.leftForearmZone),
        .init(id: "wrist-r", area: .wrist, side: .right, rect: WSCFBodyGeometry.rightWristZone),
        .init(id: "wrist-l", area: .wrist, side: .left, rect: WSCFBodyGeometry.leftWristZone),
        .init(id: "hand-r", area: .hand, side: .right, rect: WSCFBodyGeometry.rightHand),
        .init(id: "hand-l", area: .hand, side: .left, rect: WSCFBodyGeometry.leftHand),

        .init(id: "chest-r", area: .chest, side: .right, rect: WSCFBodyGeometry.rightChestZone),
        .init(id: "chest-l", area: .chest, side: .left, rect: WSCFBodyGeometry.leftChestZone),
        .init(id: "abdomen-r", area: .abdomen, side: .right, rect: WSCFBodyGeometry.rightAbdomenZone, diagramLabel: "Abd."),
        .init(id: "abdomen-l", area: .abdomen, side: .left, rect: WSCFBodyGeometry.leftAbdomenZone, diagramLabel: "Abd."),
        .init(id: "hip-r", area: .hip, side: .right, rect: WSCFBodyGeometry.rightHipZone, diagramLabel: "Hip"),
        .init(id: "hip-l", area: .hip, side: .left, rect: WSCFBodyGeometry.leftHipZone, diagramLabel: "Hip"),

        .init(id: "thigh-r", area: .thigh, side: .right, rect: WSCFBodyGeometry.rightThighZone),
        .init(id: "thigh-l", area: .thigh, side: .left, rect: WSCFBodyGeometry.leftThighZone),
        .init(id: "knee-r", area: .knee, side: .right, rect: WSCFBodyGeometry.rightKneeZone),
        .init(id: "knee-l", area: .knee, side: .left, rect: WSCFBodyGeometry.leftKneeZone),
        .init(id: "lower-leg-r", area: .lowerLeg, side: .right, rect: WSCFBodyGeometry.rightLowerLegZone, diagramLabel: "Lower\nleg"),
        .init(id: "lower-leg-l", area: .lowerLeg, side: .left, rect: WSCFBodyGeometry.leftLowerLegZone, diagramLabel: "Lower\nleg"),
        .init(id: "ankle-r", area: .ankle, side: .right, rect: WSCFBodyGeometry.rightAnkleZone),
        .init(id: "ankle-l", area: .ankle, side: .left, rect: WSCFBodyGeometry.leftAnkleZone),
        .init(id: "foot-r", area: .foot, side: .right, rect: WSCFBodyGeometry.rightFoot),
        .init(id: "foot-l", area: .foot, side: .left, rect: WSCFBodyGeometry.leftFoot)
    ]
}

private struct WSCFSelectionChip: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let title: String
    let systemImage: String
    let isSelected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                Text(WoundL10n.text(title))
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .background(isSelected ? accent : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? accent : Color.secondary.opacity(0.2), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct WSCFLateralityButton: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let side: Laterality
    let isSelected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(WoundL10n.text(side.rawValue))
                    .font(.title2.weight(.black))
                Text(WoundL10n.text("Patient's \(side == .right ? "right" : "left")"))
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(isSelected ? accent : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? accent : Color.secondary.opacity(0.2), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(WoundL10n.text("Patient's \(side == .right ? "right" : "left")"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct WSCFLateralityConfirmationStep: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let bodyArea: BodyArea?
    let laterality: Laterality?
    @Binding var isConfirmed: Bool
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: WSTheme.Space.lg) {
            WSCFStepIntroduction(
                title: "Confirm the patient's side",
                detail: "Camera previews and photos may appear mirrored. The side you confirm here becomes the source of truth for the wound record.",
                systemImage: "arrow.left.arrow.right",
                accent: accent
            )

            VStack(spacing: WSTheme.Space.md) {
                Text(WoundL10n.text(laterality?.rawValue ?? "—"))
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundStyle(accent)
                    .frame(width: 116, height: 116)
                    .background(accent.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)

                Text(WoundL10n.text(selectionTitle))
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(WoundL10n.text("The scanner and image analysis will not change this selection."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .wsCard()

            Button {
                isConfirmed.toggle()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isConfirmed ? "checkmark.square.fill" : "square")
                        .font(.title2)
                        .foregroundStyle(isConfirmed ? accent : .secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(WoundL10n.text("I confirm the patient side"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(WoundL10n.text("I verified this location from the patient's perspective."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .wsCard()
            .accessibilityLabel(WoundL10n.text("Confirm \(selectionTitle)"))
            .accessibilityValue(WoundL10n.text(isConfirmed ? "Confirmed" : "Not confirmed"))

            Label(WoundL10n.text(
                "If the side is incorrect, use Back and update the location before scanning."),
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var selectionTitle: String {
        guard let bodyArea, let laterality else { return "No location selected" }
        return "Patient's \(laterality == .right ? "right" : "left") \(bodyArea.rawValue.lowercased())"
    }
}

private struct WSCFDetailsStep: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    @Binding var notes: String
    @Binding var medicineEntries: [String]
    @Binding var medicineDraft: String
    let accent: Color
    let onAddMedicine: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WSTheme.Space.lg) {
            WSCFStepIntroduction(
                title: "Anything else to record?",
                detail: "Notes and medicines are optional. Add only details that are useful for this wound record.",
                systemImage: "note.text",
                accent: accent
            )

            VStack(alignment: .leading, spacing: WSTheme.Space.sm) {
                WSCFSectionLabel("Notes")
                ZStack(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text(WoundL10n.text("Duration, treatment, symptoms, or other context"))
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $notes)
                        .frame(minHeight: 130)
                        .scrollContentBackground(.hidden)
                        .accessibilityLabel(WoundL10n.text("Optional wound notes"))
                }
                .wsCard(padding: WSTheme.Space.sm)
            }

            VStack(alignment: .leading, spacing: WSTheme.Space.sm) {
                WSCFSectionLabel("Medicines or treatments")

                HStack(spacing: WSTheme.Space.sm) {
                    TextField(WoundL10n.text("Add a medicine or treatment"), text: $medicineDraft)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .onSubmit(onAddMedicine)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 48)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        }

                    Button(action: onAddMedicine) {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(accent, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(medicineDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel(WoundL10n.text("Add medicine or treatment"))
                }

                ForEach(Array(medicineEntries.enumerated()), id: \.offset) { index, entry in
                    HStack(spacing: WSTheme.Space.sm) {
                        Image(systemName: "pills")
                            .foregroundStyle(accent)
                        Text(entry)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(role: .destructive) {
                            medicineEntries.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(WoundL10n.text("Remove \(entry)"))
                    }
                    .wsCard(padding: WSTheme.Space.sm)
                }
            }
        }
    }
}

private struct WSCFReviewStep: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let profile: PatientProfile
    let bodyArea: BodyArea?
    let laterality: Laterality?
    let contexts: Set<WoundContext>
    let dateWounded: WoundedDateOption
    let notes: String
    let medicineEntries: [String]
    let accent: Color
    let onEdit: (WSCFCaptureStep) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WSTheme.Space.lg) {
            WSCFStepIntroduction(
                title: "Ready to scan",
                detail: "Review the wound record before opening the LiDAR measurement camera.",
                systemImage: "checklist",
                accent: accent
            )

            WSCFReviewSection(title: "Patient", editLabel: "Edit patient") {
                WSCFReviewRow(icon: "person", label: "Name", value: profile.displayName, accent: accent)
                if !profile.mrnOrPID.isEmpty {
                    WSCFReviewRow(icon: "number", label: "Patient ID", value: profile.mrnOrPID, accent: accent)
                }
            } onEdit: {
                onEdit(.patient)
            }

            WSCFReviewSection(title: "Wound", editLabel: "Edit location") {
                WSCFReviewRow(icon: "figure.stand", label: "Location", value: locationText, accent: accent)
            } onEdit: {
                onEdit(.location)
            }

            WSCFReviewSection(title: "Optional details", editLabel: "Edit details") {
                WSCFReviewRow(
                    icon: "note.text",
                    label: "Notes",
                    value: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "None" : notes,
                    accent: accent
                )
                WSCFReviewRow(
                    icon: "pills",
                    label: "Medicines",
                    value: medicineEntries.isEmpty ? "None" : medicineEntries.joined(separator: ", "),
                    accent: accent
                )
            } onEdit: {
                onEdit(.details)
            }

            HStack(alignment: .top, spacing: WSTheme.Space.sm) {
                Image(systemName: "viewfinder.circle.fill")
                    .font(.title2)
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(WoundL10n.text("The existing LiDAR scanner opens next"))
                        .font(.headline)
                    Text(WoundL10n.text("Patient and wound details are passed into the scan record. Measurement and depth calculations continue to use the app's existing capture engine."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .wsCard()
        }
    }

    private var locationText: String {
        guard let bodyArea, let laterality else { return "Not selected" }
        return "Patient's \(laterality == .right ? "right" : "left") \(bodyArea.rawValue.lowercased())"
    }

    private var contextText: String {
        guard !contexts.isEmpty else { return "Not specified" }
        return contexts.map(\.rawValue).sorted().joined(separator: ", ")
    }
}

private struct WSCFReviewSection<Content: View>: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let title: String
    let editLabel: String
    @ViewBuilder let content: Content
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WSTheme.Space.sm) {
            HStack {
                Text(WoundL10n.text(title))
                    .font(.headline)
                Spacer()
                Button(WoundL10n.text("Edit"), action: onEdit)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityLabel(WoundL10n.text(editLabel))
            }

            Divider()
            content
        }
        .wsCard()
    }
}

private struct WSCFReviewRow: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let icon: String
    let label: String
    let value: String
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: WSTheme.Space.sm) {
            Image(systemName: icon)
                .foregroundStyle(accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(WoundL10n.text(label))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(WoundL10n.text(value))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WSCFStepIntroduction: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let title: String
    let detail: String
    let systemImage: String
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: WSTheme.Space.sm) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 48, height: 48)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text(WoundL10n.text(title))
                    .font(.title2.weight(.bold))
                Text(WoundL10n.text(detail))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WSCFSectionLabel: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(WoundL10n.text(title).uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.7)
            .foregroundStyle(.secondary)
    }
}
