import Foundation
import UIKit

struct WoundAnalysisResult: Codable, Sendable {
    struct BoundingBox: Codable, Sendable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }
    let summary: String
    let confidence: Double?
    let boundingBoxes: [BoundingBox]?
}

final class WoundDetector: @unchecked Sendable {
    private let service = WoundSemanticService()
    func analyze(image: UIImage) async throws -> WoundAnalysisResult {
        let result = try await service.predict(image: image)
        return WoundAnalysisResult(summary: try result.report(measurement: nil), confidence: result.rankedClasses.first.map { Double($0.probability) }, boundingBoxes: nil)
    }
}
