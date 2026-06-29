import AVFoundation
import Foundation
import SwiftUI

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
