import SwiftUI

struct WoundStorageRecoveryView: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let message: String
    let canRestore: Bool
    let reload: () -> Void
    let restore: () -> Void
    @State private var confirmRestore = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(WoundL10n.text("Records need attention"), systemImage: "externaldrive.badge.exclamationmark").font(.headline)
            Text(WoundL10n.text(message))
            Button(WoundL10n.text("Try loading again"), action: reload).frame(minHeight: 44)
            if canRestore {
                Button(WoundL10n.text("Restore last saved copy")) { confirmRestore = true }.frame(minHeight: 44)
            }
        }
        .confirmationDialog(WoundL10n.text("Restore the previous saved copy?"), isPresented: $confirmRestore, titleVisibility: .visible) {
            Button(WoundL10n.text("Restore previous copy"), action: restore)
            Button(WoundL10n.text("Cancel"), role: .cancel) {}
        } message: { Text(WoundL10n.text("Recent changes may not be in this copy. The current file will be kept separately for recovery.")) }
    }
}
