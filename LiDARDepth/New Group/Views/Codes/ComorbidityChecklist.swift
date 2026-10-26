import Foundation

/// A tri-state value used for checklist entries.
public enum Ternary: String, CaseIterable, Identifiable, Codable, Sendable, Equatable {
    /// The state is unknown or not specified.
    case unknown
    /// The state is positive or affirmed.
    case yes
    /// The state is negative or denied.
    case no
    
    /// The unique identifier of the enum case.
    public var id: String { rawValue }
}

/// Checklist of comorbidities to optionally send along with a wound analysis.
public struct ComorbidityChecklist: Codable, Sendable, Equatable {
    /// Presence of diabetes mellitus.
    public var diabetes_mellitus: Ternary = .unknown
    /// Presence of peripheral arterial disease (PAD).
    public var peripheral_vascular_or_arterial_disease: Ternary = .unknown
    /// Presence of peripheral neuropathy.
    public var peripheral_neuropathy: Ternary = .unknown
    /// Presence of heart failure or cardiovascular disease.
    public var congestive_heart_failure: Ternary = .unknown
    /// Current or former tobacco use.
    public var tobacco_use_current_or_former: Ternary = .unknown
    /// Immunosuppression, steroid use, or active cancer therapy.
    public var weak_immune_system_or_chronic_steroids: Ternary = .unknown
    /// History of similar ulcers.
    public var history_of_similar_ulcers: Ternary = .unknown

    public var stroke_or_paralysis: Ternary = .unknown
    public var surgery_at_wound_site: Ternary = .unknown
    public var other_immune_weakening_medicines: Ternary = .unknown
    public var DVT_or_VTE: Ternary = .unknown
    public var obesity: Ternary = .unknown
    public var incontinence: Ternary = .unknown

    public init() {}

    /// Returns a plain dictionary representation suitable for JSON payloads.
    ///
    /// - Returns: A dictionary mapping property names to their string raw values.
    public func asDictionary() -> [String: String] {
        [
            "stroke_or_paralysis": stroke_or_paralysis.rawValue,
            "surgery_at_wound_site": surgery_at_wound_site.rawValue,
            "other_immune_weakening_medicines": other_immune_weakening_medicines.rawValue,
            "DVT_or_VTE": DVT_or_VTE.rawValue,
            "obesity": obesity.rawValue,
            "incontinence": incontinence.rawValue,
            "diabetes_mellitus": diabetes_mellitus.rawValue,
            "peripheral_vascular_or_arterial_disease": peripheral_vascular_or_arterial_disease.rawValue,
            "peripheral_neuropathy": peripheral_neuropathy.rawValue,
            "congestive_heart_failure": congestive_heart_failure.rawValue,
            "tobacco_use_current_or_former": tobacco_use_current_or_former.rawValue,
            "weak_immune_system_or_chronic_steroids": weak_immune_system_or_chronic_steroids.rawValue,
            "history_of_similar_ulcers": history_of_similar_ulcers.rawValue
        ]
    }

    /// Encodes the checklist as JSON data.
    ///
    /// - Parameter pretty: If true, produces pretty-printed JSON. Defaults to false.
    /// - Throws: An error if encoding fails.
    /// - Returns: The JSON data representing the checklist.
    public func jsonData(pretty: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        if pretty { encoder.outputFormatting.insert(.prettyPrinted) }
        return try encoder.encode(self)
    }
}
