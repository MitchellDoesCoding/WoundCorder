import SwiftUI

struct ContentView: View {
    let patientProfile: PatientProfile
    let woundIntake: WoundIntakeData

    @StateObject private var metricsManager = MetricsManager()
    @StateObject private var logManager = MeasurementLogManager()

    @State private var topOutlinePoints: [SIMD3<Float>] = []
    @State private var bottomOutlinePoints: [SIMD3<Float>] = []
    @State private var selectedDepthPoint: SIMD3<Float>?
    @State private var isDetecting = false
    @State private var showManualControls = false
    @State private var showMoreActions = false
    @State private var showSettings = false
    @State private var showImageAnalysis = false
    @State private var meshViewerActive = false
    @State private var arViewVersion = 0
    @State private var scanQuality: ScanQuality = .waiting
    @State private var isPreliminary = true
    @State private var meshVisible = false
    @State private var classificationColors = false
    @State private var scanInstruction = "Point the camera at the wound."
    @State private var scanProgress: Double = 0
    @State private var meshAnchorCount = 0
    @State private var meshVertexCount = 0
    @State private var meshFaceCount = 0

    @Environment(\.dismiss) private var dismiss

    private let volumeCalculator = LiDARVolumeCalculator()
    private let autoDetectFinishedNotification = NotificationCenter.default.publisher(for: Notification.Name("AutoDetectionDidFinish"))
    private let liDARScanStatusNotification = NotificationCenter.default.publisher(for: Notification.Name("LiDARScanStatusDidUpdate"))
    private let metricsUpdatedNotification = NotificationCenter.default.publisher(for: Notification.Name("MetricsUpdated"))

    init(
        patientProfile: PatientProfile = PatientProfile(),
        woundIntake: WoundIntakeData = WoundIntakeData()
    ) {
        self.patientProfile = patientProfile
        self.woundIntake = woundIntake
    }

    var body: some View {
        ZStack {
            ARViewContainer(
                topOutlinePoints: $topOutlinePoints,
                bottomOutlinePoints: $bottomOutlinePoints,
                metricsManager: metricsManager,
                selectedDepthPoint: $selectedDepthPoint,
                onMeasurementState: handleMeasurementState
            )
            .id(arViewVersion)
            .ignoresSafeArea()
            .onAppear(perform: configureScan)
            .onChange(of: topOutlinePoints) { _, newValue in
                if newValue.count >= 3 {
                    recomputeMetricsIfPossible()
                }
            }
            .onChange(of: bottomOutlinePoints) { _, newValue in
                if newValue.count >= 3 {
                    recomputeMetricsIfPossible()
                }
            }
            .onReceive(autoDetectFinishedNotification) { notification in
                applyAutoDetection(notification)
            }
            .onReceive(liDARScanStatusNotification) { notification in
                applyLiDARScanStatus(notification)
            }
            .onReceive(metricsUpdatedNotification) { notification in
                applyMetricsUpdate(notification)
            }

            DimensionOverlay(
                area: metricsManager.area,
                depth: estimatedDepthCM,
                bodyArea: woundIntake.bodyArea,
                laterality: woundIntake.laterality
            )

            VStack(spacing: 0) {
                scanHeader
                    .padding(.horizontal, 14)
                    .padding(.top, 12)

                Spacer()

                LiDARScanGuidancePanel(
                    instruction: scanInstruction,
                    progress: scanProgress,
                    anchorCount: meshAnchorCount,
                    vertexCount: meshVertexCount,
                    faceCount: meshFaceCount,
                    isScanning: isDetecting
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

                ScanResultsPanel(
                    metrics: metricsManager.metrics,
                    severity: severityScore,
                    depthCM: estimatedDepthCM,
                    scanQuality: scanQuality,
                    isPreliminary: isPreliminary,
                    shareText: shareSummary,
                    onSave: saveMeasurement
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

                ScanControlsBar(
                    isDetecting: isDetecting,
                    meshVisible: meshVisible,
                    classificationColors: classificationColors,
                    showManualControls: $showManualControls,
                    onStartScan: startLiDARScan,
                    onReset: resetScene,
                    onToggleMesh: toggleMesh,
                    onToggleClassification: toggleClassificationColors,
                    onExport: exportScene,
                    onImageAnalysis: { showImageAnalysis = true },
                    onMoreActions: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showMoreActions.toggle()
                        }
                    }
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 18)

                if showMoreActions {
                    MoreScanActionsPanel(
                        meshViewerActive: meshViewerActive,
                        onGuidedRefine: {
                            showMoreActions = false
                            showManualControls = true
                        },
                        onToggleMeshViewer: {
                            showMoreActions = false
                            toggleMeshViewerMode()
                        },
                        onImageAnalysis: {
                            showMoreActions = false
                            showImageAnalysis = true
                        },
                        onReset: {
                            showMoreActions = false
                            resetScene()
                        },
                        onSettings: {
                            showMoreActions = false
                            showSettings = true
                        }
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if showManualControls {
                    ManualRefinementBar(
                        onStart: startGuidedManualMeasurement,
                        onFinish: finishManualMeasurement,
                        onClear: clearManualMeasurement
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .statusBarHidden(true)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: $showImageAnalysis) {
            ARCameraTabView()
                .environmentObject(logManager)
                .statusBarHidden(true)
        }
    }

    private var scanHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(patientProfile.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(woundIntake.laterality.rawValue) \(woundIntake.bodyArea.rawValue) • \(woundIntake.dateWounded.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            ScanQualityPill(quality: scanQuality, isDetecting: isDetecting)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var severityScore: Int {
        WoundSeverityScorer.score(area: metricsManager.area, volume: metricsManager.volume)
    }

    private var estimatedDepthCM: Float {
        WoundSeverityScorer.depthCM(area: metricsManager.area, volume: metricsManager.volume)
    }

    private var shareSummary: String {
        var lines = [
            "Woundcorder scan",
            "Patient: \(patientProfile.displayName)",
            "Body area: \(woundIntake.laterality.rawValue) \(woundIntake.bodyArea.rawValue)",
            "Date wounded: \(woundIntake.dateWounded.rawValue)",
            "Severity: \(severityScore)/20",
            "Capture quality: \(scanQuality.title)",
            String(format: "Area: %.2f cm²", metricsManager.area),
            String(format: "Volume: %.2f cm³", metricsManager.volume),
            String(format: "Depth: %.2f cm", estimatedDepthCM)
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
        NotificationCenter.default.post(name: NSNotification.Name("ARHideOverlays"), object: nil)
        NotificationCenter.default.post(name: NSNotification.Name("DisableAutoSegmentation"), object: nil)
        NotificationCenter.default.post(name: NSNotification.Name("EnableContinuousScanning"), object: nil)
        scanInstruction = "LiDAR view ready. Center the wound, then press Scan when ready."
    }

    private func handleMeasurementState(_ state: AnyMeasurementState) {
        if let typed = state as? ARViewController.MeasurementState {
            isPreliminary = typed.isPreliminary
            switch typed.confidence {
            case .high:
                scanQuality = .high
            case .medium:
                scanQuality = .medium
            case .low:
                scanQuality = .low
            }

            if typed.area != nil || typed.volume != nil {
                isDetecting = false
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
        if let top = notification.userInfo?["topOutlinePoints"] as? [SIMD3<Float>], top.count >= 3 {
            topOutlinePoints = top
        }
        if let bottom = notification.userInfo?["bottomOutlinePoints"] as? [SIMD3<Float>], bottom.count >= 3 {
            bottomOutlinePoints = bottom
        }

        recomputeMetricsIfPossible()
        isDetecting = false
        scanQuality = maxQuality(scanQuality, .medium)
        scanProgress = 1
        if metricsManager.volume > 0 {
            scanInstruction = "Volumetric measurement ready."
        } else if metricsManager.area > 0 {
            scanInstruction = "Area found. Tilt slightly around the wound for better depth."
        }
    }

    private func applyLiDARScanStatus(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }

        if let progress = userInfo["progress"] as? Double {
            scanProgress = min(max(progress, 0), 1)
        }
        if let isScanning = userInfo["isScanning"] as? Bool {
            isDetecting = isScanning
        }
        if let anchors = userInfo["anchorCount"] as? Int {
            meshAnchorCount = anchors
        }
        if let vertices = userInfo["vertexCount"] as? Int {
            meshVertexCount = vertices
        }
        if let faces = userInfo["faceCount"] as? Int {
            meshFaceCount = faces
        }
        if let message = userInfo["message"] as? String {
            scanInstruction = message
        }
        if let quality = userInfo["quality"] as? String {
            switch quality {
            case "high":
                scanQuality = .high
            case "medium":
                scanQuality = maxQuality(scanQuality, .medium)
            case "low":
                if scanQuality.rank < ScanQuality.medium.rank {
                    scanQuality = .low
                }
            default:
                scanQuality = .scanning
            }
        }
    }

    private func applyMetricsUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        let perimeter = userInfo["perimeter"] as? Float ?? metricsManager.perimeter
        let area = userInfo["area"] as? Float ?? metricsManager.area
        let volume = userInfo["volume"] as? Float ?? metricsManager.volume

        metricsManager.updateMetrics(perimeter: perimeter, area: area, volume: volume)

        if volume > 0 {
            scanInstruction = "Volumetric measurements ready."
            scanQuality = maxQuality(scanQuality, .medium)
            scanProgress = max(scanProgress, 1)
        } else if area > 0 {
            scanInstruction = "Area measured. Use 3D Mesh View or rescan for stronger depth."
            scanQuality = maxQuality(scanQuality, .medium)
        }
    }

    private func startLiDARScan() {
        isDetecting = true
        isPreliminary = true
        scanQuality = .scanning
        scanProgress = 0
        scanInstruction = "Starting LiDAR mesh scan. Move slowly around the wound."
        if !meshVisible {
            meshVisible = true
        }
        NotificationCenter.default.post(name: NSNotification.Name("EnableAutoSegmentation"), object: nil)
        NotificationCenter.default.post(name: NSNotification.Name("EnableContinuousScanning"), object: nil)
        NotificationCenter.default.post(name: NSNotification.Name("StartVolumetricLiDARScan"), object: nil)
    }

    private func startGuidedManualMeasurement() {
        showManualControls = true
        isDetecting = true
        scanQuality = .scanning
        NotificationCenter.default.post(name: NSNotification.Name("StartGuidedWoundMeasurement"), object: nil)
    }

    private func finishManualMeasurement() {
        NotificationCenter.default.post(name: NSNotification.Name("ManualFinish"), object: nil)
        isDetecting = false
    }

    private func clearManualMeasurement() {
        NotificationCenter.default.post(name: NSNotification.Name("ManualClear"), object: nil)
        topOutlinePoints.removeAll()
        bottomOutlinePoints.removeAll()
        selectedDepthPoint = nil
        metricsManager.resetMetrics()
        scanQuality = .waiting
    }

    private func resetScene() {
        topOutlinePoints.removeAll()
        bottomOutlinePoints.removeAll()
        selectedDepthPoint = nil
        metricsManager.resetMetrics()
        arViewVersion &+= 1
        isDetecting = false
        scanQuality = .waiting
        scanProgress = 0
        meshAnchorCount = 0
        meshVertexCount = 0
        meshFaceCount = 0
        scanInstruction = "Point the camera at the wound."
        meshViewerActive = false
        NotificationCenter.default.post(name: NSNotification.Name("ExitMeshViewerMode"), object: nil)
        NotificationCenter.default.post(name: NSNotification.Name("ResetARScene"), object: nil)
    }

    private func toggleMesh() {
        meshVisible.toggle()
        NotificationCenter.default.post(name: NSNotification.Name("ToggleWireframe"), object: nil)
    }

    private func toggleClassificationColors() {
        classificationColors.toggle()
        NotificationCenter.default.post(name: NSNotification.Name("ToggleClassificationColors"), object: nil)
    }

    private func toggleMeshViewerMode() {
        meshViewerActive.toggle()
        meshVisible = true
        if meshViewerActive {
            scanInstruction = "3D mesh view is active. Move the phone to inspect the wound surface."
            NotificationCenter.default.post(name: NSNotification.Name("EnterMeshViewerMode"), object: nil)
        } else {
            scanInstruction = "Live scan view is active."
            NotificationCenter.default.post(name: NSNotification.Name("ExitMeshViewerMode"), object: nil)
        }
    }

    private func exportScene() {
        NotificationCenter.default.post(name: NSNotification.Name("ExportARScene"), object: nil)
    }

    private func saveMeasurement() {
        logManager.add(
            title: "\(patientProfile.displayName) \(woundIntake.bodyArea.rawValue)",
            perimeter: metricsManager.perimeter,
            area: metricsManager.area,
            volume: metricsManager.volume,
            severity: severityScore,
            patientName: patientProfile.displayName,
            bodyArea: woundIntake.bodyArea.rawValue,
            laterality: woundIntake.laterality.rawValue
        )
    }

    private func recomputeMetricsIfPossible() {
        guard topOutlinePoints.count >= 3 else { return }

        if bottomOutlinePoints.count >= 3 {
            let (perimeter, area, volume) = volumeCalculator.computeMetricsFromOutlines(
                topOutline: topOutlinePoints,
                bottomOutline: bottomOutlinePoints
            )
            metricsManager.updateMetrics(perimeter: perimeter, area: area, volume: volume)
        }

        if metricsManager.area > 0 || metricsManager.volume > 0 {
            scanQuality = maxQuality(scanQuality, .medium)
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
    let quality: ScanQuality
    let isDetecting: Bool

    var body: some View {
        Label(isDetecting ? "Scanning" : quality.title, systemImage: isDetecting ? "dot.radiowaves.left.and.right" : quality.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(quality.tint.opacity(0.18), in: Capsule())
            .foregroundStyle(quality.tint)
    }
}

private struct DimensionOverlay: View {
    let area: Float
    let depth: Float
    let bodyArea: BodyArea
    let laterality: Laterality

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "plus.viewfinder")
                .font(.system(size: 38, weight: .light))
            Text("\(laterality.rawValue) \(bodyArea.rawValue)")
                .font(.caption.weight(.bold))
            Text(String(format: "Area %.2f cm² • Depth %.2f cm", area, depth))
                .font(.caption2.monospacedDigit())
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(Color.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .allowsHitTesting(false)
    }
}

private struct ScanResultsPanel: View {
    let metrics: (perimeter: Float, area: Float, volume: Float)
    let severity: Int
    let depthCM: Float
    let scanQuality: ScanQuality
    let isPreliminary: Bool
    let shareText: String
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SeverityStrip(score: severity)

            HStack(spacing: 10) {
                ResultMetric(title: "Area", value: String(format: "%.2f", metrics.area), unit: "cm²")
                ResultMetric(title: "Volume", value: String(format: "%.2f", metrics.volume), unit: "cm³")
                ResultMetric(title: "Depth", value: String(format: "%.2f", depthCM), unit: "cm")
            }

            HStack(spacing: 10) {
                Label(isPreliminary ? "Capture Quality: \(scanQuality.title) • Preliminary" : "Capture Quality: \(scanQuality.title)", systemImage: scanQuality.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(scanQuality.tint)

                Spacer()

                ShareLink(item: shareText) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .font(.caption.weight(.semibold))

                Button(action: onSave) {
                    Label("Save", systemImage: "tray.and.arrow.down")
                }
                .font(.caption.weight(.semibold))
                .disabled(metrics.area <= 0 && metrics.volume <= 0)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SeverityStrip: View {
    let score: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Severity")
                    .font(.headline)
                Spacer()
                Text("\(score)/20")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(score >= 15 ? .red : score >= 10 ? .orange : .green)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.28))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.green, .yellow, .orange, .red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * CGFloat(score) / 20)
                }
            }
            .frame(height: 9)
        }
    }
}

private struct ResultMetric: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.bold).monospacedDigit())
                Text(unit)
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
    let metrics: (perimeter: Float, area: Float, volume: Float)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wound Measurements")
                .font(.headline)
            Text("Perimeter: \(metrics.perimeter, specifier: "%.2f") cm")
            Text("Area: \(metrics.area, specifier: "%.2f") cm²")
            Text("Volume: \(metrics.volume, specifier: "%.2f") cm³")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ScanControlsBar: View {
    let isDetecting: Bool
    let meshVisible: Bool
    let classificationColors: Bool
    @Binding var showManualControls: Bool
    let onStartScan: () -> Void
    let onReset: () -> Void
    let onToggleMesh: () -> Void
    let onToggleClassification: () -> Void
    let onExport: () -> Void
    let onImageAnalysis: () -> Void
    let onMoreActions: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onStartScan) {
                Label(isDetecting ? "Scanning" : "Scan", systemImage: "viewfinder.circle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)

            IconControl(systemImage: meshVisible ? "cube.fill" : "cube", title: "Mesh", isActive: meshVisible, action: onToggleMesh)
            IconControl(systemImage: classificationColors ? "paintpalette.fill" : "paintpalette", title: "Mesh colors", isActive: classificationColors, action: onToggleClassification)
            IconControl(systemImage: "square.and.arrow.up", title: "Export 3D", isActive: false, action: onExport)

            Button(action: onMoreActions) {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: 44, height: 52)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("More scan actions")
        }
    }
}

private struct IconControl: View {
    let systemImage: String
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 44, height: 52)
        }
        .buttonStyle(.bordered)
        .tint(isActive ? .blue : .gray)
        .accessibilityLabel(title)
    }
}

private struct ManualRefinementBar: View {
    let onStart: () -> Void
    let onFinish: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onStart) {
                Label("Trace", systemImage: "pencil.tip")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            Button(action: onFinish) {
                Label("Finish", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            Button(action: onClear) {
                Label("Clear", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct LiDARScanGuidancePanel: View {
    let instruction: String
    let progress: Double
    let anchorCount: Int
    let vertexCount: Int
    let faceCount: Int
    let isScanning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: isScanning ? "dot.radiowaves.left.and.right" : "cube.transparent")
                    .font(.headline)
                    .foregroundStyle(isScanning ? .blue : .secondary)

                Text(instruction)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)

                Spacer()
            }

            ProgressView(value: progress)
                .tint(.blue)

            HStack(spacing: 12) {
                MeshStat(title: "Surfaces", value: "\(anchorCount)")
                MeshStat(title: "Points", value: compactCount(vertexCount))
                MeshStat(title: "Faces", value: compactCount(faceCount))
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func compactCount(_ value: Int) -> String {
        if value >= 1_000 {
            return String(format: "%.1fk", Double(value) / 1_000.0)
        }
        return "\(value)"
    }
}

private struct MeshStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MoreScanActionsPanel: View {
    let meshViewerActive: Bool
    let onGuidedRefine: () -> Void
    let onToggleMeshViewer: () -> Void
    let onImageAnalysis: () -> Void
    let onReset: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ActionTile(
                    title: meshViewerActive ? "Live Camera" : "3D Mesh View",
                    systemImage: meshViewerActive ? "camera.viewfinder" : "cube.fill",
                    action: onToggleMeshViewer
                )
                ActionTile(title: "Guided Refine", systemImage: "pencil.and.outline", action: onGuidedRefine)
            }

            HStack(spacing: 8) {
                ActionTile(title: "Image Analysis", systemImage: "photo.viewfinder", action: onImageAnalysis)
                ActionTile(title: "Reset Scan", systemImage: "arrow.clockwise", action: onReset)
                ActionTile(title: "Settings", systemImage: "info.circle", action: onSettings)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ActionTile: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
        }
        .buttonStyle(.bordered)
    }
}

final class MetricsManager: ObservableObject {
    @Published var perimeter: Float = 0
    @Published var area: Float = 0
    @Published var volume: Float = 0

    var metrics: (perimeter: Float, area: Float, volume: Float) {
        (perimeter: perimeter, area: area, volume: volume)
    }

    func updateMetrics(perimeter: Float, area: Float, volume: Float) {
        self.perimeter = perimeter
        self.area = area
        self.volume = volume
    }

    func resetMetrics() {
        perimeter = 0
        area = 0
        volume = 0
    }
}

#Preview {
    ContentView()
}
