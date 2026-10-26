import Combine
import CryptoKit
import Foundation

enum WoundAnalysisProvider: String, CaseIterable, Identifiable {
    case semanticCNN
    case onDevice
    var id: String { rawValue }
    var title: String {
        let professional = UserDefaults.standard.string(forKey: "woundAppMode") == WoundAppMode.professional.rawValue
        return name(professional: professional)
    }
    func name(professional: Bool) -> String {
        self == .semanticCNN ? (professional ? "Image-Only Analysis" : "Photo Check") : (professional ? "Image + Clinical Context" : "Photo + Health Context")
    }
    var explanation: String {
        self == .semanticCNN ? "Checks the photo for wound and tissue types. Works on this device without a download." : "Checks the photo and uses the health details you choose to add. Needs a downloaded model and more device memory."
    }
}

enum WoundDeviceCapacity {
    // Conservative eligibility policy, not a guarantee against iOS memory pressure.
    static var hasEnoughMemory: Bool { ProcessInfo.processInfo.physicalMemory >= 8_000_000_000 }
    static var canRunContext: Bool { hasEnoughMemory && (OnDeviceMNNBridge.isRuntimeAvailable() || OnDeviceGGUFBridge.isRuntimeAvailable()) }
    static var explanation: String {
        hasEnoughMemory ? "This device has enough total memory for the supported context model. Close other apps if analysis stops." : "This device has less than 8 GB of memory. Photo Check is selected to help the app run smoothly."
    }
}

enum OnDeviceModelRuntime: String, Codable {
    case mnn
    case gguf
}

struct OnDeviceModelFile: Codable, Hashable {
    let name: String
    let byteCount: Int64
    let sha256: String
}

struct OnDeviceModelDescriptor: Codable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let detail: String
    let runtime: OnDeviceModelRuntime
    let runtimeVersion: String
    let sourceBaseURL: String?
    let revision: String?
    let localFolderName: String
    let files: [OnDeviceModelFile]
    let isBuiltIn: Bool
    var modelFileName: String? = nil
    var visionFileName: String? = nil

    var totalByteCount: Int64 {
        files.reduce(0) { $0 + $1.byteCount }
    }

    var isRuntimeSupported: Bool { true }

    static let qwen35Q4KS = OnDeviceModelDescriptor(
        id: "qwen3.5-4b-q4-k-s", displayName: "Qwen3.5-4B (Q4_K_S)",
        detail: "Recommended. Private photo and health-context analysis. Downloads the model and its vision file.",
        runtime: .gguf, runtimeVersion: "llama.cpp b11577",
        sourceBaseURL: "https://huggingface.co/bartowski/Qwen_Qwen3.5-4B-GGUF/resolve",
        revision: "4168f45a16a1290d65a4ec0fa312ae917a4c15d6", localFolderName: "qwen3.5-4b-q4-k-s",
        files: [
            OnDeviceModelFile(name: "Qwen_Qwen3.5-4B-Q4_K_S.gguf", byteCount: 2846156768, sha256: "3a6e5e8144696a87d17f136b06fce7fe5008a42737938056df13e11ddba4a01b"),
            OnDeviceModelFile(name: "mmproj-Qwen_Qwen3.5-4B-f16.gguf", byteCount: 672423488, sha256: "659b59dd44b73b1cd34af6cc424669484b06dc80f4340adf8ea84ad776eef813")
        ], isBuiltIn: true
    )

    static let qwen3VL4B = OnDeviceModelDescriptor(
        id: "qwen3-vl-4b-instruct-mnn",
        displayName: "Qwen3-VL-4B",
        detail: "4-bit vision-language model for private image analysis",
        runtime: .mnn,
        runtimeVersion: "MNN 3.5.0",
        sourceBaseURL: "https://huggingface.co/taobao-mnn/Qwen3-VL-4B-Instruct-MNN/resolve",
        revision: "5c00738180f120067d51306ecf365015cdbbabcf",
        localFolderName: "qwen3-vl-4b-instruct-mnn",
        files: [
            OnDeviceModelFile(
                name: "config.json",
                byteCount: 605,
                sha256: "1ed5c6e65459fdc4b0c33319715b763005013ba8580dd3c687bd2651546ca2a4"
            ),
            OnDeviceModelFile(
                name: "llm.mnn",
                byteCount: 591_728,
                sha256: "1214d79288201d4bd2226cb435ed85d83aea4a35b2a59634ca9116f78143e382"
            ),
            OnDeviceModelFile(
                name: "llm.mnn.json",
                byteCount: 1_245_003,
                sha256: "8fa8b23545be87bfca5d11d3180c2ba9cf1def961738c7edbbe8876ff03e21ec"
            ),
            OnDeviceModelFile(
                name: "llm.mnn.weight",
                byteCount: 2_709_972_658,
                sha256: "387576d52e7a297e3e6de837c60c25e364cd62c6244f878633097064bea0a245"
            ),
            OnDeviceModelFile(
                name: "llm_config.json",
                byteCount: 6_446,
                sha256: "907a48df99ba73e78a01ba55e05bb58567f78eb75f9233aa8f58bfbbabe8cf45"
            ),
            OnDeviceModelFile(
                name: "tokenizer.txt",
                byteCount: 3_193_555,
                sha256: "7119de4966cc6a8ae87d7f083e65b315282d06c3122fdd41ce783fdd2d3c1ca2"
            ),
            OnDeviceModelFile(
                name: "visual.mnn",
                byteCount: 502_512,
                sha256: "fb7e1923db713c6607fd2fb9eae5fd7488aff9f454b8067ab558370f84010b2b"
            ),
            OnDeviceModelFile(
                name: "visual.mnn.weight",
                byteCount: 242_953_564,
                sha256: "b48c901ffe64d1615da93992f3c0508ecf51856b016c424cd96de27114e85694"
            )
        ],
        isBuiltIn: true
    )
}

enum ModelTransferState: Equatable {
    case idle
    case downloading(modelID: String, fileName: String)
    case verifying(modelID: String, fileName: String)
    case importing
    case installed(modelID: String)
    case failed(modelID: String?, message: String)
}

final class OnDeviceModelStore: NSObject, ObservableObject {
    static let shared = OnDeviceModelStore()
    static let defaultModelID = OnDeviceModelDescriptor.qwen35Q4KS.id

    @Published private(set) var customModels: [OnDeviceModelDescriptor] = []
    @Published private(set) var transferState: ModelTransferState = .idle
    @Published private(set) var transferProgress: Double = 0

    var models: [OnDeviceModelDescriptor] {
        [OnDeviceModelDescriptor.qwen35Q4KS, .qwen3VL4B] + customModels
    }

    private struct DownloadPlan {
        let model: OnDeviceModelDescriptor
        var remainingFiles: [OnDeviceModelFile]
        var completedBytes: Int64
        let generation: UUID
    }

    private let fileManager = FileManager.default
    private let customModelsDefaultsKey = "woundCustomOnDeviceModels"
    private var plan: DownloadPlan?
    private var activeTask: URLSessionDownloadTask?

    private lazy var downloadSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 60 * 60 * 24
        configuration.allowsCellularAccess = false
        return URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }()

    override private init() {
        super.init()
        customModels = Self.loadCustomModels(defaultsKey: customModelsDefaultsKey)
        try? prepareModelsDirectory()
    }

    func model(withID id: String) -> OnDeviceModelDescriptor? {
        models.first { $0.id == id }
    }

    func modelDirectory(for model: OnDeviceModelDescriptor) -> URL {
        modelsRoot.appendingPathComponent(model.localFolderName, isDirectory: true)
    }

    func isInstalled(_ model: OnDeviceModelDescriptor) -> Bool {
        guard model.isRuntimeSupported else { return false }
        let directory = modelDirectory(for: model)
        guard model.runtime == .gguf || fileManager.fileExists(atPath: directory.appendingPathComponent("config.json").path) else {
            return false
        }
        if model.files.isEmpty {
            return true
        }
        return model.files.allSatisfy { fileMatchesSize($0, model: model) }
    }

    func download(_ model: OnDeviceModelDescriptor) {
        guard WoundDeviceCapacity.canRunContext, model.isRuntimeSupported else {
            transferState = .failed(modelID: model.id, message: "This model cannot run on this device or in this app build.")
            return
        }
        let available = (try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        guard available > model.totalByteCount + 1_000_000_000 else {
            transferState = .failed(modelID: model.id, message: "There is not enough free storage. Free space and try again, or use Photo Check.")
            return
        }
        guard model.isBuiltIn,
              let sourceBaseURL = model.sourceBaseURL,
              let revision = model.revision else {
            transferState = .failed(modelID: model.id, message: "This model can only be installed by importing its folder.")
            return
        }

        cancelDownload(resetState: false)
        do {
            try prepareModelsDirectory()
            try fileManager.createDirectory(
                at: modelDirectory(for: model),
                withIntermediateDirectories: true
            )
        } catch {
            transferState = .failed(modelID: model.id, message: error.localizedDescription)
            return
        }

        let missingFiles = model.files.filter { !fileMatchesSize($0, model: model) }
        guard !missingFiles.isEmpty else {
            transferProgress = 1
            transferState = .installed(modelID: model.id)
            return
        }

        let completedBytes = model.files
            .filter { fileMatchesSize($0, model: model) }
            .reduce(0) { $0 + $1.byteCount }
        plan = DownloadPlan(
            model: model,
            remainingFiles: missingFiles,
            completedBytes: completedBytes,
            generation: UUID()
        )
        transferProgress = Double(completedBytes) / Double(max(model.totalByteCount, 1))
        startNextDownload(sourceBaseURL: sourceBaseURL, revision: revision)
    }

    func cancelDownload() {
        cancelDownload(resetState: true)
    }

    @MainActor
    func importModel(from sourceURL: URL) async throws -> OnDeviceModelDescriptor {
        guard WoundDeviceCapacity.canRunContext else { throw ModelStoreError.invalidImportedModel }
        switch transferState {
        case .downloading, .verifying, .importing:
            throw WoundModelImportValidation.Failure.invalid("Wait for the current transfer to finish.")
        default: break
        }
        transferState = .importing
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let result = try await Task.detached(priority: .userInitiated) { () -> OnDeviceModelDescriptor in
                let manager = FileManager.default
                let plan = try WoundModelImportValidation.inspect(sourceURL)
                let available = (try manager.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
                guard available > plan.bytes + 1_000_000_000 else {
                    throw WoundModelImportValidation.Failure.invalid("Free more storage before importing this model.")
                }
                let id = "imported-\(UUID().uuidString.lowercased())"
                let destination = Self.modelsRootURL.appendingPathComponent(id, isDirectory: true)
                try manager.createDirectory(at: destination, withIntermediateDirectories: true)
                do {
                    var root = Self.modelsRootURL
                    var attributes = URLResourceValues()
                    attributes.isExcludedFromBackup = true
                    try root.setResourceValues(attributes)
                    var files: [OnDeviceModelFile] = []
                    for source in plan.files {
                        let target = destination.appendingPathComponent(source.lastPathComponent)
                        try manager.copyItem(at: source, to: target)
                        let digest = try Self.sha256(for: target)
                        let size = Int64(try target.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
                        files.append(OnDeviceModelFile(name: source.lastPathComponent, byteCount: size, sha256: digest))
                        try digest.write(to: destination.appendingPathComponent(".\(source.lastPathComponent).sha256"), atomically: true, encoding: .utf8)
                    }
                    return OnDeviceModelDescriptor(
                        id: id, displayName: sourceURL.lastPathComponent,
                        detail: "Imported vision model. Runtime compatibility and output quality depend on the supplied model.",
                        runtime: plan.gguf ? .gguf : .mnn,
                        runtimeVersion: plan.gguf ? "llama.cpp b11577 compatible" : "MNN 3.5 compatible",
                        sourceBaseURL: nil, revision: nil, localFolderName: id,
                        files: files, isBuiltIn: false,
                        modelFileName: plan.modelFile, visionFileName: plan.visionFile)
                } catch {
                    try? manager.removeItem(at: destination)
                    throw error
                }
            }.value

            customModels.append(result)
            saveCustomModels()
            transferProgress = 1
            transferState = .installed(modelID: result.id)
            return result
        } catch {
            transferState = .failed(modelID: nil, message: error.localizedDescription)
            throw error
        }
    }

    func delete(_ model: OnDeviceModelDescriptor) throws {
        if case .downloading(let modelID, _) = transferState, modelID == model.id {
            cancelDownload()
        }
        let directory = modelDirectory(for: model)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        if !model.isBuiltIn {
            customModels.removeAll { $0.id == model.id }
            saveCustomModels()
        }
        transferProgress = 0
        transferState = .idle
    }

    private var modelsRoot: URL { Self.modelsRootURL }

    private static var modelsRootURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return applicationSupport
            .appendingPathComponent("WoundCorder", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    private func prepareModelsDirectory() throws {
        try fileManager.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var root = modelsRoot
        try root.setResourceValues(values)
    }

    private func startNextDownload(sourceBaseURL: String, revision: String) {
        guard let plan else { return }
        guard let file = plan.remainingFiles.first else {
            transferProgress = 1
            transferState = .installed(modelID: plan.model.id)
            self.plan = nil
            return
        }

        let encodedName = file.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.name
        guard let url = URL(string: "\(sourceBaseURL)/\(revision)/\(encodedName)?download=true") else {
            failCurrentDownload("The model download address is invalid.")
            return
        }

        self.plan = plan
        transferState = .downloading(modelID: plan.model.id, fileName: file.name)
        let task = downloadSession.downloadTask(with: url)
        task.taskDescription = file.name
        activeTask = task
        task.resume()
    }

    private func fileMatchesSize(_ file: OnDeviceModelFile, model: OnDeviceModelDescriptor) -> Bool {
        let url = modelDirectory(for: model).appendingPathComponent(file.name)
        let marker = modelDirectory(for: model).appendingPathComponent(".\(file.name).sha256")
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              Int64(values.fileSize ?? -1) == file.byteCount,
              let verifiedDigest = try? String(contentsOf: marker, encoding: .utf8) else {
            return false
        }
        return verifiedDigest == file.sha256
    }

    private func verifyDownloadedFile(_ file: OnDeviceModelFile, at url: URL, generation: UUID) {
        guard let plan, plan.generation == generation else { return }
        transferState = .verifying(modelID: plan.model.id, fileName: file.name)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                guard Int64(values.fileSize ?? -1) == file.byteCount else {
                    throw ModelStoreError.invalidFileSize(file.name)
                }
                let digest = try Self.sha256(for: url)
                guard digest == file.sha256 else {
                    throw ModelStoreError.invalidChecksum(file.name)
                }
                DispatchQueue.main.async {
                    self?.finishFile(file, generation: generation)
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.plan?.generation == generation else { return }
                    try? self.fileManager.removeItem(at: url)
                    self.failCurrentDownload(error.localizedDescription)
                }
            }
        }
    }

    private func finishFile(_ file: OnDeviceModelFile, generation: UUID) {
        guard var plan, plan.generation == generation else { return }
        let marker = modelDirectory(for: plan.model).appendingPathComponent(".\(file.name).sha256")
        do {
            try file.sha256.write(to: marker, atomically: true, encoding: .utf8)
        } catch {
            failCurrentDownload(error.localizedDescription)
            return
        }
        plan.completedBytes += file.byteCount
        plan.remainingFiles.removeFirst()
        self.plan = plan
        transferProgress = Double(plan.completedBytes) / Double(max(plan.model.totalByteCount, 1))

        guard let baseURL = plan.model.sourceBaseURL, let revision = plan.model.revision else {
            failCurrentDownload("The model source is unavailable.")
            return
        }
        startNextDownload(sourceBaseURL: baseURL, revision: revision)
    }

    private func cancelDownload(resetState: Bool) {
        activeTask?.cancel()
        activeTask = nil
        plan = nil
        if resetState {
            transferState = .idle
            transferProgress = 0
        }
    }

    private func failCurrentDownload(_ message: String) {
        let modelID = plan?.model.id
        activeTask = nil
        plan = nil
        transferState = .failed(modelID: modelID, message: message)
    }

    private static func sha256(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 4 * 1_024 * 1_024) ?? Data()
            guard !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func loadCustomModels(defaultsKey: String) -> [OnDeviceModelDescriptor] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([OnDeviceModelDescriptor].self, from: data)) ?? []
    }

    private func saveCustomModels() {
        guard let data = try? JSONEncoder().encode(customModels) else { return }
        UserDefaults.standard.set(data, forKey: customModelsDefaultsKey)
    }
}

extension OnDeviceModelStore: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard downloadTask === activeTask,
              let plan,
              let currentFile = plan.remainingFiles.first,
              downloadTask.taskDescription == currentFile.name else { return }
        let currentBytes = min(totalBytesWritten, currentFile.byteCount)
        transferProgress = Double(plan.completedBytes + currentBytes) /
            Double(max(plan.model.totalByteCount, 1))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard downloadTask === activeTask,
              let plan,
              let currentFile = plan.remainingFiles.first,
              downloadTask.taskDescription == currentFile.name else { return }
        let destination = modelDirectory(for: plan.model).appendingPathComponent(currentFile.name)
        let marker = modelDirectory(for: plan.model).appendingPathComponent(".\(currentFile.name).sha256")

        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            if fileManager.fileExists(atPath: marker.path) {
                try fileManager.removeItem(at: marker)
            }
            try fileManager.moveItem(at: location, to: destination)
            activeTask = nil
            verifyDownloadedFile(currentFile, at: destination, generation: plan.generation)
        } catch {
            failCurrentDownload(error.localizedDescription)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard task === activeTask, let error else { return }
        failCurrentDownload(error.localizedDescription)
    }
}

private enum ModelStoreError: LocalizedError {
    case invalidImportedModel
    case invalidFileSize(String)
    case invalidChecksum(String)

    var errorDescription: String? {
        switch self {
        case .invalidImportedModel:
            return "Choose an MNN model folder containing config.json."
        case .invalidFileSize(let name):
            return "\(name) did not download completely."
        case .invalidChecksum(let name):
            return "\(name) failed its integrity check and was removed."
        }
    }
}
