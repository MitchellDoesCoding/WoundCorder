import SwiftUI

struct ComorbidityChecklistFields: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    @Binding var checklist: ComorbidityChecklist
    @AppStorage("woundAppMode") private var modeRaw = WoundAppMode.publicPatient.rawValue
    private var isProfessional: Bool { modeRaw == WoundAppMode.professional.rawValue }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(WoundL10n.text(isProfessional ? "Comorbidities (optional)" : "Your health (optional)")).font(.headline)
            Text(WoundL10n.text("Choose Yes or No for each item you know. Leave the rest as Unknown.")).foregroundStyle(.secondary)
            row(isProfessional ? "Diabetes mellitus" : "Diabetes (high blood sugar)", selection: $checklist.diabetes_mellitus)
            row(isProfessional ? "Tobacco use, current or former" : "Tobacco use (smoking now or in the past)", selection: $checklist.tobacco_use_current_or_former)
            row(isProfessional ? "Congestive heart failure (CHF)" : "Heart failure (weak or failing heart)", selection: $checklist.congestive_heart_failure)
            row(isProfessional ? "Peripheral vascular / arterial disease (PVD/PAD)" : "Poor blood flow or narrow arteries in the legs", selection: $checklist.peripheral_vascular_or_arterial_disease)
            row(isProfessional ? "Stroke / paralysis" : "Stroke or trouble moving part of your body", selection: $checklist.stroke_or_paralysis)
            row(isProfessional ? "Surgery at the wound site" : "Surgery where the wound is", selection: $checklist.surgery_at_wound_site)
            row(isProfessional ? "Immunosuppression / chronic steroids" : "Weak immune system or long-term steroid use", selection: $checklist.weak_immune_system_or_chronic_steroids)
            row(isProfessional ? "Chemotherapy / biologics / other immunosuppression" : "Cancer treatment or other immune-weakening medicines", selection: $checklist.other_immune_weakening_medicines)
            row(isProfessional ? "DVT / VTE" : "Blood clot in the leg or lungs", selection: $checklist.DVT_or_VTE)
            row(isProfessional ? "History of similar ulcers" : "Similar sores or wounds in the past", selection: $checklist.history_of_similar_ulcers)
            row(isProfessional ? "Obesity" : "Overweight", selection: $checklist.obesity)
            row(isProfessional ? "Incontinence" : "Trouble holding urine or stool", selection: $checklist.incontinence)
            row(isProfessional ? "Peripheral neuropathy" : "Numbness or loss of feeling in the feet", selection: $checklist.peripheral_neuropathy)
        }
    }
    private func row(_ title: String, selection: Binding<Ternary>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(WoundL10n.text(title)).fixedSize(horizontal: false, vertical: true)
            Picker(WoundL10n.text(title), selection: selection) {
                Text(WoundL10n.text("Unknown")).tag(Ternary.unknown)
                Text(WoundL10n.text("Yes")).tag(Ternary.yes)
                Text(WoundL10n.text("No")).tag(Ternary.no)
            }.pickerStyle(.segmented).frame(minHeight: 44)
        }
    }
}
struct ComorbidityChecklistSheet: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    @Environment(\.dismiss) private var dismiss
    @State private var checklist = ComorbidityChecklist()
    var onUse: (ComorbidityChecklist) -> Void
    var onSkip: (() -> Void)?
    var body: some View {
        NavigationStack {
            ScrollView { ComorbidityChecklistFields(checklist: $checklist).padding() }
                .navigationTitle(WoundL10n.text("Your health"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(WoundL10n.text("Skip")) { onSkip?(); dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(WoundL10n.text("Done")) { onUse(checklist); dismiss() } }
                }
        }
    }
}
