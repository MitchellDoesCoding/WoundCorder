import AVFoundation
import Foundation
import SwiftUI
import UIKit

enum WoundAppMode: String, CaseIterable, Identifiable {
    case publicPatient = "Consumer"
    case professional = "Pro"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .publicPatient: return "Consumer"
        case .professional: return "Professional"
        }
    }

    var systemImage: String {
        switch self {
        case .publicPatient: return "person.crop.circle.badge.checkmark"
        case .professional: return "stethoscope.circle.fill"
        }
    }

    var shortDetail: String {
        switch self {
        case .publicPatient:
            return "Simple language, personal progress, and clear next steps."
        case .professional:
            return "Clinical terminology, structured observations, risk flags, and review notes."
        }
    }

    var analysisPrompt: String {
        switch self {
        case .publicPatient:
            return """
            You are WoundCorder's patient-facing wound documentation assistant. Analyze the wound image cautiously and use simple, reassuring language. Do not diagnose, prescribe, or replace clinician judgment. Return strict JSON only with these keys: summary_html, capture_quality, what_to_watch, care_questions, when_to_contact_clinician, limitations. summary_html must be concise HTML using h2, p, ul, li, and strong tags only. Explain uncertainty plainly and remind the user to contact a clinician for worsening pain, spreading redness, fever, odor, pus, bleeding, or rapid deterioration.
            """
        case .professional:
            return """
            You are WoundCorder's clinician-facing wound documentation assistant. Analyze the wound image cautiously for documentation support, not autonomous diagnosis or treatment. Return strict JSON only with these keys: summary_html, wound_bed_observations, periwound_observations, exudate_or_infection_concerns, severity_rationale, capture_quality, recommended_review_actions, limitations. summary_html must be clinically detailed HTML using h2, p, ul, li, table, tr, th, td, and strong tags only. Include uncertainty, image-quality caveats, and clinician review language.
            """
        }
    }
}

enum HomeAppearanceMode: String, CaseIterable, Identifiable {
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme {
        switch self {
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var systemImage: String {
        switch self {
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.fill"
        }
    }
}

enum PatientGender: String, CaseIterable, Identifiable {
    case male = "M"
    case female = "F"
    case other = "O"

    var id: String { rawValue }
}

enum Laterality: String, CaseIterable, Identifiable {
    case right = "R"
    case left = "L"

    var id: String { rawValue }
}

enum BodyArea: String, CaseIterable, Identifiable {
    case head = "Head"
    case upperLimbs = "Upper Limbs"
    case torso = "Torso"
    case lowerLimbs = "Lower Limbs"
    case hands = "Hands"
    case feet = "Feet"
    case joints = "Joints"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .head: return "person.crop.circle"
        case .upperLimbs: return "figure.arms.open"
        case .torso: return "figure.core.training"
        case .lowerLimbs: return "figure.walk"
        case .hands: return "hand.raised"
        case .feet: return "shoeprints.fill"
        case .joints: return "figure.flexibility"
        }
    }
}

enum WoundContext: String, CaseIterable, Identifiable {
    case physicalAccident = "Physical Accident"
    case fire = "Fire"
    case chemicalHazard = "Chemical Hazard"
    case disease = "Disease"
    case bedSores = "Bed Sores"
    case violence = "Violence"
    case bandaged = "Bandaged/Covered"
    case other = "Other"

    var id: String { rawValue }
}

enum WoundedDateOption: String, CaseIterable, Identifiable {
    case today = "Today"
    case thisWeek = "This Week"
    case lastWeek = "Last Week"
    case lastMonth = "Last Month"
    case lastThreeMonths = "Last 3 Months"

    var id: String { rawValue }
}

struct PatientProfile: Equatable {
    var name: String = ""
    var mrnOrPID: String = ""
    var height: String = ""
    var weight: String = ""
    var gender: PatientGender = .other
    var age: String = ""

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New Patient" : trimmed
    }
}

struct WoundIntakeData: Equatable {
    var laterality: Laterality = .right
    var bodyArea: BodyArea = .lowerLimbs
    var contexts: Set<WoundContext> = []
    var dateWounded: WoundedDateOption = .today
    var notes: String = ""
    var prescriptionAttachmentName: String = ""
    var medicineEntries: [String] = []
}

struct CatalogedWoundPhoto: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let fileName: String
    var note: String
    var bodyArea: String?
    var laterality: String?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        fileName: String,
        note: String = "",
        bodyArea: String? = nil,
        laterality: String? = nil
    ) {
        self.id = id
        self.date = date
        self.fileName = fileName
        self.note = note
        self.bodyArea = bodyArea
        self.laterality = laterality
    }

    var displayTitle: String {
        let side = laterality.map { "\($0) " } ?? ""
        if let bodyArea, !bodyArea.isEmpty {
            return "\(side)\(bodyArea)"
        }
        return "Wound photo"
    }
}

@MainActor
final class WoundPhotoCatalogManager: ObservableObject {
    @AppStorage("catalogedWoundPhotos") private var storedJSON: String = ""

    @Published private(set) var items: [CatalogedWoundPhoto] = [] {
        didSet { persist() }
    }

    private let fileManager = FileManager.default

    init() {
        load()
        try? prepareDirectory()
    }

    func add(
        image: UIImage,
        bodyArea: BodyArea? = nil,
        laterality: Laterality? = nil,
        note: String = ""
    ) throws {
        try prepareDirectory()
        let id = UUID()
        let fileName = "\(id.uuidString).jpg"
        let url = Self.photosDirectory.appendingPathComponent(fileName)
        guard let data = image.scaled(maxDimension: 1600).jpegData(compressionQuality: 0.84) else {
            throw PhotoCatalogError.encodingFailed
        }
        try data.write(to: url, options: [.atomic])

        let photo = CatalogedWoundPhoto(
            id: id,
            fileName: fileName,
            note: note,
            bodyArea: bodyArea?.rawValue,
            laterality: laterality?.rawValue
        )
        items.insert(photo, at: 0)
    }

    func delete(_ photo: CatalogedWoundPhoto) {
        let url = imageURL(for: photo)
        try? fileManager.removeItem(at: url)
        items.removeAll { $0.id == photo.id }
    }

    func imageURL(for photo: CatalogedWoundPhoto) -> URL {
        Self.photosDirectory.appendingPathComponent(photo.fileName)
    }

    func shareText(for photo: CatalogedWoundPhoto) -> String {
        var lines = [
            "WoundCorder photo",
            "Captured: \(photo.date.formatted(date: .abbreviated, time: .shortened))",
            "Location: \(photo.displayTitle)"
        ]
        if !photo.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Note: \(photo.note)")
        }
        lines.append("Shared by explicit user action.")
        return lines.joined(separator: "\n")
    }

    private static var photosDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WoundCorder", isDirectory: true)
            .appendingPathComponent("PhotoCatalog", isDirectory: true)
    }

    private func prepareDirectory() throws {
        try fileManager.createDirectory(at: Self.photosDirectory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = Self.photosDirectory
        try? directory.setResourceValues(values)
    }

    private func load() {
        guard !storedJSON.isEmpty, let data = storedJSON.data(using: .utf8) else {
            items = []
            return
        }
        items = (try? JSONDecoder().decode([CatalogedWoundPhoto].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        storedJSON = String(data: data, encoding: .utf8) ?? ""
    }
}

enum PhotoCatalogError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "The photo could not be prepared for the catalog."
        }
    }
}

enum WoundSeverityScorer {
    static func score(area: Float, volume: Float) -> Int {
        let areaComponent = min(10, max(0, Int((area / 4.0).rounded(.up))))
        let volumeComponent = min(10, max(0, Int((volume / 2.5).rounded(.up))))
        return min(20, max(1, areaComponent + volumeComponent))
    }

    static func depthCM(area: Float, volume: Float) -> Float {
        guard area > 0, volume > 0 else { return 0 }
        return volume / area
    }
}

@MainActor
final class VoiceNoteRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate, @unchecked Sendable {
    @Published var isRecording = false
    @Published var statusText = "No voice note"

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var startedAt: Date?

    func toggleRecording() {
        isRecording ? stopRecording() : requestAndStartRecording()
    }

    private func requestAndStartRecording() {
        let handlePermission: @Sendable (Bool) -> Void = { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                if granted {
                    self.startRecording()
                } else {
                    self.statusText = "Microphone permission needed"
                }
            }
        }

        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: handlePermission)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(handlePermission)
        }
    }

    private func startRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("wound-note-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 12_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]

            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.delegate = self
            recorder?.record()

            startedAt = Date()
            isRecording = true
            statusText = "Recording 0:00"
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } catch {
            statusText = "Voice note failed"
        }
    }

    private func tick() {
        guard let startedAt else { return }
        let elapsed = Int(Date().timeIntervalSince(startedAt))
        statusText = String(format: "Recording %d:%02d", elapsed / 60, elapsed % 60)
    }

    private func stopRecording() {
        recorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false

        if let startedAt {
            let elapsed = Int(Date().timeIntervalSince(startedAt))
            statusText = String(format: "Voice note %d:%02d", elapsed / 60, elapsed % 60)
        } else {
            statusText = "Voice note saved"
        }
        startedAt = nil
    }
}
