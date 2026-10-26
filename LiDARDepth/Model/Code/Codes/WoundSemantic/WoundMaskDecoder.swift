import CoreML
import Foundation

/// Decode only explicit single-channel masks. Multi-class/ambiguous outputs need their own contract.
enum WoundMaskDecoder {
    static func probabilities(_ array: MLMultiArray, logits: Bool) -> (width: Int, height: Int, values: [Float])? {
        let shape = array.shape.map(\.intValue)
        guard shape.count >= 2, shape.count <= 4, shape.dropLast(2).allSatisfy({ $0 == 1 }),
              let width = shape.last, width > 0 else { return nil }
        let height = shape[shape.count - 2]
        guard height > 0, height <= 4096, width <= 4096 else { return nil }
        var coordinates = Array(repeating: NSNumber(value: 0), count: shape.count)
        var values: [Float] = []; values.reserveCapacity(width * height)
        for y in 0..<height {
            coordinates[shape.count - 2] = NSNumber(value: y)
            for x in 0..<width {
                coordinates[shape.count - 1] = NSNumber(value: x)
                let raw = array[coordinates].floatValue // Honors non-contiguous strides.
                guard let probability = probability(raw, logits: logits) else { return nil }
                values.append(probability)
            }
        }
        return (width, height, values)
    }
    static func probability(_ value: Float, logits: Bool) -> Float? {
        guard value.isFinite else { return nil }
        if logits { return Float(1 / (1 + exp(-Double(value)))) }
        return (0...1).contains(value) ? value : nil
    }
}
