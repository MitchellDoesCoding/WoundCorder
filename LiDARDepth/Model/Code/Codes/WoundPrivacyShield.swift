import SwiftUI
import UIKit

/// Covers the whole window, including presented camera/results/health sheets, in app-switcher snapshots.
struct WoundPrivacyShield: UIViewRepresentable {
    func makeUIView(context: Context) -> ShieldObserver { ShieldObserver() }
    func updateUIView(_ uiView: ShieldObserver, context: Context) {}

    final class ShieldObserver: UIView {
        private var observers: [NSObjectProtocol] = []
        private var cover: UIView?
        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            observers = [
                NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.showCover() },
                NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.hideCover() }
            ]
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        deinit { observers.forEach(NotificationCenter.default.removeObserver); cover?.removeFromSuperview() }
        private func showCover() {
            guard cover == nil, let window else { return }
            let panel = UIView(frame: window.bounds)
            panel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            panel.backgroundColor = .systemBackground
            let label = UILabel()
            label.text = WoundL10n.text("WoundCorder\nYour health details are private")
            label.numberOfLines = 0
            label.textAlignment = .center
            label.font = .preferredFont(forTextStyle: .title2)
            label.frame = panel.bounds
            label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            panel.addSubview(label)
            window.addSubview(panel)
            cover = panel
        }
        private func hideCover() { cover?.removeFromSuperview(); cover = nil }
    }
}
