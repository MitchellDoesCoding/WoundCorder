import SwiftUI

/// Compatibility route. All camera entry points use consent, named intake, and the current capture flow.
struct WoundCameraView: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    var body: some View { WoundCorderLaunchView() }
}
