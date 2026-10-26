#if DEBUG
import SwiftUI
import CoreVideo

@MainActor enum WoundReviewChecks {
    static func run(directory: URL) throws {
        let suite = "WoundReview-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let patient = WoundCorderPatient(profile: PatientProfile(name: "Fixture"))
        let legacy = SavedMeasurement(title: "Legacy", perimeter: 8, area: 4, volume: 0)
        defaults.set(String(decoding: try JSONEncoder().encode([patient]), as: UTF8.self), forKey: WoundCorderPatientStore.storageKey)
        defaults.set(String(decoding: try JSONEncoder().encode([legacy]), as: UTF8.self), forKey: "savedMeasurements")
        let patients = WoundCorderPatientStore(defaults: defaults, directory: directory)
        let measurements = MeasurementLogManager(defaults: defaults, directory: directory)
        precondition(patients.patients == [patient] && measurements.items == [legacy])
        precondition(defaults.string(forKey: "savedMeasurements") == nil)
        precondition(defaults.string(forKey: WoundCorderPatientStore.storageKey) == nil)
        let sameName = patients.ensure(from: patient.profile)!
        precondition(sameName.id != patient.id && patients.patients.count == 2)
        let context = WoundAnalysisContext(id: UUID(), capturedAt: Date(), perimeterCM: 8, areaCM2: 4, volumeCM3: 0.5, volumeSource: "Fixture", quality: "Medium", isPreliminary: true, bodyArea: "Leg", laterality: "Right")
        precondition(measurements.add(title: "New", perimeter: 8, area: 4, volume: 0.5, patientID: sameName.id, context: context))
        precondition(MeasurementLogManager(defaults: defaults, directory: directory).items.first?.context == context)
        precondition(!measurements.add(title: "Invalid", perimeter: 0, area: 0, volume: .nan))
        precondition(measurements.items.count == 2)
        measurements.reload()
        try Data("broken".utf8).write(to: directory.appendingPathComponent("measurements.json"))
        measurements.reload()
        precondition(measurements.storageError != nil)
        precondition(!measurements.add(title: "Blocked", perimeter: 8, area: 4, volume: 0))
        measurements.restorePrevious()
        precondition(measurements.storageError == nil && measurements.items == [legacy])
        precondition(patients.patients.count == 2) // Measurement recovery never edits identities.
        try verifyPreprocessing()
        print("PASS: actual store migration, same-name separation, context persistence, failed-save handling, recovery isolation, image preprocessing")
    }
    private static func verifyPreprocessing() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
            UIColor.green.setFill(); context.fill(CGRect(x: 20, y: 0, width: 20, height: 10))
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 10, width: 20, height: 10))
            UIColor.white.setFill(); context.fill(CGRect(x: 20, y: 10, width: 20, height: 10))
        }
        func pixel(_ buffer: CVPixelBuffer, _ x: Int, _ y: Int) -> [Int] {
            CVPixelBufferLockBaseAddress(buffer, .readOnly); defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            let p = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let i = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
            return [Int(p[i+2]), Int(p[i+1]), Int(p[i])]
        }
        let buffer = try WoundImagePreprocessor.makeModelPixelBuffer(from: image)
        precondition(pixel(buffer, 56, 80) == [255,0,0])
        precondition(pixel(buffer, 168, 80) == [0,255,0])
        precondition(pixel(buffer, 56, 140) == [0,0,255])
        precondition(pixel(buffer, 112, 10) == [124,116,104])
        let rotated = UIImage(cgImage: image.cgImage!, scale: 1, orientation: .down)
        let rotatedBuffer = try WoundImagePreprocessor.makeModelPixelBuffer(from: rotated)
        precondition(pixel(rotatedBuffer, 56, 80) == [255,255,255])
        let mirrored = UIImage(cgImage: image.cgImage!, scale: 1, orientation: .upMirrored)
        let mirroredBuffer = try WoundImagePreprocessor.makeModelPixelBuffer(from: mirrored)
        precondition(pixel(mirroredBuffer, 56, 80) == [0,255,0])
        // Portrait metadata is rendered without stretching; compare with an upright UIKit rendering.
        let portrait = UIImage(cgImage: image.cgImage!, scale: 1, orientation: .right)
        let upright = UIGraphicsImageRenderer(size: portrait.size, format: format).image { _ in portrait.draw(in: CGRect(origin: .zero, size: portrait.size)) }
        let a = try WoundImagePreprocessor.makeModelPixelBuffer(from: portrait)
        let b = try WoundImagePreprocessor.makeModelPixelBuffer(from: upright)
        for y in [20,80,140,200] { for x in [20,80,140,200] { precondition(pixel(a,x,y) == pixel(b,x,y)) } }
    }
}
#endif
