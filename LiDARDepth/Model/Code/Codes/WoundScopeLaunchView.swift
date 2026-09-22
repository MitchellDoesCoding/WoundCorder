import SwiftUI
import UIKit

struct WoundScopeLaunchView: View {
    @State private var isShowingSplash = true

    var body: some View {
        ZStack {
            WoundScopeAppShell()
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
            Color(red: 0.08, green: 0.10, blue: 0.24)
                .ignoresSafeArea()

            if let logo = UIImage(named: "WoundScope") {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 24)
                    .accessibilityLabel("WoundScope")
            }
        }
    }
}

#Preview {
    WoundScopeLaunchView()
}
