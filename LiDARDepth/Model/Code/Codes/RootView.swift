import SwiftUI

/// Compatibility entry point: all app routes share consent, setup, and patient intake.
struct RootView: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    var body: some View { WoundCorderAppShell() }
}

#Preview { RootView() }
