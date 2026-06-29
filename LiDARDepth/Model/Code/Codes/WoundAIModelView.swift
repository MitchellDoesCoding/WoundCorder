import SwiftUI
import UniformTypeIdentifiers

struct WoundAIModelSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WoundAIModelView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

struct WoundAIModelView: View {
    @AppStorage("woundAnalysisProvider") private var analysisProviderRaw = WoundAnalysisProvider.onDevice.rawValue
    @AppStorage("woundOnDeviceModelID") private var selectedModelID = OnDeviceModelStore.defaultModelID
    @AppStorage("woundServerBaseURL") private var baseURL = ""

    @StateObject private var modelStore = OnDeviceModelStore.shared
    @State private var showModelImporter = false
    @State private var importError: String?
    @State private var modelPendingDeletion: OnDeviceModelDescriptor?

    private var selectedProvider: Binding<WoundAnalysisProvider> {
        Binding(
            get: { WoundAnalysisProvider(rawValue: analysisProviderRaw) ?? .onDevice },
            set: { analysisProviderRaw = $0.rawValue }
        )
    }

    private var activeModel: OnDeviceModelDescriptor {
        modelStore.model(withID: selectedModelID) ?? .qwen3VL4B
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                statusHeader

                VStack(alignment: .leading, spacing: 24) {
                    providerSection
                    modelSection

                    if selectedProvider.wrappedValue == .legacyRemote {
                        legacyServerSection
                    }

                    privacySection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 22)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Wound AI")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showModelImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: handleModelImport
        )
        .alert("Model Import Failed", isPresented: importErrorPresented) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "The selected model could not be imported.")
        }
        .confirmationDialog(
            "Remove \(modelPendingDeletion?.displayName ?? "model")?",
            isPresented: deletionPresented,
            titleVisibility: .visible
        ) {
            Button("Remove Model", role: .destructive, action: removePendingModel)
            Button("Cancel", role: .cancel) { modelPendingDeletion = nil }
        } message: {
            Text("The local model files will be deleted from this device.")
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 15) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(headerColor)
                .frame(width: 52, height: 52)
                .background(headerColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Wound AI")
                    .font(.title2.weight(.bold))
                Text(headerStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: headerStatusIcon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(headerColor)
                .accessibilityLabel(headerStatus)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Processing")
                .font(.headline)

            Picker("Processing", selection: selectedProvider) {
                ForEach(WoundAnalysisProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Models")
                    .font(.headline)
                Spacer()
                Button {
                    showModelImporter = true
                } label: {
                    Label("Import", systemImage: "folder.badge.plus")
                }
                .disabled(!OnDeviceMNNBridge.isRuntimeAvailable())
            }

            VStack(spacing: 12) {
                ForEach(modelStore.models) { model in
                    modelRow(model)
                }
            }

            if modelStore.transferState == .importing {
                ProgressView("Importing model")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .opacity(selectedProvider.wrappedValue == .onDevice ? 1 : 0.55)
        .disabled(selectedProvider.wrappedValue != .onDevice)
    }

    private func modelRow(_ model: OnDeviceModelDescriptor) -> some View {
        let isSelected = selectedModelID == model.id
        let isInstalled = modelStore.isInstalled(model)

        return VStack(spacing: 0) {
            Button {
                selectedModelID = model.id
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(model.displayName)
                                .font(.headline)
                            if model.id == OnDeviceModelStore.defaultModelID {
                                Text("Default")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(model.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("\(model.runtimeVersion) • \(formattedSize(model.totalByteCount))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
                .padding(14)
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.leading, 50)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Label(
                        modelStatusText(model, installed: isInstalled),
                        systemImage: modelStatusIcon(model, installed: isInstalled)
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(modelStatusColor(model, installed: isInstalled))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                    Spacer()

                    modelAction(model, installed: isInstalled)
                }

                if isTransferring(model) {
                    ProgressView(value: modelStore.transferProgress) {
                        Text(transferLabel)
                            .font(.caption)
                    }
                    .tint(.blue)
                }

                if case .failed(let modelID, let message) = modelStore.transferState,
                   modelID == model.id {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        }
    }

    @ViewBuilder
    private func modelAction(_ model: OnDeviceModelDescriptor, installed: Bool) -> some View {
        if isTransferring(model) {
            Button {
                modelStore.cancelDownload()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Cancel model download")
        } else if installed {
            Button(role: .destructive) {
                modelPendingDeletion = model
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        } else if model.isBuiltIn {
            Button {
                selectedModelID = model.id
                modelStore.download(model)
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!OnDeviceMNNBridge.isRuntimeAvailable())
        }
    }

    private var legacyServerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Legacy Server")
                .font(.headline)

            TextField("Server URL", text: $baseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textFieldStyle(.roundedBorder)

            Label("Wound images leave this device in Legacy Server mode.", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    private var privacySection: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: selectedProvider.wrappedValue == .onDevice ? "lock.shield.fill" : "network")
                .font(.title3)
                .foregroundStyle(selectedProvider.wrappedValue == .onDevice ? Color.green : Color.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(selectedProvider.wrappedValue == .onDevice ? "Private by default" : "External processing")
                    .font(.subheadline.weight(.semibold))
                Text(privacyStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerStatus: String {
        if selectedProvider.wrappedValue == .legacyRemote {
            return "Legacy server selected"
        }
        if !OnDeviceMNNBridge.isRuntimeAvailable() {
            return "Physical device required for local inference"
        }
        return modelStore.isInstalled(activeModel)
            ? "\(activeModel.displayName) is ready offline"
            : "Download \(activeModel.displayName) to begin"
    }

    private var headerStatusIcon: String {
        if selectedProvider.wrappedValue == .legacyRemote { return "network" }
        if modelStore.isInstalled(activeModel) { return "checkmark.circle.fill" }
        return OnDeviceMNNBridge.isRuntimeAvailable() ? "arrow.down.circle" : "iphone.slash"
    }

    private var headerColor: Color {
        if selectedProvider.wrappedValue == .legacyRemote { return .orange }
        return modelStore.isInstalled(activeModel) ? .green : .blue
    }

    private var privacyStatus: String {
        if selectedProvider.wrappedValue == .legacyRemote {
            return "The configured server receives images submitted for AI analysis."
        }
        return "Wound images and notes remain on this device. Internet access is used only for model downloads."
    }

    private func modelStatusText(_ model: OnDeviceModelDescriptor, installed: Bool) -> String {
        if isTransferring(model) { return transferLabel }
        if installed { return "Ready offline" }
        if !OnDeviceMNNBridge.isRuntimeAvailable() { return "Device only" }
        return "Not installed"
    }

    private func modelStatusIcon(_ model: OnDeviceModelDescriptor, installed: Bool) -> String {
        if isTransferring(model) { return "arrow.down.circle" }
        if installed { return "checkmark.circle.fill" }
        if !OnDeviceMNNBridge.isRuntimeAvailable() { return "iphone.slash" }
        return "circle.dashed"
    }

    private func modelStatusColor(_ model: OnDeviceModelDescriptor, installed: Bool) -> Color {
        if installed { return .green }
        if case .failed(let modelID, _) = modelStore.transferState, modelID == model.id { return .red }
        return .secondary
    }

    private func isTransferring(_ model: OnDeviceModelDescriptor) -> Bool {
        switch modelStore.transferState {
        case .downloading(let modelID, _), .verifying(let modelID, _):
            return modelID == model.id
        default:
            return false
        }
    }

    private var transferLabel: String {
        switch modelStore.transferState {
        case .downloading(_, let fileName): return "Downloading \(fileName)"
        case .verifying(_, let fileName): return "Verifying \(fileName)"
        default: return "Preparing model"
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "Imported bundle" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var importErrorPresented: Binding<Bool> {
        Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )
    }

    private var deletionPresented: Binding<Bool> {
        Binding(
            get: { modelPendingDeletion != nil },
            set: { if !$0 { modelPendingDeletion = nil } }
        )
    }

    private func handleModelImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                do {
                    let model = try await modelStore.importModel(from: url)
                    selectedModelID = model.id
                } catch {
                    importError = error.localizedDescription
                }
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func removePendingModel() {
        guard let model = modelPendingDeletion else { return }
        do {
            try modelStore.delete(model)
            if selectedModelID == model.id {
                selectedModelID = OnDeviceModelStore.defaultModelID
            }
        } catch {
            importError = error.localizedDescription
        }
        modelPendingDeletion = nil
    }
}

#Preview {
    NavigationStack {
        WoundAIModelView()
    }
}
