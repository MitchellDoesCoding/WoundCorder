import Foundation

@main
struct WoundAnalysisContextTests {
    static func main() throws {
        let scan = WoundAnalysisContext(
            id: UUID(), capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            perimeterCM: 12, areaCM2: 8, volumeCM3: 2,
            volumeSource: "LiDAR mesh", quality: "Good", isPreliminary: false,
            bodyArea: "Lower Leg", laterality: "L"
        )
        let prompt = WoundAnalysisPrompt.make(base: "Return JSON.", measurement: scan,
            additional: ["notes": "Line one\n\"quoted\""], cnn: "CNN observation")
        for (key, value) in scan.metadata {
            assert(prompt.contains(key), "Prompt dropped \(key)")
            assert(!value.isEmpty)
        }
        assert(scan.metadata["estimated_mean_depth_cm"] == "0.25")
        assert(prompt.contains("not a directly measured maximum depth"))
        assert(prompt.contains("not expert labels or confirmed diagnoses"))
        assert(prompt.contains("Return JSON."))
        let unattached = WoundAnalysisPrompt.make(base: "Return JSON.", measurement: nil)
        assert(unattached.contains("No associated measurement"))
        assert(!unattached.contains(scan.id.uuidString))
        let invalid = WoundAnalysisContext(
            id: UUID(), capturedAt: Date(), perimeterCM: .nan, areaCM2: 0, volumeCM3: .infinity,
            volumeSource: "Unavailable", quality: "Low", isPreliminary: true,
            bodyArea: "Foot", laterality: "R"
        )
        assert(invalid.metadata["estimated_mean_depth_cm"] == nil)
        assert(invalid.metadata["perimeter_cm"] == "unavailable")
        assert(invalid.metadata["volume_cm3"] == "unavailable")
        assert(scan.shareText.contains("cm²") && scan.shareText.contains("cm³"))
        assert(scan.shareText.contains("Preliminary: No"))
        assert(invalid.shareText.contains("Preliminary: Yes"))
        assert(invalid.shareText.contains("unavailable") && !invalid.shareText.contains("nan"))
        let decoded = try JSONDecoder().decode(WoundAnalysisContext.self, from: JSONEncoder().encode(scan))
        assert(decoded == scan)
        print("PASS: measurement units, prompt inclusion, CNN context, missing/invalid values, and snapshot round trip")
    }
}
