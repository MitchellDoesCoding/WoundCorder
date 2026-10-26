import SwiftUI

/// Older callers use the same guided flow, so they cannot bypass consent or intake.
struct WoundDetectionView: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    var body: some View { WoundCorderAppShell() }
}
