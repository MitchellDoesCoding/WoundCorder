import SwiftUI

@main
struct LiDARDepthApp: App {
    @AppStorage("woundLanguage") private var language = WoundLanguage.english.rawValue
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--review-languages") {
                WoundLanguageReviewHarness()
            } else if ProcessInfo.processInfo.arguments.contains("--review-results") {
                WoundReviewHarness().environment(\.locale, Locale(identifier: language))
            } else {
                WoundCorderLaunchView().background(WoundPrivacyShield()).environment(\.locale, Locale(identifier: language))
            }
#else
            WoundCorderLaunchView().background(WoundPrivacyShield()).environment(\.locale, Locale(identifier: language))
#endif
        }
    }
}
