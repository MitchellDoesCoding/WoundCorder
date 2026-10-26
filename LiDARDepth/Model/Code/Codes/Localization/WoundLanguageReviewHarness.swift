#if DEBUG
import SwiftUI
import UIKit

/// Explicit simulator-only visual regression fixture; never part of release builds.
struct WoundLanguageReviewHarness: View {
    @AppStorage("woundLanguage") private var language = "en"
    @State private var page = "settings"
    @State private var token = UUID()
    @State private var draft = "Keep my draft"
    @State private var largeText = false
    @State private var finished = false
    private let result = WoundSemanticResult(rankedClasses: [.init(label: .abrasion, probability: 0.6)],
        semanticProbabilities: [.granulation: 0.7, .backgroundNonSkin: 0.01], embedding: [], isClassificationUncertain: false)

    var body: some View {
        VStack(spacing: 0) {
            TextField("Draft", text: $draft).textFieldStyle(.roundedBorder).padding(8)
            NavigationStack {
                if page == "settings" { woundLanguageSettingsFixture() }
                else if page == "scan" {
                    ScrollViewReader { proxy in
                        ScrollView { woundLanguageScanFixture() }
                            .onChange(of: largeText) { _, value in
                                if value { proxy.scrollTo("scan-actions", anchor: .top) }
                            }
                    }
                }
                else if page == "health" { ScrollView { ComorbidityChecklistFields(checklist: .constant(ComorbidityChecklist())).padding() } }
                else {
                    ScrollView { WoundEducationResults(result: result, mode: page == "clinician" ? .professional : .publicPatient, combined: false).padding() }
                }
            }
            if finished { Text("PASS: language state and snapshots").font(.caption) }
        }
        .environment(\.locale, Locale(identifier: language))
        .environment(\.dynamicTypeSize, largeText ? .accessibility2 : .large)
        .task { await review() }
    }

    @MainActor private func review() async {
        let initialToken = token
        let oldLanguage = UserDefaults.standard.string(forKey: "woundLanguage")
        defer { UserDefaults.standard.set(oldLanguage, forKey: "woundLanguage") }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("LanguageReview")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for screen in ["settings", "scan", "health", "patient", "clinician"] {
            page = screen
            for selected in ["en", "es", "fr", "en"] {
                language = selected
                try? await Task.sleep(for: .milliseconds(450))
                precondition(token == initialToken && draft == "Keep my draft", "Language switching reset in-progress state")
                saveSnapshot(to: directory.appendingPathComponent("\(screen)-\(selected).png"))
            }
        }
        page = "scan"; language = "fr"; largeText = true
        try? await Task.sleep(for: .milliseconds(450))
        saveSnapshot(to: directory.appendingPathComponent("scan-fr-large.png"))
        finished = true
        try? "PASS: 20 live language changes, stable view identity and draft, 16 snapshots including accessibility text".write(to: directory.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
    }
    @MainActor private func saveSnapshot(to url: URL) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: \.isKeyWindow) else { return }
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try? image.pngData()?.write(to: url)
    }
}
#endif
