import SwiftUI
import MessageUI

extension PatientProfile {
    var validationMessage: String? {
        if !age.isEmpty && (Int(age).map { (0...120).contains($0) } != true) { return "Enter age in years, from 0 to 120, or leave it blank." }
        if !height.isEmpty && (WoundWorkflowPolicy.decimalInput(height).map { $0.isFinite && (30...250).contains($0) } != true) { return "Enter height in centimeters, from 30 to 250, or leave it blank." }
        if !weight.isEmpty && (WoundWorkflowPolicy.decimalInput(weight).map { $0.isFinite && (0.5...500).contains($0) } != true) { return "Enter weight in kilograms, from 0.5 to 500, or leave it blank." }
        return nil
    }

    var inferenceMetadata: [String: String] {
        var values: [String: String] = [:]
        if let years = Int(age.trimmingCharacters(in: .whitespacesAndNewlines)), (0...120).contains(years) { values["age_years"] = String(years) }
        if let bmi = WoundWorkflowPolicy.bmi(heightCM: height, weightKG: weight) {
            values["bmi_kg_m2"] = String(format: "%.1f", bmi)
        }
        if gender != .unknown { values["gender"] = gender.displayName }
        return values
    }
    var shareDemographics: String {
        var lines: [String] = []
        if !age.isEmpty { lines.append("Age: \(age)") }
        if gender != .unknown { lines.append("Gender: \(gender.displayName)") }
        if !height.isEmpty { lines.append("Height: \(height) cm") }
        if !weight.isEmpty { lines.append("Weight: \(weight) kg") }
        if let bmi = inferenceMetadata["bmi_kg_m2"] { lines.append("BMI: \(bmi) kg/m²") }
        return lines.joined(separator: "\n")
    }
}

enum WoundShareLevel: Int, CaseIterable, Identifiable {
    case photo, demographics, health, analysis
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .photo: return "Photo only"
        case .demographics: return "Photo + basic details"
        case .health: return "Photo + basic details + health checklist"
        case .analysis: return "Photo + basic details + health checklist + results"
        }
    }
    func body(profile: PatientProfile, intake: WoundIntakeData, analysis: String) -> String {
        var parts = ["Shared from WoundCorder by the sender."]
        if rawValue >= Self.demographics.rawValue { parts.append(profile.shareDemographics) }
        if rawValue >= Self.health.rawValue {
            parts.append("Health checklist:\n" + intake.comorbidities.asDictionary().sorted { $0.key < $1.key }.map { "\($0.key.replacingOccurrences(of: "_", with: " ")): \($0.value)" }.joined(separator: "\n"))
        }
        if self == .analysis { parts.append("Wound location: \(intake.laterality.rawValue) \(intake.bodyArea.rawValue)\nDuration: \(intake.dateWounded.rawValue)\n\nResults:\n" + analysis) }
        return parts.joined(separator: "\n\n")
    }
}
struct WoundEmailShareView: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let photo: UIImage?
    let profile: PatientProfile
    let intake: WoundIntakeData
    let analysis: String
    @Environment(\.dismiss) private var dismiss
    @State private var level: WoundShareLevel = .photo
    @State private var agreed = false
    @State private var showMail = false
    @State private var mailError: String?
    private var bodyText: String { WoundL10n.text(level.body(profile: profile, intake: intake, analysis: analysis)) }
    var body: some View {
        NavigationStack {
            Form {
                Section(WoundL10n.text("Send to info@woundcorder.ai")) {
                    Text(WoundL10n.text("This shares private health information by email. This address is not an emergency care service."))
                    Picker(WoundL10n.text("Include"), selection: $level) {
                        ForEach(WoundShareLevel.allCases) { Text(WoundL10n.text($0.title)).tag($0) }
                    }.pickerStyle(.inline)
                }
                Section(WoundL10n.text("Review what you will share")) {
                    if let photo { Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 220) }
                    Text(WoundL10n.text(bodyText)).font(.callout).textSelection(.enabled)
                }
                Section {
                    Toggle(WoundL10n.text("I agree to email the photo and the details shown above."), isOn: $agreed)
                    Button(WoundL10n.text("Review email")) { showMail = true }.frame(minHeight: 48)
                        .disabled(!agreed || photo == nil || !MFMailComposeViewController.canSendMail())
                    if !MFMailComposeViewController.canSendMail() {
                        Text(WoundL10n.text("Set up an email account in Apple Mail, then return here to send your photo and chosen details."))
                    }
                    if let mailError { Text(WoundL10n.text(mailError)).foregroundStyle(.red) }
                }
            }
            .navigationTitle(WoundL10n.text("Share with WoundCorder"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(WoundL10n.text("Close")) { dismiss() } } }
            .onChange(of: level) { _, _ in agreed = false }
            .sheet(isPresented: $showMail) {
                WoundMailComposer(photo: photo, bodyText: bodyText) { error in
                    mailError = error
                    showMail = false
                }
            }
        }
    }
}
private struct WoundMailComposer: UIViewControllerRepresentable {
    let photo: UIImage?
    let bodyText: String
    let onFinish: (String?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(["info@woundcorder.ai"])
        controller.setSubject(WoundL10n.text("WoundCorder photo share"))
        controller.setMessageBody(bodyText, isHTML: false)
        // Redrawing removes source EXIF/location metadata before attachment.
        if let photo {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            let flattened = UIGraphicsImageRenderer(size: photo.size, format: format).image { _ in photo.draw(in: CGRect(origin: .zero, size: photo.size)) }
            if let data = flattened.jpegData(compressionQuality: 0.9) { controller.addAttachmentData(data, mimeType: "image/jpeg", fileName: "wound-photo.jpg") }
        }
        return controller
    }
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (String?) -> Void
        init(onFinish: @escaping (String?) -> Void) { self.onFinish = onFinish }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish(error?.localizedDescription ?? (result == .failed ? "Email could not be sent. Please try again." : nil))
        }
    }
}
