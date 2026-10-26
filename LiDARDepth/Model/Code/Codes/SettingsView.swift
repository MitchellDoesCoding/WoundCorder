import SwiftUI

struct SettingsView: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    @Environment(\.dismiss) private var dismiss

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
                    header: Text(WoundL10n.text("Care Mode")),
                    footer: Text(WoundL10n.text("This changes the home workspace and the tone/detail level used by Wound AI."))
                ) {
                    Picker(WoundL10n.text("Care Mode"), selection: $modeRaw) {
                        ForEach(WoundAppMode.allCases) { mode in
                            Label(WoundL10n.text(mode.displayName), systemImage: mode.systemImage)
                                .tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.inline)

                    ModeSettingsSummary(mode: selectedMode)
                }

                Section(header: Text(WoundL10n.text("Appearance"))) {
                    Picker(WoundL10n.text("Home Appearance"), selection: $appearanceRaw) {
                        ForEach(HomeAppearanceMode.allCases) { option in
                            Label(WoundL10n.text(option.rawValue), systemImage: option.systemImage)
                                .tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(
                    header: Text(WoundL10n.text("Measurement")),
                    footer: Text(WoundL10n.text("Area, depth, volume, and mesh export are available without a network request when device depth data is available."))
                ) {
                    Toggle(WoundL10n.text("Offline-friendly LiDAR measurement"), isOn: $offlineFriendlyMode)
                    LabeledContent(WoundL10n.text("Method"), value: "ARKit LiDAR mesh + scene depth")
                    LabeledContent(WoundL10n.text("Wound edge"), value: "On-device segmentation with guided refine")
                    LabeledContent(WoundL10n.text("Calibration"), value: "No card required")
                }

                Section(WoundL10n.text("Photo checks")) {
                    NavigationLink(WoundL10n.text("Models, modes & privacy")) { WoundAIModelView() }
                }

                Section(
                    header: Text(WoundL10n.text("Consent")),
                    footer: Text(WoundL10n.text("Research consent is optional and can be changed here at any time."))
                ) {
                    Toggle(WoundL10n.text("Allow de-identified usage data for research"), isOn: $researchUsageConsent)
                }
            }
            .navigationTitle(WoundL10n.text("Settings"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(WoundL10n.text("Done")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ModeSettingsSummary: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let mode: WoundAppMode

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: mode.systemImage)
                .font(.headline)
                .foregroundStyle(mode == .professional ? .indigo : .teal)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(WoundL10n.text(mode == .professional ? "Professional AI output" : "Patient photo results"))
                    .font(.subheadline.weight(.semibold))
                Text(WoundL10n.text(mode.shortDetail))
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
