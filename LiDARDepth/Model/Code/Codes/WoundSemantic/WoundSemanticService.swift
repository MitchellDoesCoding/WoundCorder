import CoreML
import Foundation
import UIKit

enum WoundSemanticServiceError: Error {
    case modelResourceMissing
    case missingOutput(String)
    case nonFiniteOutput(String)
    case invalidOutputCount(name: String, expected: Int, actual: Int)
}

actor WoundSemanticService {
    private var model: MLModel?

    static var isBundled: Bool {
        Bundle.main.url(forResource: "WoundSemantic", withExtension: "mlmodelc") != nil
    }

    func predict(image: UIImage) throws -> WoundSemanticResult {
        // Loading and inference both run on this actor, away from the UI actor.
        if model == nil {
            guard let url = Bundle.main.url(forResource: "WoundSemantic", withExtension: "mlmodelc") else {
                throw WoundSemanticServiceError.modelResourceMissing
            }
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            model = try MLModel(contentsOf: url, configuration: configuration)
        }
        guard let model else { throw WoundSemanticServiceError.modelResourceMissing }
        let pixelBuffer = try WoundImagePreprocessor.makeModelPixelBuffer(from: image)
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "image": MLFeatureValue(pixelBuffer: pixelBuffer)
        ])
        let output = try model.prediction(from: input)
        let classLogits = try values(output, name: "class_logits", expected: 9)
        let semanticLogits = try values(output, name: "semantic_logits", expected: 8)
        let rawEmbedding = try values(
            output,
            name: "normalized_embedding",
            expected: WoundModelContract.embeddingDimension
        )
        guard let embedding = WoundSemanticMath.normalized(rawEmbedding),
              let probabilities = WoundSemanticMath.probabilities(logits: classLogits, temperature: WoundModelContract.calibrationTemperature) else {
            throw WoundSemanticServiceError.nonFiniteOutput("model outputs")
        }
        let ranked = zip(WoundClass.modelOrder, probabilities)
            .map { RankedWoundPrediction(label: $0.0, probability: $0.1) }
            .sorted { $0.probability > $1.probability }
        let semanticProbabilities = Dictionary(
            uniqueKeysWithValues: zip(
                WoundSemanticAttribute.modelOrder,
                semanticLogits.map(WoundSemanticMath.sigmoid)
            )
        )
        return WoundSemanticResult(
            rankedClasses: ranked,
            semanticProbabilities: semanticProbabilities,
            embedding: embedding,
            isClassificationUncertain: (
                ranked.first?.probability ?? 0
            ) < WoundModelContract.confidenceThreshold
        )
    }

    private func values(
        _ provider: MLFeatureProvider,
        name: String,
        expected: Int
    ) throws -> [Float] {
        guard let array = provider.featureValue(for: name)?.multiArrayValue else {
            throw WoundSemanticServiceError.missingOutput(name)
        }
        guard array.count == expected else {
            throw WoundSemanticServiceError.invalidOutputCount(
                name: name,
                expected: expected,
                actual: array.count
            )
        }
        let values = (0..<array.count).map { array[$0].floatValue }
        guard values.allSatisfy(\.isFinite) else { throw WoundSemanticServiceError.nonFiniteOutput(name) }
        return values
    }


}


extension WoundSemanticServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .modelResourceMissing: return "The bundled Wound CNN is missing. Rebuild the app with WoundSemantic.mlpackage included."
        case .nonFiniteOutput: return "The photo check returned invalid values. Please try another photo."
        case .missingOutput(let name): return "Wound CNN did not return \(name)."
        case .invalidOutputCount(let name, let expected, let actual):
            return "Wound CNN returned \(actual) values for \(name); expected \(expected)."
        }
    }
}

extension WoundSemanticResult {
    func report(measurement: WoundAnalysisContext?) throws -> String {
        let classes = rankedClasses.prefix(2).map { ["label": $0.label.rawValue, "probability": $0.probability] as [String: Any] }
        let semantics = Dictionary(uniqueKeysWithValues: semanticProbabilities.map { ($0.key.rawValue, $0.value) })
        var object: [String: Any] = [
            "model": "WoundSemantic EfficientNet-B0 (Float32)",
            "classification_status": isClassificationUncertain ? "Uncertain — review required" : "Screening prediction — review required",
            "ranked_classes": classes,
            "semantic_probabilities": semantics,
            "limitations": WoundModelContract.clinicalWarning,
            "normal_control_guideline": WoundModelContract.normalControlGuideline
        ]
        if let measurement { object["measurements"] = measurement.metadata }
        return String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }
}
