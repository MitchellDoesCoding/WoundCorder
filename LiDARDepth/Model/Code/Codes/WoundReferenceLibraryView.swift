import SwiftUI

/// Uses the same bundled examples and education as the prediction results.
struct WoundReferenceLibraryView: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let mode: WoundAppMode
    @State private var searchText = ""
    private var professional: Bool { mode == .professional }
    private var categories: [WoundClass] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return WoundClass.modelOrder.filter { type in
            guard let entry = WoundEducationLibrary.wounds[type.rawValue] else { return false }
            return query.isEmpty || [WoundL10n.text(entry.title), WoundL10n.text(entry.proTitle), entry.title, entry.proTitle, type.rawValue.replacingOccurrences(of: "_", with: " ")]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: WSTheme.Space.lg) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(WoundL10n.text("Wound photo reference")).font(.title2.bold())
                    Text(WoundL10n.text("Find a predicted wound type below to compare its example photos and explanation. Tap a photo for a larger view."))
                    Text(WoundL10n.text("Examples show how wounds can look. Visual similarity cannot confirm a prediction or diagnosis. Wounds can look different across skin tones and stages of healing."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                .wsCard()

                if categories.isEmpty {
                    Text(WoundL10n.text("No matching wound types. Try another name."))
                        .foregroundStyle(.secondary).padding()
                }

                ForEach(categories, id: \.self) { type in
                    if let entry = WoundEducationLibrary.wounds[type.rawValue] {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(WoundL10n.text(professional ? entry.proTitle : entry.title))
                                .font(.title3.bold())
                            if WoundTemplateLibrary.forMode(mode)?.wounds[type.rawValue] != nil {
                                WoundTemplateEducation(key: type.rawValue, mode: mode)
                            } else {
                                Text(WoundL10n.text(professional ? entry.professional : entry.patient))
                                WoundReferencePhotos(woundType: type)
                            }
                            if let url = URL(string: entry.link) {
                                Link(WoundL10n.text("Learn more from MedlinePlus"), destination: url)
                                    .frame(minHeight: 44)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .wsCard()
                    }
                }
            }
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
            .padding(WSTheme.Space.lg)
        }
        .background(WSTheme.Palette.paper.ignoresSafeArea())
        .navigationTitle(WoundL10n.text("Reference"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: WoundL10n.text("Search wound types"))
    }
}

struct WoundReferencePhotoDetail: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let photo: WoundReferencePhoto
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let image = WoundReferencePhotos.exampleImage(photo) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .accessibilityLabel(WoundL10n.text(photo.caption))
                    }
                    Text(WoundL10n.text(photo.caption))
                    Text(photo.attribution).font(.caption).foregroundStyle(.secondary)
                }.padding()
            }
            .navigationTitle(WoundL10n.text("Reference photo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(WoundL10n.text("Done")) { dismiss() }
                }
            }
        }
    }
}
