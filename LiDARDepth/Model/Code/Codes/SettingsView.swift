import SwiftUI

private enum Audience: String, CaseIterable, Identifiable {
    case patient
    case doctor
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .patient: return "Patient"
        case .doctor: return "Doctor"
        }
    }
}

struct SettingsView: View {
    @AppStorage("woundServerBaseURL") private var baseURL: String = ""
    @AppStorage("woundSummaryAudience") private var audienceRaw: String = Audience.patient.rawValue
    @AppStorage("offlineFriendlyMode") private var offlineFriendlyMode: Bool = true
    @AppStorage("researchUsageConsent") private var researchUsageConsent: Bool = false

    var body: some View {
        NavigationStack {
            Form {
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
                    footer: Text("Audience controls how AI summaries are written: Patient uses simpler language, Doctor uses technical terms.")
                ) {
                    TextField("https://6727e030ebe5.ngrok-free.app", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.URL)

                    Picker("Summary Audience", selection: $audienceRaw) {
                        ForEach(Audience.allCases) { a in
                            Text(a.displayName).tag(a.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)
                }

                Section(
                    header: Text("Consent"),
                    footer: Text("Research consent is optional and can be changed here at any time.")
                ) {
                    Toggle("Allow de-identified usage data for research", isOn: $researchUsageConsent)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
