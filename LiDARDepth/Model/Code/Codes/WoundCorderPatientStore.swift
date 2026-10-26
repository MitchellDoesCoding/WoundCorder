import Foundation
import SwiftUI

/// Lightweight persisted patient identity used by the redesigned navigation flow.
/// Measurement records remain owned by the existing measurement pipeline.
struct WoundCorderPatient: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var mrnOrPID: String
    var height: String
    var weight: String
    var genderRawValue: String
    var age: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        profile: PatientProfile,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = Self.cleanName(profile.name)
        self.mrnOrPID = Self.clean(profile.mrnOrPID)
        self.height = Self.clean(profile.height)
        self.weight = Self.clean(profile.weight)
        self.genderRawValue = profile.gender.rawValue
        self.age = Self.clean(profile.age)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayName: String {
        let cleaned = Self.clean(name)
        return cleaned.isEmpty ? "New Patient" : cleaned
    }

    var initials: String {
        let components = displayName
            .split(whereSeparator: { $0.isWhitespace })
            .filter { !$0.isEmpty }

        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        if let first = components.first {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }

    var gender: PatientGender {
        get { PatientGender(rawValue: genderRawValue) ?? .unknown }
        set { genderRawValue = newValue.rawValue }
    }

    var profile: PatientProfile {
        PatientProfile(
            name: displayName,
            mrnOrPID: mrnOrPID,
            height: height,
            weight: weight,
            gender: gender,
            age: age
        )
    }

    mutating func apply(_ profile: PatientProfile, now: Date = Date()) {
        name = Self.cleanName(profile.name)
        mrnOrPID = Self.clean(profile.mrnOrPID)
        height = Self.clean(profile.height)
        weight = Self.clean(profile.weight)
        genderRawValue = profile.gender.rawValue
        age = Self.clean(profile.age)
        updatedAt = now
    }

    private static func cleanName(_ value: String) -> String {
        let cleaned = clean(value)
        return cleaned.isEmpty ? "New Patient" : cleaned
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class WoundCorderPatientStore: ObservableObject {
    static let storageKey = "woundScopePatients.v1"

    @Published private(set) var patients: [WoundCorderPatient] = []
    @Published private(set) var storageError: String?
    private let records: WoundRecordFile<WoundCorderPatient>
    var canRestorePrevious: Bool { records.hasBackup }
    var items: [WoundCorderPatient] { patients }

    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        records = WoundRecordFile(name: "patients", legacyKey: Self.storageKey, defaults: defaults, directory: directory)
        reload()
    }
    func reload() {
        do { patients = try records.load(); storageError = nil }
        catch { storageError = error.localizedDescription }
    }
    func restorePrevious() {
        do { patients = try records.restorePrevious(); storageError = nil }
        catch { storageError = error.localizedDescription }
    }
    @discardableResult private func commit(_ updated: [WoundCorderPatient]) -> Bool {
        do { try records.commit(updated); patients = updated; storageError = nil; return true }
        catch { storageError = error.localizedDescription; return false }
    }
    @discardableResult
    func add(from profile: PatientProfile) -> WoundCorderPatient? {
        guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, profile.validationMessage == nil else {
            storageError = profile.validationMessage ?? "Enter a name before saving."; return nil
        }
        let patient = WoundCorderPatient(profile: profile)
        return commit([patient] + patients) ? patient : nil
    }
    @discardableResult
    func update(id: UUID, from profile: PatientProfile) -> WoundCorderPatient? {
        guard let index = patients.firstIndex(where: { $0.id == id }) else { return nil }
        guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, profile.validationMessage == nil else {
            storageError = profile.validationMessage ?? "Enter a name before saving."; return nil
        }
        var updated = patients; updated[index].apply(profile)
        return commit(updated) ? updated[index] : nil
    }
    func delete(_ patient: WoundCorderPatient) { delete(id: patient.id) }
    func delete(id: UUID) { commit(patients.filter { $0.id != id }) }

    /// Only an explicit record identifier can merge identities. Names are not unique.
    @discardableResult
    func ensure(from profile: PatientProfile) -> WoundCorderPatient? {
        let normalizedMRN = Self.normalized(profile.mrnOrPID)
        if !normalizedMRN.isEmpty,
           let existing = patients.first(where: { Self.normalized($0.mrnOrPID) == normalizedMRN }) {
            return update(id: existing.id, from: profile)
        }
        return add(from: profile)
    }

    /// Performs an exact, whitespace-trimmed, case- and diacritic-insensitive name lookup.
    func patient(named name: String) -> WoundCorderPatient? {
        let target = Self.normalized(name)
        guard !target.isEmpty else { return nil }
        return patients.first { Self.normalized($0.name) == target }
    }

    func removeAll() { commit([]) }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
