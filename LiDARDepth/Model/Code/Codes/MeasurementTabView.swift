import SwiftUI

/// Compatibility entry point: history only. Live capture is owned solely by ContentView.
struct MeasurementTabView: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    var body: some View { MeasurementLogListView() }
}
