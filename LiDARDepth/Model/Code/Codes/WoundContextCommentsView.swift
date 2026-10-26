import SwiftUI

struct WoundContextCommentsView: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    let raw: String
    var body: some View {
        if WoundContextComments.parse(raw)?.isUnableToDetermine == true {
            EmptyView() // The result card already presents the explicit abstention.
        } else if let comment = WoundContextComments.parse(raw) {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox(WoundL10n.text("Additional health context")) { Text(comment.summary).frame(maxWidth: .infinity, alignment: .leading) }
                if !comment.observations.isEmpty { section("What the app noticed", values: comment.observations) }
                if !comment.care_questions.isEmpty { section("Questions for your care team", values: comment.care_questions) }
                GroupBox(WoundL10n.text("Keep in mind")) { Text(comment.limitations).frame(maxWidth: .infinity, alignment: .leading) }
            }
        } else if !raw.isEmpty {
            GroupBox(WoundL10n.text("Photo check status")) { Text(WoundL10n.text(raw)).frame(maxWidth: .infinity, alignment: .leading) }
        }
    }
    private func section(_ title: String, values: [String]) -> some View {
        GroupBox(WoundL10n.text(title)) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Label { Text(WoundL10n.text(value)).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "circle.fill").font(.system(size: 5)) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
