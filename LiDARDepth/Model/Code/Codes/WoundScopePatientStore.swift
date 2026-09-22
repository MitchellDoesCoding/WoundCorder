import Foundation
import SwiftUI

/// Lightweight persisted patient identity used by the redesigned navigation flow.
/// Measurement records remain owned by the existing measurement pipeline.
struct WoundScopePatient: Identifiable, Codable, Equatable, Hashable {
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
        get { PatientGender(rawValue: genderRawValue) ?? .other }
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
final class WoundScopePatientStore: ObservableObject {
    static let storageKey = "woundScopePatients.v1"

    @AppStorage private var storedPatientsJSON: String
    @Published private(set) var patients: [WoundScopePatient] = [] {
        didSet { persist() }
    }

    /// Compatibility with collection-oriented call sites.
    var items: [WoundScopePatient] { patients }

    init(defaults: UserDefaults = .standard) {
        _storedPatientsJSON = AppStorage(
            wrappedValue: "",
            Self.storageKey,
            store: defaults
        )
        restore()
    }

    @discardableResult
    func add(from profile: PatientProfile) -> WoundScopePatient {
        let patient = WoundScopePatient(profile: profile)
        patients.insert(patient, at: 0)
        return patient
    }

    @discardableResult
    func update(id: UUID, from profile: PatientProfile) -> WoundScopePatient? {
        guard let index = patients.firstIndex(where: { $0.id == id }) else { return nil }
        patients[index].apply(profile)
        return patients[index]
    }

    func delete(_ patient: WoundScopePatient) {
        delete(id: patient.id)
    }

    func delete(id: UUID) {
        patients.removeAll { $0.id == id }
    }

    /// Returns the existing patient with the same normalized name (or MRN), updating its
    /// profile in place. If no match exists a new patient is inserted and returned.
    @discardableResult
    func ensure(from profile: PatientProfile) -> WoundScopePatient {
        let rawName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)

        if !rawName.isEmpty, let existing = patient(named: rawName) {
            return update(id: existing.id, from: profile) ?? existing
        }

        let normalizedMRN = Self.normalized(profile.mrnOrPID)
        if !normalizedMRN.isEmpty,
           let existing = patients.first(where: { Self.normalized($0.mrnOrPID) == normalizedMRN }) {
            return update(id: existing.id, from: profile) ?? existing
        }

        return add(from: profile)
    }

    /// Performs an exact, whitespace-trimmed, case- and diacritic-insensitive name lookup.
    func patient(named name: String) -> WoundScopePatient? {
        let target = Self.normalized(name)
        guard !target.isEmpty else { return nil }
        return patients.first { Self.normalized($0.name) == target }
    }

    func removeAll() {
        patients.removeAll()
    }

    private func restore() {
        guard !storedPatientsJSON.isEmpty,
              let data = storedPatientsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([WoundScopePatient].self, from: data)
        else { return }

        patients = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(patients),
              let json = String(data: data, encoding: .utf8)
        else { return }
        storedPatientsJSON = json
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
