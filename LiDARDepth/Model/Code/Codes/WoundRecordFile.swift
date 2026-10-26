import Foundation

/// Main-thread owned by each store. Commits are atomic and reject stale writers.
final class WoundRecordFile<Record: Codable> {
    private struct Envelope: Codable { let version: Int; let records: [Record] }
    enum Failure: LocalizedError {
        case unreadable, notLoaded, changedElsewhere, unsupportedVersion
        var errorDescription: String? {
            switch self {
            case .unreadable: return "These records could not be read. They have been kept unchanged. Unlock the device and try again, or restore the last saved copy."
            case .notLoaded: return "Records must be loaded before changes can be saved. Your existing records have been kept."
            case .changedElsewhere: return "These records changed in another screen. Reload them before saving again."
            case .unsupportedVersion: return "These records were saved by a newer version of WoundCorder. Update the app to open them."
            }
        }
    }
    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WoundCorderRecords", isDirectory: true)
    }
    let url: URL
    private let defaults: UserDefaults
    private let legacyKey: String
    private var loaded = false
    private var expectedData: Data?
    private var backupURL: URL { url.appendingPathExtension("previous") }
    var hasBackup: Bool { FileManager.default.fileExists(atPath: backupURL.path) }

    init(name: String, legacyKey: String, defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.url = (directory ?? Self.defaultDirectory).appendingPathComponent(name + ".json")
        self.legacyKey = legacyKey
        self.defaults = defaults
    }
    func load() throws -> [Record] {
        loaded = false
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            let records = try decode(data)
            expectedData = data; loaded = true
            if let legacy = defaults.string(forKey: legacyKey)?.data(using: .utf8),
               let archived = try? Data(contentsOf: url.appendingPathExtension("legacy")), legacy == archived {
                defaults.removeObject(forKey: legacyKey)
            }
            return records
        }
        if let legacy = defaults.string(forKey: legacyKey), !legacy.isEmpty {
            guard let data = legacy.data(using: .utf8), let records = try? JSONDecoder().decode([Record].self, from: data) else {
                throw Failure.unreadable // Never replace, delete, or "repair" an unreadable legacy value.
            }
            try prepareDirectory()
            try protectedWrite(data, to: url.appendingPathExtension("legacy"))
            let encoded = try JSONEncoder().encode(Envelope(version: 1, records: records))
            try protectedWrite(encoded, to: url)
            let verified = try Data(contentsOf: url)
            _ = try decode(verified)
            guard verified == encoded else { throw Failure.unreadable }
            try protectedWrite(verified, to: backupURL)
            expectedData = verified; loaded = true
            defaults.removeObject(forKey: legacyKey) // Only after a durable, readable replacement.
            return records
        }
        expectedData = nil; loaded = true
        return []
    }
    func commit(_ records: [Record]) throws {
        guard loaded else { throw Failure.notLoaded }
        let current = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        guard current == expectedData else { throw Failure.changedElsewhere }
        let data = try JSONEncoder().encode(Envelope(version: 1, records: records))
        try prepareDirectory()
        try protectedWrite(current ?? data, to: backupURL)
        try protectedWrite(data, to: url)
        expectedData = data
    }
    /// Explicit recovery preserves the unreadable/current file for later investigation.
    func restorePrevious() throws -> [Record] {
        let data = try Data(contentsOf: backupURL)
        let records = try decode(data)
        try prepareDirectory()
        if FileManager.default.fileExists(atPath: url.path) {
            try protectedWrite(Data(contentsOf: url), to: url.appendingPathExtension("recovery-" + UUID().uuidString))
        }
        try protectedWrite(data, to: url)
        expectedData = data; loaded = true
        return records
    }
    private func decode(_ data: Data) throws -> [Record] {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { throw Failure.unreadable }
        guard envelope.version == 1 else { throw Failure.unsupportedVersion }
        return envelope.records
    }
    private func prepareDirectory() throws {
        var directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }
    private func protectedWrite(_ data: Data, to target: URL) throws {
        #if os(iOS)
        try data.write(to: target, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: target, options: [.atomic])
        #endif
    }
}
