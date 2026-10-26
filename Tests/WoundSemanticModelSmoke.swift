import CoreML
import CoreVideo
import Foundation

// Host smoke test: validates the actual bundled model's input/output contract.
@main
struct WoundSemanticModelSmoke {
    static func main() throws {
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let compiled = try MLModel.compileModel(at: source)
        defer { try? FileManager.default.removeItem(at: compiled) }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        let model = try MLModel(contentsOf: compiled, configuration: configuration)
        var buffer: CVPixelBuffer?
        precondition(CVPixelBufferCreate(kCFAllocatorDefault, 224, 224, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess)
        let image = buffer!
        CVPixelBufferLockBaseAddress(image, [])
        let bytes = CVPixelBufferGetBaseAddress(image)!.assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(image)
        for y in 0..<224 {
            for x in 0..<224 {
                let offset = y * rowBytes + x * 4
                bytes[offset] = 104
                bytes[offset + 1] = 116
                bytes[offset + 2] = 124
                bytes[offset + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(image, [])
        let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: image)]))
        for (name, count) in ["class_logits": 9, "semantic_logits": 8, "normalized_embedding": 1280] {
            let array = output.featureValue(for: name)!.multiArrayValue!
            precondition(array.count == count)
            precondition((0..<count).allSatisfy { array[$0].floatValue.isFinite })
        }
        let embedding = output.featureValue(for: "normalized_embedding")!.multiArrayValue!
        let norm = sqrt((0..<1280).reduce(Float(0)) { $0 + pow(embedding[$1].floatValue, 2) })
        precondition(abs(norm - 1) < 0.001)
        print("PASS: Core ML inference; 9 class logits, 8 semantic logits, normalized 1280-vector; all finite")
    }
}
