import SwiftUI
import UniformTypeIdentifiers

struct WoundAIModelSheet: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            WoundAIModelView().toolbar { ToolbarItem(placement: .confirmationAction) { Button(WoundL10n.text("Done")) { dismiss() } } }
        }
    }
}

struct WoundAIModelView: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    @AppStorage("woundAnalysisProvider") private var providerRaw = WoundAnalysisProvider.onDevice.rawValue
    @AppStorage("woundOnDeviceModelID") private var modelID = OnDeviceModelStore.defaultModelID
    @AppStorage("woundModelDownloadConsent") private var downloadConsent = false
    @State private var showImporter = false
    @State private var importError: String?
    @StateObject private var store = OnDeviceModelStore.shared
    var body: some View {
        Form {
            Section(WoundL10n.text("Choose how to check a wound")) {
                Text(WoundL10n.text(WoundDeviceCapacity.explanation))
                ForEach(WoundAnalysisProvider.allCases) { provider in
                    Button {
                        providerRaw = provider.rawValue
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(WoundL10n.text(provider.title), systemImage: providerRaw == provider.rawValue ? "checkmark.circle.fill" : "circle").font(.headline)
                            Text(WoundL10n.text(provider.explanation)).font(.body).foregroundStyle(.secondary)
                            Text(WoundL10n.text(provider == .semanticCNN ? "CNN only" : "CNN + VLM")).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).padding(.vertical, 8)
                    }.disabled(provider == .onDevice && !WoundDeviceCapacity.canRunContext)
                }
            }
            Section(WoundL10n.text("Photo + Health Context model")) {
                Text(WoundL10n.text("Qwen3.5-4B (Q4_K_S) is selected by default. Its download is about 3.5 GB. Use Wi-Fi, keep this screen open, and allow extra free space. Qwen3-VL-4B is also available."))
                Toggle(WoundL10n.text("I agree to download model files over Wi-Fi and use device storage."), isOn: $downloadConsent)
                ForEach(store.models) { model in
                    VStack(alignment: .leading, spacing: 10) {
                        Button { modelID = model.id } label: {
                            Label(WoundL10n.text(model.displayName), systemImage: modelID == model.id ? "checkmark.circle.fill" : "circle").font(.headline).frame(minHeight: 44)
                        }.disabled(!model.isRuntimeSupported || !WoundDeviceCapacity.canRunContext)
                        Text(WoundL10n.text(model.detail)).foregroundStyle(.secondary)
                        if model.isRuntimeSupported {
                            Text(WoundL10n.text(ByteCountFormatter.string(fromByteCount: model.totalByteCount, countStyle: .file)))
                            if store.isInstalled(model) {
                                Label(WoundL10n.text(model.isBuiltIn ? "Ready on this device" : "Imported · compatibility checked when used"), systemImage: "checkmark.shield")
                                Button(WoundL10n.text("Remove download"), role: .destructive) {
                                    do {
                                        try store.delete(model)
                                        if modelID == model.id { modelID = OnDeviceModelStore.defaultModelID; providerRaw = WoundAnalysisProvider.semanticCNN.rawValue }
                                    } catch { importError = error.localizedDescription }
                                }.disabled(transferring)
                            } else {
                                Button(WoundL10n.text("Download over Wi-Fi")) { modelID = model.id; store.download(model) }
                                    .buttonStyle(.bordered).frame(minHeight: 44)
                                    .disabled(!downloadConsent || !WoundDeviceCapacity.canRunContext || transferring)
                            }
                        }
                    }.padding(.vertical, 8)
                }
                if transferring {
                    if case .importing = store.transferState {
                        Text(WoundL10n.text("Keep the app open while the model is imported.")).font(.footnote)
                    } else {
                        ProgressView(value: store.transferProgress)
                        Button(WoundL10n.text("Cancel download")) { store.cancelDownload() }
                    }
                }
                if case .failed(_, let message) = store.transferState { Text(WoundL10n.text(message)).foregroundStyle(.red) }
            }
            Section(WoundL10n.text("Add your own model")) {
                Text(WoundL10n.text("Choose a folder in Files containing a GGUF vision-language model and its matching mmproj GGUF file, or a complete MNN vision model."))
                Text(WoundL10n.text("Imported models must work with the bundled runtime and return WoundCorder’s structured response. The built-in wound CNN remains unchanged."))
                    .font(.footnote).foregroundStyle(.secondary)
                Button(WoundL10n.text("Add model from Files"), systemImage: "folder.badge.plus") { showImporter = true }
                    .disabled(transferring || !WoundDeviceCapacity.canRunContext)
                if case .importing = store.transferState { ProgressView(WoundL10n.text("Copying and checking model files…")) }
            }
            Section(WoundL10n.text("Your privacy")) {
                Text(WoundL10n.text("Photo checks run on this device. Downloading a model does not send your wound photos. Sharing by email is always a separate choice."))
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                Task {
                    do {
                        let model = try await store.importModel(from: url)
                        modelID = model.id
                        providerRaw = WoundAnalysisProvider.onDevice.rawValue
                    } catch { importError = error.localizedDescription }
                }
            case .failure(let error): importError = error.localizedDescription
            }
        }
        .alert(WoundL10n.text("Model could not be added"), isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button(WoundL10n.text("OK")) { importError = nil }
        } message: { Text(WoundL10n.text(importError ?? "Please try again.")) }
        .navigationTitle(WoundL10n.text("Photo check settings"))
        .onAppear {
            if !WoundDeviceCapacity.canRunContext || WoundAnalysisProvider(rawValue: providerRaw) == nil { providerRaw = WoundAnalysisProvider.semanticCNN.rawValue }
        }
    }
    private var transferring: Bool {
        switch store.transferState { case .downloading, .verifying, .importing: return true; default: return false }
    }
}
