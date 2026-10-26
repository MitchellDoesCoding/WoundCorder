import SwiftUI
import UIKit

struct WoundCorderLaunchView: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    @State private var isShowingSplash = true
    @AppStorage("woundAppMode") private var modeRaw = WoundAppMode.publicPatient.rawValue

    var body: some View {
        ZStack {
            WoundCorderAppShell()
                .opacity(isShowingSplash ? 0 : 1)
                .allowsHitTesting(!isShowingSplash)

            if isShowingSplash {
                splash
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(950))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                isShowingSplash = false
            }
        }
    }

    private var splash: some View {
        ZStack {
            (WoundAppMode(rawValue: modeRaw) ?? .publicPatient).wsSoft
                .ignoresSafeArea()

            if let logo = UIImage(named: "WoundCorder") {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 24)
                    .accessibilityLabel(WoundL10n.text("WoundCorder"))
            }
        }
    }
}

#Preview {
    WoundCorderLaunchView()
}
