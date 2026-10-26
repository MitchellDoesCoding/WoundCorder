import Foundation
import CoreML

@main struct WoundSensorPolicyTests {
    static func main() throws {
        for invalid: UInt8? in [nil, 0, 3, 255] {
            precondition(!WoundDepthValidation.isUsable(depth: 0.3, confidence: invalid))
            precondition(WoundDepthValidation.normalizedConfidence(invalid) == 0)
        }
        precondition(WoundDepthValidation.isUsable(depth: 0.3, confidence: 1))
        precondition(WoundDepthValidation.isUsable(depth: 0.3, confidence: 2))
        for depth: Float in [.nan, .infinity, -.infinity, 0, -1, 5, 0.02] {
            precondition(!WoundDepthValidation.isUsable(depth: depth, confidence: 2))
        }
        let pointer = UnsafeMutablePointer<Float>.allocate(capacity: 8)
        pointer.initialize(repeating: -99, count: 8)
        pointer[0] = 0; pointer[1] = 1; pointer[4] = 0.5; pointer[5] = 0.25
        let strided = try MLMultiArray(dataPointer: pointer, shape: [1,1,2,2], dataType: .float32, strides: [8,8,4,1], deallocator: { $0.assumingMemoryBound(to: Float.self).deallocate() })
        precondition(WoundMaskDecoder.probabilities(strided, logits: false)?.values == [0,1,0.5,0.25])
        let logits = WoundMaskDecoder.probabilities(strided, logits: true)!.values
        precondition(abs(logits[0] - 0.5) < 0.00001 && abs(logits[2] - 0.622459) < 0.00001)
        pointer[0] = .nan
        precondition(WoundMaskDecoder.probabilities(strided, logits: true) == nil)
        pointer[0] = -1
        precondition(WoundMaskDecoder.probabilities(strided, logits: false) == nil)
        let ambiguous = try MLMultiArray(shape: [1,2,2,2], dataType: .float32)
        precondition(WoundMaskDecoder.probabilities(ambiguous, logits: false) == nil)
        let center = NotificationCenter(), first = NSObject(), second = NSObject()
        var firstCount = 0, secondCount = 0
        let a = center.addObserver(forName: .init("ScanTest"), object: first, queue: nil) { _ in firstCount += 1 }
        let b = center.addObserver(forName: .init("ScanTest"), object: second, queue: nil) { _ in secondCount += 1 }
        center.post(name: .init("ScanTest"), object: nil)
        precondition(firstCount == 0 && secondCount == 0)
        center.post(name: .init("ScanTest"), object: first)
        precondition(firstCount == 1 && secondCount == 0)
        center.removeObserver(a); center.removeObserver(b)
        print("PASS: depth confidence/range rejection, strided mask decoding, logits/probability contracts, nonfinite/ambiguous mask rejection, scan-event isolation")
    }
}
