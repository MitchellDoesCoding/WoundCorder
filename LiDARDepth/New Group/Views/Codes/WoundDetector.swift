import Foundation
import UIKit



///
///
///DONT PUT FILE IN
///
///
#if targetEnvironment(simulator)
// Simulator can reach your Mac via loopback:
private let defaultBase = "http://127.0.0.1:3000"
#else
// On device: replace with your Mac’s LAN IP (same Wi-Fi as device)
private let defaultBase = "https://6727e030ebe5.ngrok-free.app" //Change if needed
#endif

private let defaultDetectorEndpoint = "\(defaultBase)/api/analyze-wound"

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
    private let session: URLSession
    private let endpointURL: URL
    // Give the backend a bit more time (model call, etc.)
    private let timeout: TimeInterval = 120

    init(endpoint: URL = URL(string: defaultDetectorEndpoint)!, session: URLSession = .shared) {
        self.endpointURL = endpoint
        self.session = session
    }

    enum DetectorError: Error {
        case encodingFailed
        case badResponse
        case server(String)
    }

    func analyze(image: UIImage) async throws -> WoundAnalysisResult {
        return try await analyze(image: image, metadata: nil)
    }

    func analyze(image: UIImage, metadata: [String: String]?) async throws -> WoundAnalysisResult {
        guard let jpegData = image.jpegData(compressionQuality: 0.85) else {
            throw DetectorError.encodingFailed
        }
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        request.setValue(
            "fsdat-vlnkhiou439o7yn-sdspm08-9up4ji-opsp4p3vp8", /// DO NOT PAST
            ///E IN
            forHTTPHeaderField: "x-api-key" ////DO NOT PUt This fiLE IN
        )

        let metadataData: Data? = {
            guard let metadata else { return nil }
            return try? JSONSerialization.data(withJSONObject: metadata, options: [])
        }()

        request.httpBody = makeMultipartBody(
            boundary: boundary,
            data: jpegData,
            fileName: "wound.jpg",
            fieldName: "file",
            mimeType: "image/jpeg",
            metadataJSON: metadataData
        )
        request.timeoutInterval = timeout

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw DetectorError.badResponse }
            guard 200..<300 ~= http.statusCode else {
                let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                throw DetectorError.server(msg)
            }
            return try JSONDecoder().decode(WoundAnalysisResult.self, from: data)
        } catch let urlError as URLError {
            switch urlError.code {
            case .timedOut:
                throw DetectorError.server(
                    """
                    Server took too long to respond (request timed out).
                    Your request DID reach the server at \(endpointURL.absoluteString),
                    but it didn't answer within \(Int(timeout))s.
                    """
                )
            case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                throw DetectorError.server(
                    """
                    Cannot connect to \(endpointURL.absoluteString).
                    • If you're on device: make sure the ngrok URL is current.
                    • If you restarted ngrok, update defaultBase.
                    • Make sure server is still running.
                    """
                )
            default:
                throw urlError
            }
        }

    }

    private func makeMultipartBody(boundary: String, data: Data, fileName: String, fieldName: String, mimeType: String, metadataJSON: Data?) -> Data {
        var body = Data()

        // File part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)

        // Optional metadata JSON part
        if let metadataJSON {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"metadata\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
            body.append(metadataJSON)
            body.append("\r\n".data(using: .utf8)!)
        }

        // Closing boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}
