import SwiftUI
import UIKit
import ARKit
import SceneKit
import Photos
import PhotosUI
import Vision
import CoreImage

struct ARCameraTabView: View {
    @EnvironmentObject private var logManager: MeasurementLogManager
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var analysisText: String? = nil
    @State private var snapshotRequestID: Int = 0
    @State private var showComorbiditySheet = false
    @State private var selectedComorbidities: ComorbidityChecklist? = nil
    @State private var isAnalyzing = false
    @AppStorage("woundServerBaseURL") private var baseURL: String = ""
    @AppStorage("woundAnalysisProvider") private var analysisProviderRaw = WoundAnalysisProvider.onDevice.rawValue
    @AppStorage("woundOnDeviceModelID") private var selectedModelID = OnDeviceModelStore.defaultModelID
    @AppStorage("woundAppMode") private var modeRaw = WoundAppMode.publicPatient.rawValue
    @State private var showSettings = false
    @State private var formattedAnalysis: AttributedString? = nil
    @AppStorage("showLegacyControls") private var showLegacyControls: Bool = false
    @StateObject private var localAnalyzer = OnDeviceWoundAnalyzer()

    @State private var latestAnalysisSummary: AttributedString? = nil
    
    @State private var analyzeStartTime: Date? = nil
    @State private var analysisElapsed: TimeInterval = 0
    @State private var analysisTimer: Timer? = nil

    private var detector: WoundDetector {
        let base = baseURL.isEmpty ? "http://127.0.0.1:3000" : baseURL
        let endpoint = URL(string: "\(base)/api/analyze-wound")!
        return WoundDetector(endpoint: endpoint, session: .shared)
    }

    private var selectedProvider: WoundAnalysisProvider {
        WoundAnalysisProvider(rawValue: analysisProviderRaw) ?? .onDevice
    }

    private var selectedMode: WoundAppMode {
        WoundAppMode(rawValue: modeRaw) ?? .publicPatient
    }

    private var activeModel: OnDeviceModelDescriptor {
        OnDeviceModelStore.shared.model(withID: selectedModelID) ?? .qwen3VL4B
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ARCameraControllerHost(snapshotRequestID: $snapshotRequestID, onSnapshot: handleSnapshot)
                .ignoresSafeArea()

            HStack(spacing: 16) {
                if showLegacyControls {
                    Button {
                        showPicker = true
                    } label: {
                        Label("Upload", systemImage: "square.and.arrow.up.on.square")
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                    }

                    Button {
                        showComorbiditySheet = true
                    } label: {
                        Label("Shutter", systemImage: "camera.shutter.button")
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .sheet(isPresented: $showComorbiditySheet) {
                        ComorbidityChecklistSheet(
                            onUse: { checklist in
                                selectedComorbidities = checklist
                                snapshotRequestID &+= 1 // now trigger the actual capture
                            },
                            onSkip: {
                                selectedComorbidities = nil
                                snapshotRequestID &+= 1 // trigger capture without metadata
                            }
                        )
                    }

                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .sheet(isPresented: $showSettings) {
                        SettingsView()
                    }
                }

                Button {
                    NotificationCenter.default.post(name: NSNotification.Name("RunWoundAnalysisNow"), object: nil)
                } label: {
                    Label("Wound Analysis", systemImage: "scope")
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                }

                Button {
                    showPicker = true
                } label: {
                    Label("Upload Image", systemImage: "photo.on.rectangle")
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(.bottom, 24)
            
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(.top, 16)
                    .padding(.trailing, 16)
                }
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                if let summary = latestAnalysisSummary {
                    Text(summary)
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
        .overlay(alignment: .center) {
            if isAnalyzing {
                ProgressView("Analyzing… (\(String(format: "%.1f", analysisElapsed))s)")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .photosPicker(isPresented: $showPicker, selection: $selectedItem)
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem = newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await analyze(image)
                }
            }
            
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
            AnalysisResultView(rawOutput: item.markdown, mode: selectedMode) { title in
                logManager.add(title: title.isEmpty ? "Analysis" : title, perimeter: 0, area: 0, volume: 0)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SubmitVolumeFeedback"))) { notification in
            guard let userInfo = notification.userInfo,
                  let perimeter = userInfo["perimeter"] as? Float,
                  let area = userInfo["area"] as? Float,
                  let volume = userInfo["volume"] as? Float else {
                print("SubmitVolumeFeedback missing metrics")
                return
            }
            Task { await sendVolumeFeedback(perimeter: perimeter, area: area, volume: volume) }
        }
    }

    private func handleSnapshot(_ image: UIImage) {
        Task { await analyze(image) }
    }

    private func analyze(_ image: UIImage) async {
        isAnalyzing = true
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
            let raw: String
            if selectedProvider == .onDevice {
                raw = try await localAnalyzer.analyze(
                    image: reduced,
                    model: activeModel,
                    prompt: selectedMode.analysisPrompt
                )
            } else {
                let result = try await detector.analyze(
                    image: reduced,
                    metadata: analysisMetadata(mode: selectedMode)
                )
                raw = result.summary
            }
            let t2 = CFAbsoluteTimeGetCurrent()
            print(String(format: "Timing: scale=%.2fs, analysis=%.2fs, total=%.2fs", t1 - t0, t2 - t1, t2 - t0))
            await MainActor.run {
                self.analysisText = raw
                self.formattedAnalysis = SummaryFormatter.formatMarkdown(raw)
                self.latestAnalysisSummary = self.formattedAnalysis
            }
        } catch {
            await MainActor.run {
                let message: String
                if let detectorError = error as? WoundDetector.DetectorError {
                    switch detectorError {
                    case .server(let serverMessage):
                        message = "Analysis failed: \(serverMessage)"
                    case .encodingFailed:
                        message = "Analysis failed: Could not encode image."
                    case .badResponse:
                        message = "Analysis failed: Bad response from server."
                    }
                } else if let urlError = error as? URLError {
                    message = "Network error (\(urlError.code.rawValue)): \(urlError.localizedDescription)"
                } else {
                    message = "Analysis failed: \(error.localizedDescription)"
                }
                self.analysisText = message
                self.formattedAnalysis = SummaryFormatter.formatParagraphs(message)
                self.latestAnalysisSummary = self.formattedAnalysis
            }
        }
    }

    private func analysisMetadata(mode: WoundAppMode) -> [String: String] {
        var metadata = selectedComorbidities?.asDictionary() ?? [:]
        metadata["woundscope_mode"] = mode.rawValue
        metadata["audience"] = mode == .professional ? "professional" : "consumer"
        metadata["output_format"] = "strict_json_with_summary_html"
        metadata["prompt"] = mode.analysisPrompt
        return metadata
    }
    
    private func sendVolumeFeedback(perimeter: Float, area: Float, volume: Float) async {
        let base = baseURL.isEmpty ? "http://127.0.0.1:3000" : baseURL
        guard let url = URL(string: "\(base)/api/feedback") else {
            print("Invalid feedback URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "perimeter_cm": perimeter,
            "area_cm2": area,
            "volume_cm3": volume
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if !(200..<300).contains(http.statusCode) {
                    print("Feedback POST failed: HTTP \(http.statusCode)")
                } else {
                    print("Feedback POST succeeded")
                }
            }
        } catch {
            print("Feedback POST error: \(error)")
        }
    }
}

extension UIImage {
    func scaled(maxDimension: CGFloat) -> UIImage {
        let size = self.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }
        let scale = maxDimension / maxSide
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
    private var loadedModelID: String?

    func analyze(image: UIImage, model: OnDeviceModelDescriptor, prompt: String) async throws -> String {
        guard OnDeviceMNNBridge.isRuntimeAvailable() else {
            throw LocalAnalysisError.deviceRequired
        }
        guard OnDeviceModelStore.shared.isInstalled(model) else {
            throw LocalAnalysisError.modelNotInstalled(model.displayName)
        }

        if loadedModelID != model.id {
            try await load(model)
        }

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
            return "On-device Wound AI requires a physical iPhone or iPad. Use Legacy Server only for explicit testing."
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
    let rawOutput: String
    let mode: WoundAppMode
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: mode.systemImage)
                            .foregroundStyle(mode == .professional ? .indigo : .teal)
                        Text(mode == .professional ? "Professional Analysis" : "Consumer Analysis")
                            .font(.headline)
                        Spacer()
                    }

                    TextField("Save title", text: $title)
                        .textFieldStyle(.roundedBorder)

                    StructuredAnalysisContent(raw: rawOutput)
                        .textSelection(.enabled)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(title)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct StructuredAnalysisContent: View {
    let raw: String

    var body: some View {
        if let object = AIResponseParser.jsonObject(from: raw) {
            JSONAnalysisView(object: object)
        } else if AIResponseParser.looksLikeHTML(raw) {
            HTMLAnalysisView(html: raw)
        } else {
            MarkdownWithCodeBlocksView(markdown: raw)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct JSONAnalysisView: View {
    let object: [String: Any]

    private var orderedKeys: [String] {
        let preferred = [
            "summary_html",
            "wound_bed_observations",
            "periwound_observations",
            "exudate_or_infection_concerns",
            "severity_rationale",
            "what_to_watch",
            "care_questions",
            "when_to_contact_clinician",
            "capture_quality",
            "recommended_review_actions",
            "limitations"
        ]
        let known = preferred.filter { object[$0] != nil }
        let extra = object.keys.filter { !preferred.contains($0) }.sorted()
        return known + extra
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(orderedKeys, id: \.self) { key in
                VStack(alignment: .leading, spacing: 8) {
                    Text(title(for: key))
                        .font(.headline)

                    if key.localizedCaseInsensitiveContains("html"),
                       let html = object[key] as? String {
                        HTMLAnalysisView(html: html)
                    } else {
                        Text(render(value: object[key] ?? ""))
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func title(for key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { word in
                let text = String(word)
                return text.prefix(1).uppercased() + String(text.dropFirst())
            }
            .joined(separator: " ")
    }

    private func render(value: Any) -> String {
        if let string = value as? String { return string }
        if let array = value as? [Any] {
            return array.map { "• \(render(value: $0))" }.joined(separator: "\n")
        }
        if let dict = value as? [String: Any] {
            return dict.keys.sorted().map { "\(title(for: $0)): \(render(value: dict[$0] ?? ""))" }.joined(separator: "\n")
        }
        return String(describing: value)
    }
}

private struct HTMLAnalysisView: View {
    let html: String

    var body: some View {
        Text(attributedHTML)
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributedHTML: AttributedString {
        let wrapped = """
        <style>
        body { font-family: -apple-system; font-size: 16px; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 6px; border-bottom: 1px solid #d0d0d0; text-align: left; }
        </style>
        \(html)
        """
        guard let data = wrapped.data(using: .utf8),
              let ns = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return AttributedString(html)
        }
        return AttributedString(ns)
    }
}

private enum AIResponseParser {
    static func jsonObject(from raw: String) -> [String: Any]? {
        let cleaned = stripFence(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    static func looksLikeHTML(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return lower.contains("<h1") || lower.contains("<h2") || lower.contains("<p") || lower.contains("<ul") || lower.contains("<table")
    }

    private static func stripFence(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("```") else { return text }
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
        guard lines.count >= 2 else { return text }
        var body = Array(lines.dropFirst())
        if body.last?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") == true {
            body.removeLast()
        }
        text = body.map(String.init).joined(separator: "\n")
        return text
    }
}



// MARK: - Markdown rendering with fenced code blocks
private struct MarkdownWithCodeBlocksView: View {
    let markdown: String

    var body: some View {
        let blocks = MarkdownBlockParser.parse(markdown)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                switch block.kind {
                case .markdown(let text):
                    MarkdownText(text: text)

                case .code(let language, let code):
                    CodeBlockView(language: language, code: code)
                }
            }
        }
    }
}

private struct MarkdownBlock: Identifiable {
    enum Kind {
        case markdown(String)
        case code(language: String?, code: String)
    }

    let id = UUID()
    let kind: Kind
}

private enum MarkdownBlockParser {
    static func parse(_ input: String) -> [MarkdownBlock] {
        // Very small, fence-only parser.
        // Supports ```lang\n...``` and preserves everything else as markdown.
        var result: [MarkdownBlock] = []
        let lines = input.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
        var i = 0

        func flushMarkdown(_ buffer: inout String) {
            let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { buffer = ""; return }
            result.append(MarkdownBlock(kind: .markdown(buffer)))
            buffer = ""
        }

        var mdBuffer = ""
        while i < lines.count {
            let line = String(lines[i])
            if line.hasPrefix("```") {
                flushMarkdown(&mdBuffer)

                let lang = line.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
                i += 1
                var codeLines: [String] = []
                while i < lines.count {
                    let l = String(lines[i])
                    if l.hasPrefix("```") { break }
                    codeLines.append(l)
                    i += 1
                }
                // Skip closing fence if present
                if i < lines.count, String(lines[i]).hasPrefix("```") { i += 1 }

                let code = codeLines.joined(separator: "\n")
                result.append(MarkdownBlock(kind: .code(language: lang.isEmpty ? nil : String(lang), code: code)))
                continue
            } else {
                mdBuffer += line
                mdBuffer += "\n"
                i += 1
            }
        }
        flushMarkdown(&mdBuffer)
        return result
    }
}

private struct MarkdownText: View {
    let text: String

    var body: some View {
        // AttributedString's Markdown support does not render fenced code blocks well.
        // We keep code blocks out of this component and render them separately.
        let attributed: AttributedString = (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        )) ?? AttributedString(text)

        return Text(attributed)
            .font(.body)
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CodeBlockView: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let language = language, !language.isEmpty {
                Text(language.uppercased())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separator), lineWidth: 1)
            )
            .contextMenu {
                Button("Copy") {
                    UIPasteboard.general.string = code
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ARCameraControllerHost: UIViewControllerRepresentable {
    @Binding var snapshotRequestID: Int
    let onSnapshot: (UIImage) -> Void

    func makeUIViewController(context: Context) -> ARCameraViewController {
        let vc = ARCameraViewController()
        vc.onSnapshot = onSnapshot
        return vc
    }

    func updateUIViewController(_ uiViewController: ARCameraViewController, context: Context) {
        // When snapshotRequestID changes, trigger a snapshot.
        if context.coordinator.lastHandledRequestID != snapshotRequestID {
            context.coordinator.lastHandledRequestID = snapshotRequestID
            uiViewController.takeSnapshot()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastHandledRequestID: Int = 0
    }
}

final class ARCameraViewController: UIViewController, ARSCNViewDelegate {
    private let sceneView = ARSCNView()
    var onSnapshot: ((UIImage) -> Void)?
    
    private var isSimpleMode: Bool = false
    
    private var meshNodes: [UUID: SCNNode] = [:]
    private var didStartSessionOnce = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupScene()
        
        NotificationCenter.default.addObserver(self, selector: #selector(hideOverlays), name: NSNotification.Name("ARHideOverlays"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showOverlays), name: NSNotification.Name("ARShowOverlays"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(enableSimpleMode), name: NSNotification.Name("ARSimpleModeEnabled"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(disableSimpleMode), name: NSNotification.Name("ARSimpleModeDisabled"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(simpleDetectNow), name: NSNotification.Name("ARSimpleDetectNow"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(simpleDetectNow), name: NSNotification.Name("RunWoundAnalysisNow"), object: nil)
        hideOverlays()
        
        sceneView.preferredFramesPerSecond = 60
        sceneView.automaticallyUpdatesLighting = true
        
        sceneView.showsStatistics = false
        sceneView.overlaySKScene = nil
        sceneView.automaticallyUpdatesLighting = false
        sceneView.scene.background.contents = nil
        sceneView.technique = nil

        // Disable user interaction and any gesture-based measurement
        sceneView.gestureRecognizers?.forEach { sceneView.removeGestureRecognizer($0) }
        if let recognizers = sceneView.gestureRecognizers, !recognizers.isEmpty {
            print("Unexpected gesture recognizers still present in viewDidLoad: ", recognizers)
        } else {
            print("No gesture recognizers on sceneView in viewDidLoad.")
        }
        sceneView.isUserInteractionEnabled = false
        // Clear any camera filters/post-processing that could draw outlines
        sceneView.pointOfView?.camera?.wantsHDR = false
        sceneView.pointOfView?.camera?.wantsExposureAdaptation = false
        sceneView.pointOfView?.camera?.motionBlurIntensity = 0
        sceneView.pointOfView?.camera?.screenSpaceAmbientOcclusionIntensity = 0
        sceneView.pointOfView?.camera?.colorFringeIntensity = 0
        sceneView.pointOfView?.camera?.bloomIntensity = 0
        sceneView.pointOfView?.camera?.vignettingIntensity = 0
        sceneView.pointOfView?.camera?.grainIntensity = 0
        sceneView.pointOfView?.camera?.contrast = 1.0
        sceneView.pointOfView?.camera?.saturation = 1.0
        sceneView.pointOfView?.filters = nil
        sceneView.antialiasingMode = .none
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.debugOptions = []
    }

    private func setupScene() {
        view.addSubview(sceneView)
        sceneView.frame = view.bounds
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.delegate = self
        sceneView.scene = SCNScene()
        sceneView.debugOptions = []
    }

    private func startSession() {
        let config = ARWorldTrackingConfiguration()
        if isSimpleMode {
            // Keep it minimal in simple mode
            config.planeDetection = []
            // Do not set sceneReconstruction in simple mode to keep it minimal
            config.environmentTexturing = .none
        } else {
            // Non-simple: enable robust scanning for accurate points
            config.planeDetection = [.horizontal, .vertical]
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
                config.sceneReconstruction = .meshWithClassification
            } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                config.sceneReconstruction = .mesh
            }
            config.environmentTexturing = .automatic
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                config.frameSemantics.insert(.sceneDepth)
            }
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
                config.frameSemantics.insert(.smoothedSceneDepth)
            }
        }
        let runOptions: ARSession.RunOptions
        if !didStartSessionOnce {
            runOptions = [.resetTracking, .removeExistingAnchors]
            didStartSessionOnce = true
        } else {
            runOptions = []
        }
        sceneView.session.run(config, options: runOptions)
        // Ensure no residual nodes/overlays
        sceneView.debugOptions = []
        // Removed clearing rootNode children to keep mesh occlusion nodes persistent
        sceneView.technique = nil
        sceneView.pointOfView?.filters = nil
        sceneView.gestureRecognizers?.forEach { sceneView.removeGestureRecognizer($0) }
        if let recognizers = sceneView.gestureRecognizers, !recognizers.isEmpty {
            print("Unexpected gesture recognizers still present in startSession: ", recognizers)
        } else {
            print("No gesture recognizers on sceneView in startSession.")
        }
        sceneView.isUserInteractionEnabled = false
    }

    // MARK: - Mesh Occlusion Support
    private func makeGeometry(from meshAnchor: ARMeshAnchor) -> SCNGeometry? {
        let geometry = meshAnchor.geometry
        guard geometry.vertices.count > 0, geometry.faces.count > 0 else { return nil }

        // Vertex source
        let vertexBuffer = geometry.vertices.buffer
        let vertexSource = SCNGeometrySource(buffer: vertexBuffer,
                                             vertexFormat: .float3,
                                             semantic: .vertex,
                                             vertexCount: geometry.vertices.count,
                                             dataOffset: geometry.vertices.offset,
                                             dataStride: geometry.vertices.stride)

        // Normal source (optional). If not available, SceneKit can compute per-pixel normals; we keep it nil.
        let sources: [SCNGeometrySource] = [vertexSource]

        // Faces (triangles)
        let facesDesc = geometry.faces
        let indexCount = facesDesc.count * facesDesc.indexCountPerPrimitive
        let element = SCNGeometryElement(data: Data(bytesNoCopy: facesDesc.buffer.contents(),
                                                    count: indexCount * MemoryLayout<UInt32>.size,
                                                    deallocator: .none),
                                         primitiveType: .triangles,
                                         primitiveCount: facesDesc.count,
                                         bytesPerIndex: MemoryLayout<UInt32>.size)
        let scnGeom = SCNGeometry(sources: sources, elements: [element])
        // Occlusion-only material: write depth, skip color
        let mat = SCNMaterial()
        mat.colorBufferWriteMask = []
        mat.isDoubleSided = true
        mat.lightingModel = .constant
        scnGeom.firstMaterial = mat
        return scnGeom
    }

    private func upsertOcclusionNode(for meshAnchor: ARMeshAnchor, attachTo parent: SCNNode) {
        let id = meshAnchor.identifier
        let node = meshNodes[id] ?? SCNNode()
        node.geometry = makeGeometry(from: meshAnchor)
        node.simdTransform = meshAnchor.transform
        if node.parent == nil { parent.addChildNode(node) }
        meshNodes[id] = node
    }

    private func removeOcclusionNode(for anchor: ARAnchor) {
        guard let node = meshNodes.removeValue(forKey: anchor.identifier) else { return }
        node.removeFromParentNode()
    }

    private func setupSnapshotButton() {
        let button: UIButton
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.filled()
            config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.3)
            config.baseForegroundColor = .white
            config.cornerStyle = .capsule
            config.image = UIImage(systemName: "circle.fill")
            config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)

            button = UIButton(configuration: config, primaryAction: nil)
        } else {
            button = UIButton(type: .system)
            button.setImage(UIImage(systemName: "circle.fill"), for: .normal)
            button.tintColor = .white
            button.backgroundColor = UIColor.black.withAlphaComponent(0.3)
            button.layer.cornerRadius = 28
            button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(takeSnapshot), for: .touchUpInside)

        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])
    }

    @objc func takeSnapshot() {
        let image = sceneView.snapshot()
        self.onSnapshot?(image)
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else { return }
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        }
    }

    @objc private func hideOverlays() {
        // Remove any existing visualization nodes and disable debug visuals
        sceneView.debugOptions = []
        // Removed removing all children from rootNode to keep mesh occlusion nodes persistent
        sceneView.technique = nil
        sceneView.pointOfView?.filters = nil
    }

    @objc private func showOverlays() {
        // Optional: enable minimal debug options if desired, leaving it empty to keep clean UI
        sceneView.debugOptions = []
    }

    @objc private func enableSimpleMode() {
        isSimpleMode = true
        startSession()
        hideOverlays()
    }
    @objc private func disableSimpleMode() {
        isSimpleMode = false
        startSession()
    }

    @objc private func simpleDetectNow() {
        self.takeSnapshot()
    }
    
    // MARK: - ARSCNViewDelegate (mesh updates for occlusion)
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let mesh = anchor as? ARMeshAnchor else { return }
        upsertOcclusionNode(for: mesh, attachTo: node)
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let mesh = anchor as? ARMeshAnchor else { return }
        upsertOcclusionNode(for: mesh, attachTo: node)
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("MeshDidUpdate"), object: nil)
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        removeOcclusionNode(for: anchor)
    }
}
