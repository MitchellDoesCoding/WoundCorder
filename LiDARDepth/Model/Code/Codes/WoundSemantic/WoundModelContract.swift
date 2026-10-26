import Foundation

enum WoundClass: String, CaseIterable, Codable, Sendable {
    case abrasion
    case bruise
    case burn
    case diabeticFootUlcer = "diabetic_foot_ulcer"
    case lacerationOrCut = "laceration_or_cut"
    case normalControl = "normal_control"
    case pressureInjury = "pressure_injury"
    case surgicalWound = "surgical_wound"
    case venousLegUlcer = "venous_leg_ulcer"

    static let modelOrder: [WoundClass] = [
        .abrasion,
        .bruise,
        .burn,
        .diabeticFootUlcer,
        .lacerationOrCut,
        .normalControl,
        .pressureInjury,
        .surgicalWound,
        .venousLegUlcer,
    ]
}

enum WoundSemanticAttribute: String, CaseIterable, Codable, Sendable {
    case inflammation
    case normalSkin = "normal_skin"
    case epithelial
    case granulation
    case sloughFibrin = "slough_fibrin"
    case necroticEschar = "necrotic_eschar"
    case callus
    case backgroundNonSkin = "background_non_skin"

    static let modelOrder: [WoundSemanticAttribute] = [
        .inflammation,
        .normalSkin,
        .epithelial,
        .granulation,
        .sloughFibrin,
        .necroticEschar,
        .callus,
        .backgroundNonSkin,
    ]
}

enum WoundModelContract {
    static let inputSize = 224
    static let embeddingDimension = 1_280
    static let neutralFillRGB = (red: 124, green: 116, blue: 104)
    static let calibrationTemperature: Float = 1.057018
    static let confidenceThreshold: Float = 0.36

    static let normalControlGuideline =
        "No open wound is present. Benign lesions or other non-open skin findings may still be visible."

    static let clinicalWarning =
        "Research screening output only. It is not a diagnosis or treatment recommendation."
}

struct RankedWoundPrediction: Codable, Sendable, Equatable {
    let label: WoundClass
    let probability: Float
}

struct WoundSemanticResult: Sendable {
    let rankedClasses: [RankedWoundPrediction]
    let semanticProbabilities: [WoundSemanticAttribute: Float]
    let embedding: [Float]
    let isClassificationUncertain: Bool
}

