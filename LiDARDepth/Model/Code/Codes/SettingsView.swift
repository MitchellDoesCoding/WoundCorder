import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("woundServerBaseURL") private var baseURL: String = ""
    @AppStorage("offlineFriendlyMode") private var offlineFriendlyMode: Bool = true
    @AppStorage("researchUsageConsent") private var researchUsageConsent: Bool = false
    @AppStorage("woundAppMode") private var modeRaw: String = WoundAppMode.publicPatient.rawValue
    @AppStorage("homeAppearanceMode") private var appearanceRaw: String = HomeAppearanceMode.light.rawValue
    @AppStorage("woundAnalysisProvider") private var analysisProviderRaw = WoundAnalysisProvider.onDevice.rawValue

    private var selectedMode: WoundAppMode {
        WoundAppMode(rawValue: modeRaw) ?? .publicPatient
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(
                    header: Text("Care Mode"),
                    footer: Text("This changes the home workspace and the tone/detail level used by Wound AI.")
                ) {
                    Picker("Care Mode", selection: $modeRaw) {
                        ForEach(WoundAppMode.allCases) { mode in
                            Label(mode.displayName, systemImage: mode.systemImage)
                                .tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.inline)

                    ModeSettingsSummary(mode: selectedMode)
                }

                Section(header: Text("Appearance")) {
                    Picker("Home Appearance", selection: $appearanceRaw) {
                        ForEach(HomeAppearanceMode.allCases) { option in
                            Label(option.rawValue, systemImage: option.systemImage)
                                .tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(
                    header: Text("Measurement"),
                    footer: Text("Area, depth, volume, mesh export, and severity scoring are available without a network request when device depth data is available.")
                ) {
                    Toggle("Offline-friendly LiDAR measurement", isOn: $offlineFriendlyMode)
                    LabeledContent("Method", value: "ARKit LiDAR mesh + scene depth")
                    LabeledContent("Wound edge", value: "On-device segmentation with guided refine")
                    LabeledContent("Calibration", value: "No card required")
                }

                Section(
                    header: Text("Wound AI"),
                    footer: Text("On-device keeps wound images local when the model is installed. Legacy Server sends images to the configured endpoint.")
                ) {
                    Picker("Processing", selection: $analysisProviderRaw) {
                        ForEach(WoundAnalysisProvider.allCases) { provider in
                            Text(provider.title).tag(provider.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    NavigationLink {
                        WoundAIModelView()
                    } label: {
                        Label("Models & Privacy", systemImage: "brain.head.profile")
                    }

                    if analysisProviderRaw == WoundAnalysisProvider.legacyRemote.rawValue {
                        TextField("Legacy Server URL", text: $baseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .keyboardType(.URL)
                    }
                }

                Section(
                    header: Text("Consent"),
                    footer: Text("Research consent is optional and can be changed here at any time.")
                ) {
                    Toggle("Allow de-identified usage data for research", isOn: $researchUsageConsent)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ModeSettingsSummary: View {
    let mode: WoundAppMode

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: mode.systemImage)
                .font(.headline)
                .foregroundStyle(mode == .professional ? .indigo : .teal)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(mode == .professional ? "Professional AI output" : "Consumer AI output")
                    .font(.subheadline.weight(.semibold))
                Text(mode.shortDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SettingsView()
}
