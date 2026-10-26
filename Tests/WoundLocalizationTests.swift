import Foundation

@main
struct WoundLocalizationTests {
    static func main() throws {
        let catalog = WoundL10n.catalog
        precondition(catalog.es.count > 1000, "Bundled translations must be available")
        precondition(Set(catalog.es.keys) == Set(catalog.fr.keys))
        for (language, table) in [(WoundLanguage.spanish, catalog.es), (.french, catalog.fr)] {
            for (key, value) in table {
                precondition(!value.isEmpty)
                precondition(key.components(separatedBy: "%@").count == value.components(separatedBy: "%@").count, key)
                precondition(WoundL10n.text(key, language: language) == value)
            }
            // Template values, medical units and personal names must survive translation.
            let measured = WoundL10n.text("Area 12.50 cm² · Volume 3.20 cm³", language: language)
            precondition(measured.contains("12.50 cm²") && measured.contains("3.20 cm³"))
            precondition(!measured.contains("Area "))
            let status = WoundL10n.text("Seen 100% · verified 65% / 60%. Make a small side-to-side sweep; keep the wound centered.", language: language)
            precondition(status.contains("100") && status.contains("65") && status.contains("60") && !status.contains("verified"))
            let name = WoundL10n.text("This measurement was saved to Patient's record.", language: language)
            precondition(name.contains("Patient"), "Never translate personal names in a template")
            precondition(WoundL10n.text("Notes: Left", language: language).hasSuffix("Left"))
            let multiline = WoundL10n.text("Attached LiDAR measurements (estimates):\nArea: 12.50 cm²\nA zero volume does not establish that a wound has no depth.", language: language)
            precondition(!multiline.contains("Attached") && !multiline.contains("zero volume"))
            precondition(WoundL10n.text("R Lower Leg", language: language) != "R Lower Leg")
        }
        precondition(WoundL10n.text("Area 12.50 cm²", language: .english) == "Area 12.50 cm²")
        precondition(WoundL10n.text("My own note 123", language: .french) == "My own note 123")
        print("PASS: \(catalog.es.count) translations per language, placeholder parity, dynamic LiDAR messages, units, names, multiline education and English fallback")
    }
}
