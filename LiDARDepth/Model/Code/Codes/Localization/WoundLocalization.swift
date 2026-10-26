import Foundation

enum WoundLanguage: String, CaseIterable, Identifiable {
    case english = "en", spanish = "es", french = "fr"
    var id: String { rawValue }
    var nativeName: String {
        switch self { case .english: return "English"; case .spanish: return "Español"; case .french: return "Français" }
    }
    var locale: Locale { Locale(identifier: rawValue) }
    static var current: Self { Self(rawValue: UserDefaults.standard.string(forKey: "woundLanguage") ?? "en") ?? .english }
    var responseInstruction: String {
        switch self {
        case .english: return "Write all human-readable JSON values in English."
        case .spanish: return "Write all human-readable JSON values in Spanish."
        case .french: return "Write all human-readable JSON values in French."
        }
    }
}

/// Translates presentation text only. Persisted identifiers, model labels, and user input stay intact.
/// Dynamic status messages use anchored templates, never word-by-word substitutions.
enum WoundL10n {
    struct Catalog: Decodable { let es: [String: String]; let fr: [String: String] }
    static let catalog: Catalog = {
        guard let url = Bundle.main.url(forResource: "wound-localization", withExtension: "json"),
              let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Catalog.self, from: data)
        else { return Catalog(es: [:], fr: [:]) }
        return value
    }()
    struct Template {
        let key: String
        let regex: NSRegularExpression
    }
    static let templates: [Template] = catalog.es.keys.filter { $0.contains("%@") }.sorted { $0.count > $1.count }.compactMap { key in
        let pattern = "^" + key.components(separatedBy: "%@").map(NSRegularExpression.escapedPattern(for:)).joined(separator: "([^\\n]*?)") + "$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return Template(key: key, regex: regex)
    }
    static func text(_ source: String, language: WoundLanguage = .current) -> String {
        guard language != .english, !source.isEmpty else { return source }
        let table = language == .spanish ? catalog.es : catalog.fr
        if let result = table[source] { return result }
        for template in templates {
            guard let translated = table[template.key],
                  let match = template.regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) else { continue }
            let pieces = translated.components(separatedBy: "%@")
            guard pieces.count == match.numberOfRanges else { continue }
            var result = pieces[0]
            for index in 1..<match.numberOfRanges {
                guard let range = Range(match.range(at: index), in: source) else { return source }
                let argument = String(source[range])
                // Only known app-owned values in status/measurement templates are translated.
                // Names, notes, identifiers and user-authored titles are deliberately verbatim.
                let protectsInput = ["to %@", "Save to %@", "This measurement was saved to %@'s record.", "ID: %@", "MRN / ID %@", "Remove %@", "Patient: %@", "Notes: %@", "Note: %@", "Medicines: %@"].contains(template.key)
                result += (protectsInput ? argument : table[argument] ?? argument) + pieces[index]
            }
            return result
        }
        for separator in ["\n", " • ", " · "] where source.contains(separator) {
            return source.components(separatedBy: separator).map { text($0, language: language) }.joined(separator: separator)
        }
        return source
    }
}

// Allows the same explicit numeric formatting in translated and English measurement labels.
extension String.StringInterpolation {
    mutating func appendInterpolation<T: CVarArg>(_ value: T, specifier: String) {
        appendLiteral(String(format: specifier, locale: WoundLanguage.current.locale, value))
    }
}

extension Date {
    func woundFormatted(date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> String {
        formatted(Date.FormatStyle(date: date, time: time).locale(WoundLanguage.current.locale))
    }
}
