import Vision
import CoreML
/*
class WoundDetector {
    private var model: VNCoreMLModel?

    init() {
        do {
            let config = MLModelConfiguration()
            let woundModel = try WoundClassifier(configuration: config)
            self.model = try VNCoreMLModel(for: woundModel.model)
        } catch {
            print("Failed to load ML model: \(error)")
        }
    }

    func detectWound(in image: CGImage, completion: @escaping (CGRect?) -> Void) {
        guard let model = model else { return }

        let request = VNCoreMLRequest(model: model) { request, _ in
            guard let results = request.results as? [VNRecognizedObjectObservation],
                  let wound = results.first else {
                completion(nil)
                return
            }
            completion(wound.boundingBox)
        }

        let handler = VNImageRequestHandler(cgImage: image)
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }
}
*/
