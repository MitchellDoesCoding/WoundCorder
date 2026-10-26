import SwiftUI
import UIKit
import AVFoundation
import PhotosUI
import Vision
import CoreImage

struct ARCameraTabView: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    var onFinish: (() throws -> Void)? = nil
    var measurementContext: WoundAnalysisContext? = nil
    var patientID: UUID? = nil
    var patientName: String? = nil
    var patientProfile = PatientProfile()
    var woundIntake = WoundIntakeData()
    @State private var recordID = UUID()
    @State private var closeError: String?
    @State private var trackingWoundID = UUID()
    @State private var resultCNN: WoundSemanticResult?
    @State private var resultPhoto: UIImage?
    @State private var resultUsedContext = false
    @State private var resultMeasurement: WoundAnalysisContext?
    @State private var semanticService = WoundSemanticService()
    @EnvironmentObject private var logManager: MeasurementLogManager
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    @State private var pendingLibraryImage: UIImage?
    @State private var confirmImageAssociation = false
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var analysisText: String? = nil
    @State private var snapshotRequestID: Int = 0
    @State private var isAnalyzing = false
    @AppStorage("woundAnalysisProvider") private var analysisProviderRaw = WoundAnalysisProvider.onDevice.rawValue
    @AppStorage("woundOnDeviceModelID") private var selectedModelID = OnDeviceModelStore.defaultModelID
    @AppStorage("woundAppMode") private var modeRaw = WoundAppMode.publicPatient.rawValue
    @State private var showSettings = false
    @AppStorage("woundCombinedAnalysisDefault.v1") private var appliedCombinedDefault = false
    @State private var formattedAnalysis: AttributedString? = nil
    @StateObject private var localAnalyzer = OnDeviceWoundAnalyzer()

    @State private var latestAnalysisSummary: AttributedString? = nil
    
    @State private var analyzeStartTime: Date? = nil
    @State private var analysisElapsed: TimeInterval = 0
    @State private var analysisTimer: Timer? = nil

    private var selectedProvider: WoundAnalysisProvider {
        guard WoundDeviceCapacity.canRunContext else { return .semanticCNN }
        return WoundAnalysisProvider(rawValue: analysisProviderRaw) ?? .semanticCNN
    }

    private var selectedMode: WoundAppMode {
        WoundAppMode(rawValue: modeRaw) ?? .publicPatient
    }

    private var activeModel: OnDeviceModelDescriptor {
        OnDeviceModelStore.shared.model(withID: selectedModelID) ?? .qwen35Q4KS
    }

    private var cameraContent: some View {
        ZStack(alignment: .bottom) {
            ARCameraControllerHost(snapshotRequestID: $snapshotRequestID, onSnapshot: handleSnapshot, onError: { message in
                resultCNN = nil; resultPhoto = nil; resultMeasurement = nil; analysisText = message
            })
                .ignoresSafeArea()

            HStack(spacing: 16) {
                Button {
                    snapshotRequestID &+= 1
                } label: {
                    Label(WoundL10n.text("Take photo"), systemImage: "scope")
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                }

                Button {
                    showPicker = true
                } label: {
                    Label(WoundL10n.text("Choose photo"), systemImage: "photo.on.rectangle")
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(.bottom, 24)
            .disabled(isAnalyzing)
            
            VStack {
                HStack {
                    Menu {
                        Picker(WoundL10n.text("AI model"), selection: $analysisProviderRaw) {
                            ForEach(WoundAnalysisProvider.allCases) { provider in
                                Text(WoundL10n.text(provider.title)).tag(provider.rawValue).disabled(provider == .onDevice && !WoundDeviceCapacity.canRunContext)
                            }
                        }
                        Button(WoundL10n.text("AI Options")) { showSettings = true }
                    } label: {
                        Label(WoundL10n.text(selectedProvider.title), systemImage: "brain.head.profile")
                            .padding(10)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .disabled(isAnalyzing)
                    Spacer()
                    Button {
                        do { try saveAndFinish(title: "", woundID: trackingWoundID) }
                        catch { closeError = error.localizedDescription }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(.top, 16)
                    .padding(.trailing, 16)
                    .disabled(isAnalyzing)
                }
                if selectedProvider == .onDevice && !OnDeviceModelStore.shared.isInstalled(activeModel) {
                    Button(WoundL10n.text("Download health-context model in AI Options")) { showSettings = true }
                        .font(.footnote).padding(8).background(.regularMaterial, in: Capsule())
                    Text(WoundL10n.text("Until installed, photo checks use the CNN only.")).font(.caption)
                        .padding(6).background(.regularMaterial)
                }
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                if let measurementContext {
                    Text(WoundL10n.text("LiDAR measurements attached\nArea \(measurementContext.areaCM2, specifier: "%.2f") cm² · Volume \(measurementContext.volumeCM3, specifier: "%.2f") cm³\nTake a photo of the same wound to continue."))
                        .font(.caption)
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .padding(.top, 52)
                }
                if let summary = latestAnalysisSummary {
                    Text(summary)
                        .lineLimit(3)
                        .font(.footnote)
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.top, .leading], 16)
            .allowsHitTesting(false)
        }
    }

    var body: some View {
        cameraContent
        .overlay(alignment: .center) {
            if isAnalyzing {
                ProgressView(WoundL10n.text("Analyzing… (\(String(format: "%.1f", analysisElapsed))s)"))
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .onAppear {
            if !appliedCombinedDefault {
                if WoundDeviceCapacity.canRunContext { analysisProviderRaw = WoundAnalysisProvider.onDevice.rawValue }
                appliedCombinedDefault = true
            }
        }
        .tint(selectedMode.wsPrimary)
        .alert(WoundL10n.text("Could not save"), isPresented: Binding(get: { closeError != nil }, set: { if !$0 { closeError = nil } })) {
            Button(WoundL10n.text("OK")) { closeError = nil }
        } message: { Text(WoundL10n.text(closeError ?? "Please try again.")) }
        .sheet(isPresented: $showSettings) { WoundAIModelSheet() }
        .photosPicker(isPresented: $showPicker, selection: $selectedItem, matching: .images)
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem = newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    if measurementContext != nil {
                        pendingLibraryImage = image
                        confirmImageAssociation = true
                    } else {
                        await analyze(image, measurement: nil)
                    }
                } else {
                    analysisText = "This photo could not be opened. Choose another photo and try again."
                    resultCNN = nil
                    resultPhoto = nil
                }
                selectedItem = nil
            }
        }
        .confirmationDialog(WoundL10n.text("Is this the wound you just measured?"), isPresented: $confirmImageAssociation, titleVisibility: .visible) {
            Button(WoundL10n.text("Use attached measurements")) {
                if let image = pendingLibraryImage {
                    Task { await analyze(image, measurement: measurementContext) }
                }
                pendingLibraryImage = nil
            }
            Button(WoundL10n.text("Analyze without measurements")) {
                if let image = pendingLibraryImage {
                    Task { await analyze(image, measurement: nil) }
                }
                pendingLibraryImage = nil
            }
            Button(WoundL10n.text("Cancel"), role: .cancel) { pendingLibraryImage = nil }
        }
        .fullScreenCover(
            item: Binding(
                get: { analysisText.map { AnalysisResult(markdown: $0) } },
                set: { _ in
                    analysisText = nil
                    formattedAnalysis = nil
                }
            )
        ) { item in
            AnalysisResultView(rawOutput: item.markdown, mode: selectedMode, cnn: resultCNN, usedContext: resultUsedContext, photo: resultPhoto, profile: patientProfile, intake: woundIntake, measurement: resultMeasurement, patientID: patientID, woundID: $trackingWoundID) { title in
                try saveAndFinish(title: title, woundID: trackingWoundID)
            }
        }
    }

    private func saveAndFinish(title: String, woundID: UUID) throws {
        if let image = resultPhoto {
            let result = resultCNN ?? WoundSemanticResult(rankedClasses: [], semanticProbabilities: [:], embedding: [], isClassificationUncertain: true)
            try WoundPhotoCheckStore.shared.save(title: title.isEmpty ? "\(woundIntake.laterality.rawValue) \(woundIntake.bodyArea.rawValue)" : title,
                patientID: patientID, profile: patientProfile, intake: woundIntake, mode: selectedMode,
                combined: resultUsedContext, comments: analysisText ?? "", result: result,
                measurement: resultMeasurement, image: image, recordID: recordID, woundID: woundID)
        }
        try onFinish?()
        NotificationCenter.default.post(name: Notification.Name("WoundWorkflowCompleted"), object: nil)
        dismiss()
    }

    private func handleSnapshot(_ image: UIImage) {
        Task { await analyze(image, measurement: measurementContext) }
    }

    private func analyze(_ image: UIImage, measurement: WoundAnalysisContext?) async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        recordID = UUID()
        resultMeasurement = measurement
        resultPhoto = image
        resultCNN = nil
        resultUsedContext = false
        self.analyzeStartTime = Date()
        self.analysisElapsed = 0
        self.analysisTimer?.invalidate()
        self.analysisTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            if let start = self.analyzeStartTime {
                self.analysisElapsed = Date().timeIntervalSince(start)
            }
        }
        defer {
            isAnalyzing = false
            self.analysisTimer?.invalidate()
            self.analysisTimer = nil
        }

        do {
            let t0 = CFAbsoluteTimeGetCurrent()
            let reduced = image.scaled(maxDimension: 1024)
            let t1 = CFAbsoluteTimeGetCurrent()
            let provider = selectedProvider
            let mode = selectedMode
            let model = activeModel
            var additional = woundIntake.comorbidities.asDictionary()
            additional.merge(patientProfile.inferenceMetadata) { _, value in value }
            additional["wound_duration"] = woundIntake.dateWounded.rawValue
            additional["body_area"] = woundIntake.bodyArea.rawValue
            additional["laterality"] = woundIntake.laterality.rawValue
            let cnn = try await semanticService.predict(image: image)
            resultCNN = cnn
            guard cnn.isPhotoAdequate else {
                analysisText = "Please try a clearer photo that shows the wound and nearby skin."
                return
            }
            guard !cnn.isClassificationUncertain else {
                analysisText = ""
                latestAnalysisSummary = AttributedString(WoundContextComments.unsureMessage)
                return
            }
            let prompt = WoundAnalysisPrompt.make(
                base: mode.analysisPrompt + "\n" + WoundLanguage.current.responseInstruction + " Keep JSON keys, assessment values, and candidate_labels exactly as specified in English.",
                measurement: measurement,
                additional: additional,
                cnn: try cnn.report(measurement: nil)
            )
            let raw: String
            switch provider {
            case .semanticCNN:
                raw = ""
            case .onDevice:
                do {
                    let output = try await localAnalyzer.analyze(image: reduced, model: model, prompt: prompt)
                    guard let comments = WoundContextComments.parse(output, allowedLabels: Array(cnn.rankedClasses.prefix(2).map(\.label))),
                          comments.assessment != nil else {
                        throw LocalAnalysisError.inferenceFailed("The added comments were not in the expected format. Please try again.")
                    }
                    raw = output
                    resultUsedContext = true
                } catch {
                    raw = "Health context was not added. Photo Check results are shown below. " + error.localizedDescription
                }
            }
            let t2 = CFAbsoluteTimeGetCurrent()
            print(String(format: "Timing: scale=%.2fs, analysis=%.2fs, total=%.2fs", t1 - t0, t2 - t1, t2 - t0))
            await MainActor.run {
                self.analysisText = raw
                self.formattedAnalysis = AttributedString(raw.isEmpty ? "Your photo check is ready." : WoundContextComments.displayText(raw))
                self.latestAnalysisSummary = self.formattedAnalysis
            }
        } catch {
            await MainActor.run {
                let message = "We could not check this photo. Try again with a clear, well-lit photo. " + error.localizedDescription
                self.analysisText = message
                self.formattedAnalysis = AttributedString(message)
                self.latestAnalysisSummary = self.formattedAnalysis
            }
        }
    }

}

extension UIImage {
    func scaled(maxDimension: CGFloat) -> UIImage {
        let size = self.size
        let maxSide = max(size.width, size.height)
        guard maxSide > 0 else { return self }
        let scale = min(1, maxDimension / maxSide)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
        defer { UIGraphicsEndImageContext() }
        self.draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext() ?? self
    }
}

@MainActor
final class OnDeviceWoundAnalyzer: ObservableObject {
    private let bridge = OnDeviceMNNBridge()
    private let ggufBridge = OnDeviceGGUFBridge()
    private var loadedModelID: String?

    func analyze(image: UIImage, model: OnDeviceModelDescriptor, prompt: String) async throws -> String {
        guard WoundDeviceCapacity.canRunContext, model.isRuntimeSupported else {
            throw LocalAnalysisError.deviceRequired
        }
        guard OnDeviceModelStore.shared.isInstalled(model) else {
            throw LocalAnalysisError.modelNotInstalled(model.displayName)
        }

        if model.runtime == .gguf {
            bridge.unloadModel()
            loadedModelID = nil
            let folder = OnDeviceModelStore.shared.modelDirectory(for: model)
            return try await withCheckedThrowingContinuation { continuation in
                ggufBridge.analyze(image,
                    modelPath: folder.appendingPathComponent(model.modelFileName ?? "Qwen_Qwen3.5-4B-Q4_K_S.gguf").path,
                    visionPath: folder.appendingPathComponent(model.visionFileName ?? "mmproj-Qwen_Qwen3.5-4B-f16.gguf").path,
                    prompt: prompt) { output, error in
                    if let output { continuation.resume(returning: output) }
                    else { continuation.resume(throwing: LocalAnalysisError.inferenceFailed(error ?? "The model could not finish.")) }
                }
            }
        }

        try await load(model)

        return try await withCheckedThrowingContinuation { continuation in
            bridge.analyze(image, prompt: prompt, maxTokens: 768) { output, error in
                if let output, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: LocalAnalysisError.inferenceFailed(error ?? "The local model did not return a response."))
                }
            }
        }
    }

    private func load(_ model: OnDeviceModelDescriptor) async throws {
        let path = OnDeviceModelStore.shared.modelDirectory(for: model).path
        try await withCheckedThrowingContinuation { continuation in
            bridge.loadModel(atPath: path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: LocalAnalysisError.inferenceFailed(error ?? "The model could not be loaded."))
                }
            }
        }
        loadedModelID = model.id
    }
}

enum LocalAnalysisError: LocalizedError {
    case deviceRequired
    case modelNotInstalled(String)
    case inferenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .deviceRequired:
            return "This model cannot run on this device or in this build. Use Photo Check or select a supported model in Settings."
        case .modelNotInstalled(let name):
            return "\(name) is not installed. Open Settings > Wound AI > Models & Privacy to download or import it."
        case .inferenceFailed(let message):
            return message
        }
    }
}

private struct AnalysisResult: Identifiable {
    let id = UUID()
    let markdown: String
}

private struct AnalysisResultView: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let rawOutput: String
    let mode: WoundAppMode
    let cnn: WoundSemanticResult?
    let usedContext: Bool
    let photo: UIImage?
    let profile: PatientProfile
    let intake: WoundIntakeData
    let measurement: WoundAnalysisContext?
    let patientID: UUID?
    @Binding var woundID: UUID
    @ObservedObject private var records = WoundPhotoCheckStore.shared
    @State private var newWoundID = UUID()
    @State private var showShare = false
    let onSave: (String) throws -> Void
    @State private var saveError: String?

    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""

    private var existingWounds: [SavedPhotoCheck] {
        var seen = Set<UUID>()
        return records.items.filter {
            $0.patientID == patientID && $0.intake.bodyArea == intake.bodyArea &&
            $0.intake.laterality == intake.laterality && seen.insert($0.woundID ?? $0.id).inserted
        }
    }
    private func finish() {
        do { try onSave(title) } catch { saveError = error.localizedDescription }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: mode.systemImage)
                            .foregroundStyle(mode == .professional ? .indigo : .teal)
                        Text(WoundL10n.text(mode == .professional ? "Professional Analysis" : "Your photo check"))
                            .font(.headline)
                        Spacer()
                    }

                    Picker(WoundL10n.text("Track this wound"), selection: $woundID) {
                        Text(WoundL10n.text("New wound")).tag(newWoundID)
                        ForEach(existingWounds) { record in
                            Text("\(record.title) · \(record.date.woundFormatted(date: .abbreviated, time: .omitted))").tag(record.woundID ?? record.id)
                        }
                    }
                    Text(WoundL10n.text("Choose an earlier wound only if this is the same wound.")).font(.caption).foregroundStyle(.secondary)
                    TextField(WoundL10n.text("Optional check-in title"), text: $title)
                        .textFieldStyle(.roundedBorder)

                    if let cnn {
                        WoundEducationResults(result: cnn, mode: mode, combined: usedContext, contextComments: rawOutput)
                    }
                    if let measurement { GroupBox(WoundL10n.text("Attached measurements")) { Text(WoundL10n.text(measurement.shareText)).frame(maxWidth: .infinity, alignment: .leading) } }
                    if !rawOutput.isEmpty, cnn?.isClassificationUncertain != true {
                        WoundContextCommentsView(raw: rawOutput).textSelection(.enabled)
                    }
                    Button { showShare = true } label: {
                        Label(WoundL10n.text("Share with WoundCorder"), systemImage: "envelope").frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.borderedProminent)
                    Text(WoundL10n.text("You choose what to include and review the email before sending.")).font(.footnote).foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showShare) {
                WoundEmailShareView(photo: photo, profile: profile, intake: intake, analysis: WoundEducationResults.shareText(result: cnn, mode: mode, combined: usedContext, contextComments: rawOutput) + "\n" + (cnn?.isClassificationUncertain == true ? "" : WoundContextComments.displayText(rawOutput)) + (measurement.map { "\n\n" + $0.shareText } ?? ""))
            }
            .interactiveDismissDisabled()
            .onAppear { newWoundID = woundID }
            .navigationTitle(WoundL10n.text("Analysis"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(WoundL10n.text("Close")) { finish() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(WoundL10n.text("Save & Home")) { finish() }
                }
            }
            .alert(WoundL10n.text("Could not save"), isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button(WoundL10n.text("OK")) { saveError = nil }
            } message: { Text(WoundL10n.text(saveError ?? "Please try again.")) }
        }
    }
}

private struct ARCameraControllerHost: UIViewControllerRepresentable {
    @Binding var snapshotRequestID: Int
    let onSnapshot: (UIImage) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> ARCameraViewController {
        let vc = ARCameraViewController()
        vc.onSnapshot = onSnapshot
        vc.onError = onError
        return vc
    }

    func updateUIViewController(_ uiViewController: ARCameraViewController, context: Context) {
        // When snapshotRequestID changes, trigger a snapshot.
        if context.coordinator.lastHandledRequestID != snapshotRequestID {
            context.coordinator.lastHandledRequestID = snapshotRequestID
            uiViewController.takeSnapshot()
        }
    }

    static func dismantleUIViewController(_ controller: ARCameraViewController, coordinator: Coordinator) { controller.shutdown() }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastHandledRequestID: Int = 0
    }
}

/// Photo capture deliberately has no AR session, mesh, global measurement events, or Photos-library writes.
final class ARCameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    var onSnapshot: ((UIImage) -> Void)?
    var onError: ((String) -> Void)?
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "ai.woundcorder.photo-capture")
    private var preview: AVCaptureVideoPreviewLayer?
    // Main-thread state: preview and photo need separate sensor-aware angles.
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewRotationObservation: NSKeyValueObservation?
    private var configured = false // Accessed only on queue.
    private var visible = false // Accessed only on main thread.
    private var capturing = false
    private let message = UILabel()
    private var observers: [NSObjectProtocol] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer); preview = layer
        message.textColor = .white; message.numberOfLines = 0; message.textAlignment = .center
        message.text = WoundL10n.text("Starting camera…")
        view.addSubview(message)
        observers = [
            NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.stop() },
            NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in if self?.visible == true { self?.authorizeAndStart() } }
        ]
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
        message.frame = view.bounds.insetBy(dx: 30, dy: 120)
        updatePreviewRotation()
    }
    private func configureRotation(for device: AVCaptureDevice) {
        if rotationCoordinator == nil {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: preview)
            rotationCoordinator = coordinator
            previewRotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview,
                                                              options: [.initial, .new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.updatePreviewRotation() }
            }
        }
        updatePreviewRotation()
    }

    private func updatePreviewRotation() {
        guard let coordinator = rotationCoordinator, let connection = preview?.connection else { return }
        let angle = coordinator.videoRotationAngleForHorizonLevelPreview
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        CATransaction.commit()
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); visible = true; authorizeAndStart() }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); visible = false; stop() }
    func shutdown() {
        visible = false; onSnapshot = nil; onError = nil
        previewRotationObservation?.invalidate()
        previewRotationObservation = nil
        rotationCoordinator = nil
        observers.forEach(NotificationCenter.default.removeObserver); observers = []
        stop()
    }
    private func stop() { queue.async { [self] in if session.isRunning { session.stopRunning() } } }
    private func authorizeAndStart() {
        guard visible else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in DispatchQueue.main.async { self?.authorizeAndStart() } }
        default: message.text = WoundL10n.text("Camera access is off. You can choose a photo, or allow camera access in Settings.")
        }
    }
    private func start() {
        queue.async { [self] in
            do {
                if !configured {
                    session.beginConfiguration()
                    defer { session.commitConfiguration() }
                    session.sessionPreset = .photo
                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw CaptureError.unavailable }
                    let input = try AVCaptureDeviceInput(device: device)
                    guard session.canAddInput(input), session.canAddOutput(output) else { throw CaptureError.unavailable }
                    session.addInput(input); session.addOutput(output); configured = true
                }
                if !session.isRunning { session.startRunning() }
                let camera = (session.inputs.first as? AVCaptureDeviceInput)?.device
                DispatchQueue.main.async { [weak self] in
                    guard let self, visible else { return }
                    if let camera { configureRotation(for: camera) }
                    message.text = nil
                }
            } catch {
                DispatchQueue.main.async { [weak self] in self?.message.text = WoundL10n.text("Camera is unavailable. Use Choose photo instead.") }
            }
        }
    }
    func takeSnapshot() {
        guard visible, !capturing else { return }
        guard let rotationCoordinator else {
            onError?("Camera is still starting. Please try again.")
            return
        }
        capturing = true
        let angle = rotationCoordinator.videoRotationAngleForHorizonLevelCapture
        queue.async { [self] in
            guard configured, session.isRunning else {
                DispatchQueue.main.async { [weak self] in self?.capturing = false; self?.onError?("Camera is not ready. Choose a photo or try again.") }; return
            }
            if let connection = output.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = false
                }
            }
            let settings = AVCapturePhotoSettings(); settings.flashMode = .off
            output.capturePhoto(with: settings, delegate: self)
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = error == nil ? photo.fileDataRepresentation().flatMap(UIImage.init(data:)) : nil
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }; capturing = false
            guard visible else { return }
            if let image { onSnapshot?(image) } else { onError?("The photo could not be taken. Please try again.") }
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        guard error != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, capturing else { return }
            capturing = false
            if visible { onError?("The camera could not finish taking the photo. Please try again.") }
        }
    }
    private enum CaptureError: Error { case unavailable }
}
