import SwiftUI

private enum ManualSelectionPhase: Equatable {
    case rim
    case bed

    var stepText: String { self == .rim ? "Step 1 of 2" : "Step 2 of 2" }
    var title: String { self == .rim ? "Wound edge" : "Depth edge" }
    var primaryTitle: String { self == .rim ? "Next: Depth" : "Finish" }
    var symbol: String { self == .rim ? "circle.dashed" : "circle.circle" }
}

private enum AutomaticMeasurementPhase: Equatable {
    case ready
    case mapping
    case awaitingConfirmation
    case capturing
    case finalizing
    case complete
    case failed
}

struct ContentView: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let patientID: UUID?
    let patientProfile: PatientProfile
    let woundIntake: WoundIntakeData
    let onMeasurementSaved: () -> Void

    @State private var notificationScope = NSObject()
    @StateObject private var metricsManager = MetricsManager()
    @EnvironmentObject private var logManager: MeasurementLogManager

    @State private var topOutlinePoints: [SIMD3<Float>] = []
    @State private var bottomOutlinePoints: [SIMD3<Float>] = []
    @State private var selectedDepthPoint: SIMD3<Float>?
    @State private var isDetecting = false
    @State private var showManualControls = false
    @State private var scanQuality: ScanQuality = .waiting
    @State private var isPreliminary = true
    @State private var latestEstimateIsPreliminary = true
    @State private var isMeasurementFinalized = false
    @State private var hasSavedMeasurement = false
    @State private var isShowingSaveConfirmation = false
    @State private var isShowingSaveSuccess = false
    @State private var measurementID = UUID()
    @State private var measurementCompletedAt: Date?
    @State private var analysisContext: WoundAnalysisContext?
    @State private var capturedMeasurement: WoundAnalysisContext?
    @State private var showingAnalysis = false
    @State private var showingMeasurementDetails = false
    @State private var confirmSaveAfterDetails = false
    @State private var scanInstruction = "Point the camera at the wound."
    @State private var scanProgress: Double = 0
    @State private var segmentationVolumeApplied = false
    @State private var volumeSourceText = "LiDAR mesh/depth pending"
    @State private var manualPhase: ManualSelectionPhase = .rim
    @State private var manualPointCount = 0
    @State private var manualCanFinish = false
    @State private var manualCanUndo = false
    @State private var manualHasDetectedSeed = false
    @State private var manualValidationMessage = ""
    @State private var automaticPhase: AutomaticMeasurementPhase = .ready
    @State private var canConfirmWound = false
    @State private var canFinishPointCapture = false

    @Environment(\.dismiss) private var dismiss

    private let autoDetectFinishedNotification = NotificationCenter.default.publisher(for: Notification.Name("AutoDetectionDidFinish"))
    private let liDARScanStatusNotification = NotificationCenter.default.publisher(for: Notification.Name("LiDARScanStatusDidUpdate"))
    private let metricsUpdatedNotification = NotificationCenter.default.publisher(for: Notification.Name("MetricsUpdated"))
    private let manualOutlineStateNotification = NotificationCenter.default.publisher(for: Notification.Name("ManualOutlineStateDidUpdate"))

    init(
        patientID: UUID? = nil,
        patientProfile: PatientProfile = PatientProfile(),
        woundIntake: WoundIntakeData = WoundIntakeData(),
        onMeasurementSaved: @escaping () -> Void = {}
    ) {
        self.patientID = patientID
        self.patientProfile = patientProfile
        self.woundIntake = woundIntake
        self.onMeasurementSaved = onMeasurementSaved
    }

    var body: some View {
        ZStack {
            ARViewContainer(
                topOutlinePoints: $topOutlinePoints,
                bottomOutlinePoints: $bottomOutlinePoints,
                metricsManager: metricsManager,
                selectedDepthPoint: $selectedDepthPoint,
                onMeasurementState: handleMeasurementState,
                notificationScope: notificationScope
            )
            .ignoresSafeArea()
            .onAppear(perform: configureScan)
            .onReceive(autoDetectFinishedNotification) { notification in
                guard (notification.object as? NSObject) === notificationScope else { return }
                applyAutoDetection(notification)
            }
            .onReceive(liDARScanStatusNotification) { notification in
                guard (notification.object as? NSObject) === notificationScope else { return }
                applyLiDARScanStatus(notification)
            }
            .onReceive(metricsUpdatedNotification) { notification in
                guard (notification.object as? NSObject) === notificationScope else { return }
                applyMetricsUpdate(notification)
            }
            .onReceive(manualOutlineStateNotification) { notification in
                guard (notification.object as? NSObject) === notificationScope else { return }
                applyManualOutlineState(notification)
            }

            VStack(spacing: 0) {
                if let error = logManager.storageError {
                    WoundStorageRecoveryView(message: error, canRestore: logManager.canRestorePrevious, reload: logManager.reload, restore: logManager.restorePrevious).padding().background(.regularMaterial)
                }
                scanHeader
                    .padding(.horizontal, 14)
                    .padding(.top, 12)

                Spacer()

                LiDARScanGuidancePanel(
                    instruction: scanInstruction,
                    progress: scanProgress,
                    hasSegmentation: hasSegmentation,
                    // Live values are useful feedback, but the Measure step is not
                    // complete until the AR pipeline has finalized its consensus.
                    hasMeasurement: isMeasurementFinalized,
                    isScanning: isDetecting,
                    automaticPhase: automaticPhase
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

                if automaticPhase == .complete || isMeasurementFinalized {
                    completedMeasurementCard
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }

                Button {
                    continueToAnalysis()
                } label: {
                    Label(WoundL10n.text(canAttachMeasurements ? "Continue to AI with measurements" :
                          (automaticPhase == .finalizing ? "Finalizing measurements…" :
                           (automaticPhase == .complete ? "Continue to AI without measurements" : "Skip measurement · Go to AI"))),
                          systemImage: canAttachMeasurements ? "checkmark.circle.fill" : "arrow.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(automaticPhase == .finalizing)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

                if !showManualControls && !canAttachMeasurements {
                ScanControlsBar(
                    isDetecting: isDetecting,
                    automaticPhase: automaticPhase,
                    canConfirmWound: canConfirmWound,
                    canFinishPointCapture: canFinishPointCapture,
                    onStartScan: startLiDARScan,
                    onConfirmWound: confirmMappedWound,
                    onFinishCapture: finishPointCapture,
                    onCorrect: startGuidedManualMeasurement
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 18)
                }

                if showManualControls {
                    Button(action: startLiDARScan) {
                        Label(WoundL10n.text("Switch to Auto Detect"), systemImage: "viewfinder")
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(WoundL10n.text("Discards the current trace and starts automatic wound detection"))
                    ManualRefinementBar(
                        phase: manualPhase,
                        pointCount: manualPointCount,
                        canFinish: manualCanFinish,
                        canUndo: manualCanUndo,
                        hasDetectedSeed: manualHasDetectedSeed,
                        onUndo: undoManualMeasurement,
                        onBack: returnToManualRim,
                        onFinish: finishManualMeasurement,
                        onClear: clearManualMeasurement
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: $showingMeasurementDetails, onDismiss: {
            if confirmSaveAfterDetails {
                confirmSaveAfterDetails = false
                isShowingSaveConfirmation = true
            }
        }) {
            NavigationStack {
                ScrollView {
                    ScanResultsPanel(
                        metrics: displayedMetrics, depthCM: estimatedDepthCM,
                        scanQuality: scanQuality, isPreliminary: isPreliminary,
                        segmentationVolumeApplied: segmentationVolumeApplied,
                        volumeSourceText: volumeSourceText, patientName: patientProfile.displayName,
                        canSave: hasMeasurement && isMeasurementFinalized,
                        isSaved: hasSavedMeasurement, shareText: shareSummary,
                        onSave: {
                            confirmSaveAfterDetails = true
                            showingMeasurementDetails = false
                        }
                    ).padding()
                }
                .navigationTitle(WoundL10n.text("Measurement"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button(WoundL10n.text("Done")) { showingMeasurementDetails = false }
                } }
            }
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showingAnalysis) {
            ARCameraTabView(onFinish: saveMeasurementBeforeLeaving, measurementContext: analysisContext, patientID: patientID, patientName: patientProfile.displayName, patientProfile: patientProfile, woundIntake: woundIntake)
                .environmentObject(logManager)
        }
        .onChange(of: isMeasurementFinalized) { _, finalized in
            if finalized { measurementCompletedAt = Date() }
            else { measurementCompletedAt = nil; measurementID = UUID() }
        }
        .statusBarHidden(true)
        .confirmationDialog(WoundL10n.text(
            "Confirm this measurement?"),
            isPresented: $isShowingSaveConfirmation,
            titleVisibility: .visible
        ) {
            Button(WoundL10n.text("Save to \(patientProfile.displayName)")) {
                saveMeasurement()
            }
            Button(WoundL10n.text("Cancel"), role: .cancel) {}
        } message: {
            Text(WoundL10n.text(
                String(
                    format: "Area %.2f cm² • Volume %.2f cm³\n%@ %@",
                    displayedMetrics.area,
                    displayedMetrics.volume,
                    woundIntake.laterality.rawValue,
                    woundIntake.bodyArea.rawValue
                )
            ))
        }
        .alert(WoundL10n.text("Measurement Saved"), isPresented: $isShowingSaveSuccess) {
            Button(WoundL10n.text("Continue to AI with measurements")) { continueToAnalysis() }
            Button(WoundL10n.text("Done")) {
                onMeasurementSaved()
                dismiss()
            }
        } message: {
            Text(WoundL10n.text("This measurement was saved to \(patientProfile.displayName)'s record."))
        }
    }

    private var scanHeader: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Label(WoundL10n.text("Back"), systemImage: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint(WoundL10n.text("Returns to the wound location review"))

            VStack(alignment: .leading, spacing: 4) {
                Text(patientProfile.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(WoundL10n.text("\(woundIntake.laterality.rawValue) \(woundIntake.bodyArea.rawValue) • \(woundIntake.dateWounded.rawValue)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Menu {
                Button(WoundL10n.text("Restart camera"), systemImage: "arrow.clockwise") {
                    NotificationCenter.default.post(name: Notification.Name("RestartWoundCamera"), object: notificationScope)
                }
            } label: {
                Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
            }
            .accessibilityLabel(WoundL10n.text("Camera options"))
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }



    private var canAttachMeasurements: Bool { capturedMeasurement != nil }

    private func continueToAnalysis() {
        analysisContext = canAttachMeasurements ? currentMeasurementContext : nil
        showingAnalysis = true
    }

    private var completedMeasurementCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(WoundL10n.text(canAttachMeasurements ? "Measurements captured" : "Scan needs another pass"),
                  systemImage: canAttachMeasurements ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.headline)
                .foregroundStyle(canAttachMeasurements ? Color.green : Color.orange)
            if hasMeasurement {
                HStack(spacing: 6) {
                    ResultMetric(title: "Area", value: String(format: "%.2f", displayedMetrics.area), unit: "cm²")
                    ResultMetric(title: "Volume", value: String(format: "%.2f", displayedMetrics.volume), unit: "cm³")
                    ResultMetric(title: "Mean depth", value: estimatedDepthCM.map { String(format: "%.2f", $0) } ?? "—", unit: "cm")
                }
            }
            Text(WoundL10n.text(canAttachMeasurements
                 ? "These measurements will be attached to your AI photo check. Mean depth is estimated from volume ÷ area."
                 : "Any values shown are provisional. Scan again to attach measurements, or continue with a photo only."))
                .font(.caption).foregroundStyle(.secondary)
            if canAttachMeasurements && isPreliminary {
                Text(WoundL10n.text("Preliminary estimate · Capture quality: \(scanQuality.title)"))
                    .font(.caption.weight(.semibold)).foregroundStyle(.orange)
            }
            HStack {
                if hasMeasurement {
                    Button(WoundL10n.text(hasSavedMeasurement ? "View saved measurements" : "Details & save")) {
                        showingMeasurementDetails = true
                    }
                    .frame(minHeight: 44)
                }
                Spacer()
                if canAttachMeasurements {
                    Button(WoundL10n.text("Measure again"), action: startLiDARScan).frame(minHeight: 44)
                }
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var estimatedDepthCM: Float? {
        guard displayedMetrics.area.isFinite, displayedMetrics.volume.isFinite,
              displayedMetrics.area > 0, displayedMetrics.volume > 0 else { return nil }
        return WoundMeasurementMath.depthCM(area: displayedMetrics.area, volume: displayedMetrics.volume)
    }

    private var hasMeasurement: Bool {
        displayedMetrics.area.isFinite && displayedMetrics.area > 0 && displayedMetrics.perimeter.isFinite && displayedMetrics.perimeter > 0 && displayedMetrics.volume.isFinite && displayedMetrics.volume >= 0
    }
    private var displayedMetrics: (perimeter: Float, area: Float, volume: Float) {
        if let capturedMeasurement {
            return (capturedMeasurement.perimeterCM, capturedMeasurement.areaCM2, capturedMeasurement.volumeCM3)
        }
        return metricsManager.metrics
    }

    private var currentMeasurementContext: WoundAnalysisContext {
        capturedMeasurement ?? liveMeasurementContext
    }

    private var liveMeasurementContext: WoundAnalysisContext {
        WoundAnalysisContext(id: measurementID, capturedAt: measurementCompletedAt ?? Date(),
            perimeterCM: displayedMetrics.perimeter, areaCM2: displayedMetrics.area, volumeCM3: displayedMetrics.volume,
            volumeSource: volumeSourceText, quality: scanQuality.title, isPreliminary: isPreliminary,
            bodyArea: woundIntake.bodyArea.rawValue, laterality: woundIntake.laterality.rawValue)
    }

    private var hasSegmentation: Bool {
        topOutlinePoints.count >= 3
    }

    private var shareSummary: String {
        var lines = [
            "WoundCorder scan",
            "Patient: \(patientProfile.displayName)",
            "Body area: \(woundIntake.laterality.rawValue) \(woundIntake.bodyArea.rawValue)",
            "Date wounded: \(woundIntake.dateWounded.rawValue)",
            "Capture quality: \(scanQuality.title)",
            "Volume source: \(volumeSourceText)",
            String(format: "Area: %.2f cm²", displayedMetrics.area),
            String(format: "Volume: %.2f cm³", displayedMetrics.volume),
            estimatedDepthCM.map { String(format: "Estimated mean depth: %.2f cm (volume ÷ area)", $0) }
                ?? "Estimated mean depth: unavailable"
        ]

        if !woundIntake.contexts.isEmpty {
            let context = woundIntake.contexts.map(\.rawValue).sorted().joined(separator: ", ")
            lines.append("Context: \(context)")
        }

        if !woundIntake.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Notes: \(woundIntake.notes)")
        }

        if !woundIntake.medicineEntries.isEmpty {
            lines.append("Medicines: \(woundIntake.medicineEntries.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }

    private func configureScan() {
        // Returning from AI analysis must not restart or overwrite the completed scan.
        guard !isMeasurementFinalized else { return }
        NotificationCenter.default.post(name: NSNotification.Name("ARHideOverlays"), object: notificationScope)
        NotificationCenter.default.post(name: NSNotification.Name("DisableAutoSegmentation"), object: notificationScope)
        NotificationCenter.default.post(name: NSNotification.Name("EnableContinuousScanning"), object: notificationScope)
        automaticPhase = .ready
        scanInstruction = "LiDAR view ready. Center the wound, then tap Map Wound."
    }

    private func handleMeasurementState(_ state: AnyMeasurementState) {
        if let typed = state as? ARViewController.MeasurementState {
            // A high-quality live frame is still provisional until the scan's
            // explicit completion event accepts the multi-frame consensus.
            latestEstimateIsPreliminary = typed.isPreliminary
            isPreliminary = !isMeasurementFinalized || typed.isPreliminary
            switch typed.confidence {
            case .high:
                scanQuality = .high
            case .medium:
                scanQuality = .medium
            case .low:
                scanQuality = .low
            }

            return
        }

        let description = String(describing: state).lowercased()
        if description.contains("detect") || description.contains("refin") {
            isDetecting = true
            scanQuality = .scanning
        } else if description.contains("complete") || description.contains("ready") {
            isDetecting = false
            scanQuality = maxQuality(scanQuality, .medium)
        }
    }

    private func applyAutoDetection(_ notification: Notification) {
        var didReceiveSegmentation = false
        if let top = notification.userInfo?["topOutlinePoints"] as? [SIMD3<Float>], top.count >= 3 {
            topOutlinePoints = top
            didReceiveSegmentation = true
        }
        if let bottom = notification.userInfo?["bottomOutlinePoints"] as? [SIMD3<Float>], bottom.count >= 3 {
            bottomOutlinePoints = bottom
        }

        // The AR measurement pipeline is the sole owner of area/volume. Recomputing
        // here with a second formula made the values change after a scan had settled.
        if notification.userInfo?["measurementReady"] as? Bool != nil ||
            isDetecting || isMeasurementFinalized {
            return
        }

        isDetecting = false
        if displayedMetrics.volume > 0 {
            scanQuality = maxQuality(scanQuality, .medium)
            scanInstruction = "Measurement captured. Review the result before saving."
        } else if displayedMetrics.area > 0 {
            scanQuality = maxQuality(scanQuality, .medium)
            scanInstruction = "Area found. Tilt slightly around the wound for better depth."
        } else if didReceiveSegmentation {
            scanQuality = maxQuality(scanQuality, .medium)
            scanInstruction = "Mask ready. Correct the outline or measure again if needed."
        } else {
            scanQuality = .low
            scanInstruction = "No wound mask found. Recenter the wound and measure again."
        }
    }

    private func applyLiDARScanStatus(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        let finalReadiness = userInfo["measurementReady"] as? Bool

        if let stage = userInfo["scanStage"] as? String {
            switch stage {
            case "mapping": automaticPhase = .mapping
            case "awaitingConfirmation": automaticPhase = .awaitingConfirmation
            case "capturing": automaticPhase = .capturing
            case "finalizing": automaticPhase = .finalizing
            case "complete": automaticPhase = .complete
            case "boundaryFailed": automaticPhase = .failed
            default: automaticPhase = .ready
            }
        }
        if let canConfirm = userInfo["canConfirmWound"] as? Bool {
            canConfirmWound = canConfirm
        }
        if let canFinish = userInfo["canFinishCapture"] as? Bool {
            canFinishPointCapture = canFinish
        }

        if let progress = userInfo["progress"] as? Double {
            scanProgress = min(max(progress, 0), 1)
        }
        if let isScanning = userInfo["isScanning"] as? Bool {
            isDetecting = isScanning
        }
        if let measurementReady = finalReadiness {
            isMeasurementFinalized = measurementReady
            if measurementReady {
                isDetecting = false
                isPreliminary = latestEstimateIsPreliminary
                showManualControls = false
            } else {
                capturedMeasurement = nil
                isPreliminary = true
            }
        }
        if let message = userInfo["message"] as? String {
            scanInstruction = message
        }
        if let quality = userInfo["quality"] as? String {
            switch quality {
            case "high":
                scanQuality = .high
            case "medium":
                scanQuality = finalReadiness == nil
                    ? maxQuality(scanQuality, .medium)
                    : .medium
            case "low":
                if finalReadiness != nil {
                    scanQuality = .low
                } else if scanQuality.rank < ScanQuality.medium.rank {
                    scanQuality = .low
                }
            default:
                scanQuality = .scanning
            }
        }
        if let applied = userInfo["segmentationApplied"] as? Bool {
            segmentationVolumeApplied = applied
        }
        if let source = userInfo["volumeSource"] as? String {
            volumeSourceText = source
        }
        if finalReadiness == true, hasMeasurement {
            measurementCompletedAt = Date()
            capturedMeasurement = liveMeasurementContext
        }
    }

    private func applyMetricsUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        // Numeric values arrive through ARViewContainer's direct callback. This
        // notification carries source/quality metadata only, avoiding a duplicate
        // three-property SwiftUI update for every live sample.
        let area = displayedMetrics.area
        let volume = displayedMetrics.volume
        if let source = userInfo["volumeSource"] as? String {
            volumeSourceText = source
        }
        if let applied = userInfo["segmentationApplied"] as? Bool {
            segmentationVolumeApplied = applied
        }

        // Preliminary metric samples arrive throughout a scan. The explicit
        // measurementReady status owns completion text and progress so live values
        // cannot briefly make an in-progress or failed scan look complete.
        if isMeasurementFinalized {
            if volume > 0 {
                scanInstruction = "Volumetric measurement ready."
                scanQuality = maxQuality(scanQuality, .medium)
                scanProgress = 1
            } else if area > 0 {
                scanInstruction = "Area measurement ready."
                scanQuality = maxQuality(scanQuality, .medium)
                scanProgress = 1
            }
        }
    }

    private func startLiDARScan() {
        showManualControls = false
        automaticPhase = .mapping
        canConfirmWound = false
        canFinishPointCapture = false
        isDetecting = true
        isPreliminary = true
        isMeasurementFinalized = false
        capturedMeasurement = nil
        hasSavedMeasurement = false
        scanQuality = .scanning
        scanProgress = 0
        segmentationVolumeApplied = false
        volumeSourceText = "Mapping wound boundary"
        scanInstruction = "Step 1 of 2: Hold steady while the wound edge is mapped."
        metricsManager.resetMetrics()
        NotificationCenter.default.post(name: NSNotification.Name("EnableContinuousScanning"), object: notificationScope)
        NotificationCenter.default.post(name: NSNotification.Name("StartVolumetricLiDARScan"), object: notificationScope)
    }

    private func confirmMappedWound() {
        guard automaticPhase == .awaitingConfirmation, canConfirmWound else { return }
        automaticPhase = .capturing
        canConfirmWound = false
        canFinishPointCapture = false
        isDetecting = true
        scanProgress = 0.34
        scanInstruction = "Step 2 of 2: Move slowly around the wound while the green point cloud fills in."
        NotificationCenter.default.post(
            name: NSNotification.Name("ConfirmAutomaticWoundBoundary"),
            object: notificationScope
        )
    }

    private func finishPointCapture() {
        guard automaticPhase == .capturing, canFinishPointCapture else { return }
        automaticPhase = .finalizing
        isDetecting = true
        scanInstruction = "Finalizing the confirmed wound point cloud…"
        NotificationCenter.default.post(
            name: NSNotification.Name("FinishAutomaticPointCapture"),
            object: notificationScope
        )
    }

    private func startGuidedManualMeasurement() {
        showManualControls = true
        automaticPhase = .ready
        canConfirmWound = false
        canFinishPointCapture = false
        manualPhase = .rim
        manualPointCount = 0
        manualCanFinish = false
        manualCanUndo = false
        manualHasDetectedSeed = false
        manualValidationMessage = ""
        isDetecting = true
        isPreliminary = true
        isMeasurementFinalized = false
        capturedMeasurement = nil
        hasSavedMeasurement = false
        scanQuality = .scanning
        scanProgress = 0
        metricsManager.resetMetrics()
        segmentationVolumeApplied = false
        volumeSourceText = "Manual tracing in progress"
        scanInstruction = "Trace once around the wound edge, then tap Next."
        NotificationCenter.default.post(name: NSNotification.Name("StartGuidedWoundMeasurement"),
                                        object: notificationScope, userInfo: ["startFresh": true])
    }

    private func finishManualMeasurement() {
        NotificationCenter.default.post(name: NSNotification.Name("ManualFinish"), object: notificationScope)
    }

    private func clearManualMeasurement() {
        NotificationCenter.default.post(name: NSNotification.Name("ManualClear"), object: notificationScope)
        scanQuality = .scanning
        isPreliminary = true
        isMeasurementFinalized = false
        capturedMeasurement = nil
        hasSavedMeasurement = false
        segmentationVolumeApplied = false
        volumeSourceText = "Manual tracing in progress"
        scanProgress = manualPhase == .rim ? 0 : 0.5
        scanInstruction = manualPhase == .rim
            ? "Wound edge cleared. Trace once around it, then tap Next."
            : "Depth edge cleared. Trace the inner edge, then tap Finish."
    }

    private func undoManualMeasurement() {
        NotificationCenter.default.post(name: NSNotification.Name("ManualUndo"), object: notificationScope)
    }

    private func returnToManualRim() {
        NotificationCenter.default.post(name: NSNotification.Name("ManualBackToRim"), object: notificationScope)
    }

    private func applyManualOutlineState(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        manualPhase = (userInfo["phase"] as? String) == "bed" ? .bed : .rim
        manualPointCount = userInfo["pointCount"] as? Int ?? 0
        manualCanFinish = userInfo["canFinish"] as? Bool ?? false
        manualCanUndo = userInfo["canUndo"] as? Bool ?? false
        manualHasDetectedSeed = userInfo["hasDetectedSeed"] as? Bool ?? false
        manualValidationMessage = userInfo["validationMessage"] as? String ?? ""

        if manualPhase == .bed {
            if !manualCanFinish, !manualValidationMessage.isEmpty, manualPointCount > 0 {
                scanInstruction = manualValidationMessage
            } else {
                scanInstruction = manualPointCount == 0
                    ? "Trace the inner depth edge, then tap Finish."
                    : "Complete the depth edge, then tap Finish."
            }
        } else if manualHasDetectedSeed {
            scanInstruction = "Existing edge shown. Trace to replace it, or tap Next to keep it."
        } else if manualPointCount == 0 {
            scanInstruction = "Trace once around the wound edge, then tap Next."
        } else if !manualCanFinish, !manualValidationMessage.isEmpty {
            scanInstruction = manualValidationMessage
        } else {
            scanInstruction = "Complete the wound edge, then tap Next."
        }
    }

    private func saveMeasurementBeforeLeaving() throws {
        guard canAttachMeasurements, !hasSavedMeasurement else { return }
        guard logManager.add(title: "\(woundIntake.laterality.rawValue) \(woundIntake.bodyArea.rawValue)",
            perimeter: displayedMetrics.perimeter, area: displayedMetrics.area, volume: displayedMetrics.volume,
            patientID: patientID, patientName: patientProfile.displayName, bodyArea: woundIntake.bodyArea.rawValue,
            laterality: woundIntake.laterality.rawValue, context: currentMeasurementContext) else {
            throw CocoaError(.fileWriteUnknown)
        }
        hasSavedMeasurement = true
    }

    private func saveMeasurement() {
        guard hasMeasurement, isMeasurementFinalized, !hasSavedMeasurement else { return }
        guard logManager.add(
            title: "\(patientProfile.displayName) \(woundIntake.bodyArea.rawValue)",
            perimeter: displayedMetrics.perimeter,
            area: displayedMetrics.area,
            volume: displayedMetrics.volume,
            patientID: patientID,
            patientName: patientProfile.displayName,
            bodyArea: woundIntake.bodyArea.rawValue,
            laterality: woundIntake.laterality.rawValue,
            context: currentMeasurementContext
        ) else { return }
        hasSavedMeasurement = true
        DispatchQueue.main.async {
            isShowingSaveSuccess = true
        }
    }

    private func maxQuality(_ lhs: ScanQuality, _ rhs: ScanQuality) -> ScanQuality {
        lhs.rank >= rhs.rank ? lhs : rhs
    }
}

private enum ScanQuality: Equatable {
    case waiting
    case scanning
    case low
    case medium
    case high

    var title: String {
        switch self {
        case .waiting: return "Ready"
        case .scanning: return "Scanning"
        case .low: return "Low"
        case .medium: return "Good"
        case .high: return "High"
        }
    }

    var symbol: String {
        switch self {
        case .waiting: return "viewfinder"
        case .scanning: return "dot.radiowaves.left.and.right"
        case .low: return "exclamationmark.triangle"
        case .medium: return "checkmark.circle"
        case .high: return "checkmark.seal.fill"
        }
    }

    var tint: Color {
        switch self {
        case .waiting: return .secondary
        case .scanning: return .blue
        case .low: return .orange
        case .medium: return .green
        case .high: return .mint
        }
    }

    var rank: Int {
        switch self {
        case .waiting: return 0
        case .scanning: return 1
        case .low: return 2
        case .medium: return 3
        case .high: return 4
        }
    }
}

private struct ScanQualityPill: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let quality: ScanQuality
    let isDetecting: Bool

    var body: some View {
        Label(WoundL10n.text(isDetecting ? "Scanning" : quality.title), systemImage: isDetecting ? "dot.radiowaves.left.and.right" : quality.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(quality.tint.opacity(0.18), in: Capsule())
            .foregroundStyle(quality.tint)
    }
}

private struct DimensionOverlay: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let area: Float
    let depth: Float?
    let bodyArea: BodyArea
    let laterality: Laterality

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "plus.viewfinder")
                .font(.system(size: 38, weight: .light))
            Text(WoundL10n.text("\(laterality.rawValue) \(bodyArea.rawValue)"))
                .font(.caption.weight(.bold))
            Text(WoundL10n.text(String(format: "Area %.2f cm²", area) + " • Mean depth "
                 + (depth.map { String(format: "%.2f cm", $0) } ?? "unavailable")))
                .font(.caption2.monospacedDigit())
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(Color.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .allowsHitTesting(false)
    }
}

private struct ScanResultsPanel: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let metrics: (perimeter: Float, area: Float, volume: Float)
    let depthCM: Float?
    let scanQuality: ScanQuality
    let isPreliminary: Bool
    let segmentationVolumeApplied: Bool
    let volumeSourceText: String
    let patientName: String
    let canSave: Bool
    let isSaved: Bool
    let shareText: String
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack(spacing: 10) {
                ResultMetric(title: "Area", value: String(format: "%.2f", metrics.area), unit: "cm²")
                ResultMetric(title: "Volume", value: String(format: "%.2f", metrics.volume), unit: "cm³")
                ResultMetric(title: "Mean depth", value: depthCM.map { String(format: "%.2f", $0) } ?? "—", unit: "cm")
            }

            Text(WoundL10n.text("Mean depth is estimated from volume ÷ area."))
                .font(.caption2)
                .foregroundStyle(.secondary)

            Label(WoundL10n.text(
                volumeSourceText),
                systemImage: segmentationVolumeApplied ? "checkmark.seal.fill" : "cube.transparent"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(segmentationVolumeApplied ? .green : .secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Label(WoundL10n.text(isPreliminary ? "Capture Quality: \(scanQuality.title) • Preliminary" : "Capture Quality: \(scanQuality.title)"), systemImage: scanQuality.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(scanQuality.tint)

                Spacer()

                ShareLink(item: shareText) {
                    Label(WoundL10n.text("Share"), systemImage: "square.and.arrow.up")
                }
                .font(.caption.weight(.semibold))
                .disabled(!canSave)
            }

            Button(action: onSave) {
                HStack {
                    Image(systemName: isSaved ? "checkmark.circle.fill" : "checkmark.seal.fill")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(WoundL10n.text(isSaved ? "Measurement Saved" : "Confirm & Save"))
                            .font(.headline)
                        Text(WoundL10n.text("to \(patientName)"))
                            .font(.caption)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(!canSave || isSaved)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}



private struct ResultMetric: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(WoundL10n.text(title))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(WoundL10n.text(value))
                    .font(.title3.weight(.bold).monospacedDigit())
                Text(WoundL10n.text(unit))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.systemBackground).opacity(0.56), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct MetricsView: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let metrics: (perimeter: Float, area: Float, volume: Float)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(WoundL10n.text("Wound Measurements"))
                .font(.headline)
            Text(WoundL10n.text("Perimeter: \(metrics.perimeter, specifier: "%.2f") cm"))
            Text(WoundL10n.text("Area: \(metrics.area, specifier: "%.2f") cm²"))
            Text(WoundL10n.text("Volume: \(metrics.volume, specifier: "%.2f") cm³"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ScanControlsBar: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let isDetecting: Bool
    let automaticPhase: AutomaticMeasurementPhase
    let canConfirmWound: Bool
    let canFinishPointCapture: Bool
    let onStartScan: () -> Void
    let onConfirmWound: () -> Void
    let onFinishCapture: () -> Void
    let onCorrect: () -> Void

    private var primaryTitle: String {
        switch automaticPhase {
        case .ready: return "Auto Detect"
        case .mapping: return "Mapping Wound…"
        case .awaitingConfirmation: return "Confirm Wound"
        case .capturing: return canFinishPointCapture ? "Finish Scan" : "Collecting Points…"
        case .finalizing: return "Finalizing…"
        case .complete: return "Measure Again"
        case .failed: return "Retry Auto Detect"
        }
    }

    private var primarySymbol: String {
        switch automaticPhase {
        case .awaitingConfirmation: return "checkmark.circle.fill"
        case .capturing: return canFinishPointCapture ? "stop.circle.fill" : "dot.radiowaves.left.and.right"
        case .finalizing: return "hourglass"
        default: return "viewfinder.circle"
        }
    }

    private var primaryDisabled: Bool {
        switch automaticPhase {
        case .mapping, .finalizing: return true
        case .awaitingConfirmation: return !canConfirmWound
        case .capturing: return !canFinishPointCapture
        case .ready: return isDetecting
        case .complete, .failed: return false
        }
    }

    private func performPrimaryAction() {
        switch automaticPhase {
        case .awaitingConfirmation:
            onConfirmWound()
        case .capturing:
            onFinishCapture()
        case .ready, .complete, .failed:
            onStartScan()
        case .mapping, .finalizing:
            break
        }
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            Button(action: performPrimaryAction) {
                Label(WoundL10n.text(primaryTitle), systemImage: primarySymbol)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(automaticPhase == .awaitingConfirmation ? .green : .blue)
            .disabled(primaryDisabled)

            Button(action: onCorrect) {
                Label(WoundL10n.text("Trace Manually"), systemImage: "pencil.tip.crop.circle")
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.bordered)
            .disabled(automaticPhase == .finalizing)
            .accessibilityHint(WoundL10n.text("Starts a separate manual measurement with a blank outline"))

        }
    }
}

private struct ManualRefinementBar: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let phase: ManualSelectionPhase
    let pointCount: Int
    let canFinish: Bool
    let canUndo: Bool
    let hasDetectedSeed: Bool
    let onUndo: () -> Void
    let onBack: () -> Void
    let onFinish: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: phase.symbol)
                    .foregroundStyle(phase == .rim ? .green : .cyan)

                VStack(alignment: .leading, spacing: 2) {
                    Text(WoundL10n.text(phase.stepText))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(WoundL10n.text(phase.title))
                        .font(.subheadline.weight(.bold))
                }

                Spacer()

                Text(WoundL10n.text(hasDetectedSeed ? "Existing edge" : "\(pointCount) points"))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button(action: onUndo) {
                    Label(WoundL10n.text("Undo"), systemImage: "arrow.uturn.backward")
                        .labelStyle(.iconOnly)
                        .frame(width: 30)
                }
                .buttonStyle(.bordered)
                .disabled(!canUndo)
                .accessibilityLabel(WoundL10n.text("Undo last outline change"))

                if phase == .bed {
                    Button(action: onBack) {
                        Label(WoundL10n.text("Back"), systemImage: "chevron.left")
                            .labelStyle(.iconOnly)
                            .frame(width: 30)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(WoundL10n.text("Return to wound edge"))
                }

                Button(action: onFinish) {
                    Label(WoundL10n.text(
                        phase.primaryTitle),
                        systemImage: phase == .rim ? "arrow.right.circle.fill" : "checkmark.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(phase == .rim ? .blue : .green)
                .disabled(!canFinish)

                Button(action: onClear) {
                    Label(WoundL10n.text("Clear step"), systemImage: "trash")
                        .labelStyle(.iconOnly)
                        .frame(width: 30)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(pointCount == 0 && !hasDetectedSeed)
                .accessibilityLabel(WoundL10n.text("Clear \(phase.title.lowercased())"))
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct LiDARScanGuidancePanel: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let instruction: String
    let progress: Double
    let hasSegmentation: Bool
    let hasMeasurement: Bool
    let isScanning: Bool
    let automaticPhase: AutomaticMeasurementPhase

    private var boundaryMapped: Bool {
        switch automaticPhase {
        case .awaitingConfirmation, .capturing, .finalizing, .complete: return true
        case .ready, .mapping, .failed: return hasSegmentation && automaticPhase != .mapping
        }
    }

    private var boundaryConfirmed: Bool {
        switch automaticPhase {
        case .capturing, .finalizing, .complete: return true
        case .ready, .mapping, .awaitingConfirmation, .failed: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: isScanning ? "dot.radiowaves.left.and.right" : hasSegmentation ? "checkmark.circle" : "viewfinder")
                    .font(.headline)
                    .foregroundStyle(isScanning ? .blue : hasSegmentation ? .green : .secondary)

                Text(WoundL10n.text(instruction))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)

                Spacer()
            }

            if isScanning { ProgressView(value: progress).tint(.blue) }


        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct WorkflowStep: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let title: String
    let isActive: Bool

    var body: some View {
        Label(WoundL10n.text(title), systemImage: isActive ? "checkmark.circle.fill" : "circle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(isActive ? .green : .secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
final class MetricsManager: ObservableObject {
    private struct Values: Equatable {
        var perimeter: Float = 0
        var area: Float = 0
        var volume: Float = 0
    }

    @Published private var values = Values()

    var perimeter: Float { values.perimeter }
    var area: Float { values.area }
    var volume: Float { values.volume }

    var metrics: (perimeter: Float, area: Float, volume: Float) {
        (perimeter: perimeter, area: area, volume: volume)
    }

    func updateMetrics(perimeter: Float, area: Float, volume: Float) {
        let next = Values(perimeter: perimeter, area: area, volume: volume)
        guard next != values else { return }
        values = next
    }

    func resetMetrics() {
        guard values != Values() else { return }
        values = Values()
    }
}

#Preview {
    ContentView()
        .environmentObject(MeasurementLogManager())
}

#if DEBUG
@MainActor func woundLanguageScanFixture() -> some View {
    VStack(alignment: .leading, spacing: 16) {
        Text(WoundL10n.text("Starting LiDAR camera…")).font(.headline)
        Text(WoundL10n.text("Step 2 of 2: Aim for a 5–10 second gentle sweep. Keep the whole wound and nearby skin in view."))
        ProgressView(value: 0.65)
        Text(WoundL10n.text("Seen 100% · verified 65% / 60%. Make a small side-to-side sweep; keep the wound centered."))
        ScanControlsBar(isDetecting: true, automaticPhase: .capturing, canConfirmWound: false,
                        canFinishPointCapture: true, onStartScan: {}, onConfirmWound: {}, onFinishCapture: {}, onCorrect: {})
            .id("scan-actions")
        ResultMetric(title: "Mean depth", value: "0.50", unit: "cm")
        Text(WoundL10n.text("Measurements captured"))
        Text(WoundL10n.text("Area 12.50 cm² · Volume 3.20 cm³"))
        Button(WoundL10n.text("Continue to AI with measurements")) {}.buttonStyle(.borderedProminent)
        Text(WoundL10n.text("These measurements will be attached to your AI photo check. Mean depth is estimated from volume ÷ area."))
    }.fixedSize(horizontal: false, vertical: true).padding()
}
#endif
