import Foundation

@main struct WoundRecordFileTests {
    struct Record: Codable, Equatable { let id: Int; let name: String }
    static func check(_ value: @autoclosure () throws -> Bool) rethrows { let valid = try value(); precondition(valid) }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "WoundRecordTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        func store(_ name: String) -> WoundRecordFile<Record> { WoundRecordFile(name: name, legacyKey: name, defaults: defaults, directory: root) }
        let original = [Record(id: 1, name: "Legacy fixture")]
        defaults.set(String(decoding: try JSONEncoder().encode(original), as: UTF8.self), forKey: "valid")
        let migrated = store("valid")
        try check(migrated.load() == original)
        precondition(defaults.object(forKey: "valid") == nil)
        precondition(FileManager.default.fileExists(atPath: migrated.url.appendingPathExtension("legacy").path))
        let second = store("valid"); try check(second.load() == original)
        try migrated.commit(original + [Record(id: 2, name: "New fixture")])
        do { try second.commit([]); preconditionFailure("Stale writer accepted") } catch {}
        let damaged = Data("not-json".utf8)
        try damaged.write(to: migrated.url)
        do { _ = try migrated.load(); preconditionFailure("Corruption accepted") } catch {}
        do { try migrated.commit([]); preconditionFailure("Corruption overwritten") } catch {}
        try check(Data(contentsOf: migrated.url) == damaged)
        try check(migrated.restorePrevious() == original)
        try check(store("valid").load() == original)
        defaults.set("broken legacy JSON", forKey: "broken")
        let broken = store("broken")
        do { _ = try broken.load(); preconditionFailure("Bad migration accepted") } catch {}
        precondition(defaults.string(forKey: "broken") == "broken legacy JSON")
        precondition(!FileManager.default.fileExists(atPath: broken.url.path))
        let empty = store("empty"); try check(empty.load().isEmpty)
        try empty.commit(original); try check(store("empty").load() == original)
        print("PASS: protected-record migration, corruption preservation, explicit recovery, stale writer rejection, and independent indexes")
    }
}
