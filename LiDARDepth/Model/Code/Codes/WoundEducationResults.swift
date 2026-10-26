import SwiftUI

struct WoundEducationEntry: Decodable {
    let title: String
    let patient: String
    let professional: String
    let proTitle: String
    let caution: String
    let link: String
}
struct TissueEducationEntry: Decodable {
    let title: String
    let text: String
}
enum WoundEducationLibrary {
    static let wounds: [String: WoundEducationEntry] = load("wound-education")
    static let tissues: [String: TissueEducationEntry] = load("tissue-education")
    static func load<T: Decodable>(_ name: String) -> [String: T] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode([String: T].self, from: data) else { return [:] }
        return value
    }
}

extension WoundSemanticResult {
    var isPhotoAdequate: Bool {
        guard let background = semanticProbabilities[.backgroundNonSkin], background.isFinite, (0...1).contains(background) else { return false }
        return background < 0.5
    }
    func displayedPredictions(combined: Bool) -> [RankedWoundPrediction] {
        guard isPhotoAdequate, !isClassificationUncertain else { return [] }
        return Array(rankedClasses.prefix(WoundWorkflowPolicy.candidateCount(topProbability: rankedClasses.first?.probability ?? 0, combined: combined)))
    }
}

struct WoundEducationResults: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let result: WoundSemanticResult
    let mode: WoundAppMode
    let combined: Bool
    var contextComments: String = ""
    private var professional: Bool { mode == .professional }
    var body: some View {
        if !result.isPhotoAdequate {
            GroupBox(WoundL10n.text("Try another photo")) {
                Text(WoundL10n.text("The app could not clearly find skin in this photo. Move closer, use good light, and take a clear photo of the wound. This does not mean the skin is healthy."))
            }
        } else if result.isClassificationUncertain || result.rankedClasses.isEmpty ||
                    WoundContextComments.parse(contextComments)?.isUnableToDetermine == true {
            GroupBox(WoundL10n.text("Unable to determine")) {
                Label(WoundL10n.text(WoundContextComments.unsureMessage), systemImage: "questionmark.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
        VStack(alignment: .leading, spacing: 20) {
            Label(WoundL10n.text((combined ? WoundAnalysisProvider.onDevice : .semanticCNN).name(professional: professional)), systemImage: "photo.badge.checkmark").font(.title2.bold())
            Text(WoundL10n.text("These are possible matches, not a diagnosis. A doctor or nurse should check the wound.")).foregroundStyle(.secondary)
            if result.isClassificationUncertain {
                Label(WoundL10n.text("The app is unsure. Ask your care team to check this wound."), systemImage: "questionmark.circle").font(.headline)
            }
            ForEach(result.displayedPredictions(combined: combined), id: \.label) { prediction in
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        if let entry = WoundEducationLibrary.wounds[prediction.label.rawValue] {
                            Text(WoundL10n.text(professional ? entry.proTitle : entry.title)).font(.headline)
                            Text(WoundL10n.text("Photo match: \(Int((prediction.probability * 100).rounded()))%"))
                                .font(.subheadline).foregroundStyle(.secondary)
                            ProgressView(value: Double(prediction.probability)).tint(mode.wsPrimary)
                            if WoundTemplateLibrary.forMode(mode)?.wounds[prediction.label.rawValue] != nil {
                                WoundTemplateEducation(key: prediction.label.rawValue, mode: mode)
                            } else {
                                Text(WoundL10n.text(professional ? entry.professional : entry.patient))
                                WoundReferencePhotos(woundType: prediction.label)
                            }
                            if let url = URL(string: entry.link) { Link(WoundL10n.text("Learn more from MedlinePlus"), destination: url).frame(minHeight: 44) }
                        } else { Text(WoundL10n.text(prediction.label.rawValue.replacingOccurrences(of: "_", with: " "))) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            GroupBox(WoundL10n.text(professional ? "Tissue observations" : "Tissue in the photo")) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(WoundL10n.text("Colors can give clues, but a photo cannot confirm tissue health.")).foregroundStyle(.secondary)
                    ForEach(WoundSemanticAttribute.modelOrder.filter { (result.semanticProbabilities[$0] ?? 0) >= 0.5 }, id: \.self) { tissue in
                        if WoundTemplateLibrary.forMode(mode)?.tissues[tissue.rawValue] != nil || WoundEducationLibrary.tissues[tissue.rawValue] != nil {
                            VStack(alignment: .leading, spacing: 6) {
                                if WoundTemplateLibrary.forMode(mode)?.tissues[tissue.rawValue] != nil {
                                    WoundTemplateEducation(key: tissue.rawValue, mode: mode, tissue: true)
                                } else if let entry = WoundEducationLibrary.tissues[tissue.rawValue] {
                                    Text(WoundL10n.text(entry.title)).font(.headline)
                                    Text(WoundL10n.text(entry.text))
                                }
                            }
                        }
                    }
                    if !WoundSemanticAttribute.modelOrder.contains(where: { (WoundTemplateLibrary.forMode(mode)?.tissues[$0.rawValue] != nil || WoundEducationLibrary.tissues[$0.rawValue] != nil) && (result.semanticProbabilities[$0] ?? 0) >= 0.5 }) {
                        Text(WoundL10n.text("No clear tissue match. Ask your care team to check."))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if professional {
                WoundTemplateClinicianReview()
                GroupBox(WoundL10n.text("TIME / TIMERS review")) {
                    Text(WoundL10n.text("Assess tissue, infection/inflammation, moisture, wound edge, nutrition, glycemic control, pain, and social factors. Document location, size, depth, exudate, tissue, peri-wound skin, pain, and odor. Do not debride dry ischemic eschar before vascular assessment. Escalate spreading or deep infection, ischemia, atypical wounds, or wounds failing to improve."))
                }
            }
            GroupBox(WoundL10n.text("When to get help")) {
                Text(WoundL10n.text("Call your doctor or nurse for more redness, swelling, warmth, pain, pus, bad smell, fever, or a wound that gets bigger or does not heal. Get urgent help for bleeding that will not stop."))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }.fixedSize(horizontal: false, vertical: true)
        }
    }
    static func shareText(result: WoundSemanticResult?, mode: WoundAppMode, combined: Bool, contextComments: String = "") -> String {
        guard let result else { return WoundL10n.text("No photo check result.") }
        guard result.isPhotoAdequate else { return WoundL10n.text("Photo quality was not sufficient for a wound check. Take another photo.") }
        guard !result.isClassificationUncertain, !result.rankedClasses.isEmpty,
              WoundContextComments.parse(contextComments)?.isUnableToDetermine != true else {
            return WoundL10n.text(WoundContextComments.unsureMessage)
        }
        return result.displayedPredictions(combined: combined).map { prediction in
            let entry = WoundEducationLibrary.wounds[prediction.label.rawValue]
            if let template = WoundTemplateLibrary.forMode(mode)?.wounds[prediction.label.rawValue] {
                let guidance = mode == .professional ? template.nurse : template.patient
                let steps = guidance.steps.filter { $0.count >= 2 }.map { WoundL10n.text($0[0]) + ": " + WoundL10n.text($0[1]) }.joined(separator: "\n")
                return "\(WoundL10n.text(template.title)): \(WoundL10n.text("\(Int((prediction.probability * 100).rounded()))% photo match"))\n\(WoundL10n.text(guidance.description))\n\(steps)"
            }
            return "\(WoundL10n.text(entry?.title ?? prediction.label.rawValue)): \(WoundL10n.text("\(Int((prediction.probability * 100).rounded()))% photo match"))\n\(WoundL10n.text(mode == .professional ? entry?.professional ?? "" : entry?.patient ?? ""))"
        }.joined(separator: "\n\n") + "\n" + WoundL10n.text("Possible matches only. Not a diagnosis.")
    }
}

// Only reviewed, bundled examples may appear here. User photos are never repurposed as examples.
struct WoundReferencePhoto: Decodable, Identifiable {
    let id: String
    let woundType: WoundClass
    let assetName: String
    let caption: String
    let attribution: String
}
struct WoundReferencePhotos: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let woundType: WoundClass
    @State private var selectedPhoto: WoundReferencePhoto?
    static let references: [WoundReferencePhoto] = {
        guard let url = Bundle.main.url(forResource: "wound-reference-photos", withExtension: "json", subdirectory: "WoundReferenceExamples"),
              let data = try? Data(contentsOf: url),
              let all = try? JSONDecoder().decode([WoundReferencePhoto].self, from: data) else { return [] }
        return all
    }()
    static func exampleImage(_ photo: WoundReferencePhoto) -> UIImage? {
        guard let url = Bundle.main.url(forResource: photo.assetName, withExtension: "jpg", subdirectory: "WoundReferenceExamples") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
    private var photos: [WoundReferencePhoto] {
        Array(Self.references.filter { $0.woundType == woundType && Self.exampleImage($0) != nil }.prefix(2))
    }
    var body: some View {
        if !photos.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(WoundL10n.text("Example photos — wounds can look different")).font(.headline)
                ForEach(photos) { photo in
                    if let image = Self.exampleImage(photo) {
                        Button { selectedPhoto = photo } label: {
                            Image(uiImage: image).resizable().scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 240)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(WoundL10n.text("Reference photo: \(photo.caption)"))
                        .accessibilityHint(WoundL10n.text("Opens a larger photo"))
                    }
                    Text(WoundL10n.text(photo.caption)).font(.callout)
                    Text(photo.attribution).font(.caption).foregroundStyle(.secondary)
                }
            }
            .sheet(item: $selectedPhoto) { photo in
                WoundReferencePhotoDetail(photo: photo)
            }
        }
    }
}
