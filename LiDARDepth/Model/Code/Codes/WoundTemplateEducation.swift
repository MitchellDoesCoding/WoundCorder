import SwiftUI

struct WoundTemplateLibrary: Decodable {
    struct Guidance: Decodable {
        let description: String
        let steps: [[String]]
        let references: [Int]?
    }
    struct Wound: Decodable {
        let title: String
        let images: [String]
        let patient: Guidance
        let nurse: Guidance
    }
    struct Tissue: Decodable {
        let title: String
        let patient: String
        let nurse: String
        let overnight: String?
        let references: [Int]?
    }
    struct RedFlag: Decodable {
        let title: String
        let text: String
        init(from decoder: Decoder) throws {
            var values = try decoder.unkeyedContainer()
            title = try values.decode(String.self)
            text = try values.decode(String.self)
        }
    }
    struct Triage: Decodable {
        let purpose: String
        let modelRole: String
        let redFlags: [RedFlag]
        let documentation: String
        let universalDos: String
        let universalDonts: String
    }
    let wounds: [String: Wound]
    let tissues: [String: Tissue]
    let references: [String]
    let triage: Triage

    static let patient = load("patient")
    static let clinician = load("clinician")
    static func forMode(_ mode: WoundAppMode) -> Self? {
        mode == .professional ? clinician : patient
    }
    private static func load(_ mode: String) -> Self? {
        guard let url = Bundle.main.url(forResource: "template-" + mode, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

struct WoundTemplateEducation: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let key: String
    let mode: WoundAppMode
    var tissue = false
    private var professional: Bool { mode == .professional }

    var body: some View {
        if let library = WoundTemplateLibrary.forMode(mode) {
            VStack(alignment: .leading, spacing: 12) {
                if tissue, let entry = library.tissues[key] {
                    Text(WoundL10n.text(entry.title)).font(.headline)
                    Text(WoundL10n.text(professional ? entry.nurse : entry.patient))
                    if professional, let overnight = entry.overnight {
                        Text(WoundL10n.text("Overnight care")).font(.subheadline.bold())
                        Text(WoundL10n.text(overnight))
                    }
                    if professional { references(entry.references ?? [], library: library) }
                } else if let entry = library.wounds[key] {
                    let guidance = professional ? entry.nurse : entry.patient
                    Text(WoundL10n.text(guidance.description))
                    ForEach(Array(guidance.steps.enumerated()), id: \.offset) { _, step in
                        if step.count >= 2 {
                            Text(WoundL10n.text(step[0])).font(.subheadline.bold())
                            Text(WoundL10n.text(step[1]))
                        }
                    }
                    if !entry.images.isEmpty {
                        Text(WoundL10n.text("Example photos — wounds can look different")).font(.headline)
                        ForEach(entry.images, id: \.self) { path in
                            let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                            TemplateExamplePhoto(asset: "template-" + (professional ? "clinician-" : "patient-") + stem,
                                                 title: entry.title)
                        }
                    }
                    if professional { references(guidance.references ?? [], library: library) }
                }
            }
        }
    }

    @ViewBuilder private func references(_ indices: [Int], library: WoundTemplateLibrary) -> some View {
        if !indices.isEmpty {
            DisclosureGroup(WoundL10n.text("Sources from the supplied guide")) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(indices, id: \.self) { number in
                        if library.references.indices.contains(number - 1) {
                            Text(WoundL10n.text("\(number). \(library.references[number - 1])")).font(.caption)
                        }
                    }
                }
            }
        }
    }
}

private struct TemplateExamplePhoto: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let asset: String
    let title: String
    @State private var expanded = false
    var body: some View {
        Button { expanded = true } label: {
            Image(asset).resizable().scaledToFit().frame(maxHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(WoundL10n.text("\(title) reference photo"))
        .accessibilityHint(WoundL10n.text("Opens a larger photo"))
        .sheet(isPresented: $expanded) {
            NavigationStack {
                ScrollView { Image(asset).resizable().scaledToFit().padding() }
                    .navigationTitle(WoundL10n.text(title))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(WoundL10n.text("Done")) { expanded = false } } }
            }
        }
    }
}

struct WoundTemplateClinicianReview: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    var body: some View {
        if let triage = WoundTemplateLibrary.clinician?.triage {
            GroupBox(WoundL10n.text("Clinical safety and overnight review")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(WoundL10n.text(triage.purpose))
                    Text(WoundL10n.text(triage.modelRole))
                    ForEach(Array(triage.redFlags.enumerated()), id: \.offset) { _, flag in
                        Text(WoundL10n.text(flag.title)).font(.headline)
                        Text(WoundL10n.text(flag.text))
                    }
                    Text(WoundL10n.text("General care")).font(.headline)
                    Text(WoundL10n.text(triage.universalDos))
                    Text(WoundL10n.text(triage.universalDonts))
                    Text(WoundL10n.text("Documentation")).font(.headline)
                    Text(WoundL10n.text(triage.documentation))
                }
            }
        }
    }
}
