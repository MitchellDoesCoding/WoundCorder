import SwiftUI

struct WoundMeasurementOverlay: View {
    @AppStorage("woundLanguage") private var presentationLanguage = WoundLanguage.english.rawValue
    struct Model {
        var areaText: String = "--"
        var volumeText: String = "--"
        var confidence: Confidence = .low
        var isPreliminary: Bool = false
        enum Confidence: String { case low = "Low", medium = "Medium", high = "High" }
    }

    @State var model: Model

    var body: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(WoundL10n.text("Area:"))
                            .font(.headline)
                        Text(WoundL10n.text(model.areaText))
                            .font(.headline)
                    }
                    HStack(spacing: 8) {
                        Text(WoundL10n.text("Volume:"))
                            .font(.subheadline)
                        Text(WoundL10n.text(model.volumeText + (model.isPreliminary ? " (prelim)" : "")))
                            .font(.subheadline)
                    }
                    HStack(spacing: 8) {
                        Text(WoundL10n.text("Confidence:"))
                            .font(.caption)
                        Text(WoundL10n.text(model.confidence.rawValue))
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(confidenceColor.opacity(0.2))
                            .foregroundStyle(confidenceColor)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding([.top, .horizontal])

            Spacer()

            HStack(spacing: 12) {
                Button {
                    NotificationCenter.default.post(name: NSNotification.Name("StartMeasureFlow"), object: nil)
                } label: {
                    HStack {
                        Image(systemName: "ruler")
                        Text(WoundL10n.text("Measure Wound"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    NotificationCenter.default.post(name: NSNotification.Name("SelectDepthPoint"), object: nil)
                } label: {
                    HStack {
                        Image(systemName: "scope")
                        Text(WoundL10n.text("Select Depth"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
    }

    private var confidenceColor: Color {
        switch model.confidence {
        case .low: return .orange
        case .medium: return .yellow
        case .high: return .green
        }
    }
}

#Preview {
    WoundMeasurementOverlay(model: .init(areaText: "24.3 cm²", volumeText: "12.1 cm³", confidence: .medium, isPreliminary: true))
        .background(Color.black.opacity(0.8))
}
