import Foundation

enum WoundModelImportValidation {
    struct Plan {
        let gguf: Bool
        let modelFile: String?
        let visionFile: String?
        let files: [URL]
        let bytes: Int64
    }
    enum Failure: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            switch self { case .invalid(let message): return message }
        }
    }
    static func inspect(_ folder: URL) throws -> Plan {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]
        let root = try folder.resourceValues(forKeys: keys)
        guard root.isDirectory == true, root.isSymbolicLink != true else {
            throw Failure.invalid("Choose a model folder, not an individual file or shortcut.")
        }
        let files = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [])
        var usable: [URL] = []
        var bytes: Int64 = 0
        for file in files {
            let values = try file.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true else { throw Failure.invalid("Model folders cannot contain symbolic links.") }
            if file.lastPathComponent.hasPrefix(".") { continue }
            guard values.isRegularFile == true else { throw Failure.invalid("Place the model files directly in one folder, without subfolders.") }
            let size = Int64(values.fileSize ?? 0)
            guard size > 0, size <= 16_000_000_000, bytes <= 16_000_000_000 - size else {
                throw Failure.invalid("The model files are empty or exceed the 16 GB import limit.")
            }
            bytes += size
            usable.append(file)
        }
        let ggufs = usable.filter { $0.pathExtension.lowercased() == "gguf" }
        if !ggufs.isEmpty {
            let vision = ggufs.filter { $0.lastPathComponent.lowercased().hasPrefix("mmproj") }
            let models = ggufs.filter { !$0.lastPathComponent.lowercased().hasPrefix("mmproj") }
            guard vision.count == 1, models.count == 1 else {
                throw Failure.invalid("Include exactly one GGUF model and its matching mmproj GGUF vision file. Split models are not supported.")
            }
            for file in ggufs {
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                guard try handle.read(upToCount: 4) == Data("GGUF".utf8),
                      (try file.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0 > 24 else {
                    throw Failure.invalid("A selected GGUF file has an invalid header.")
                }
            }
            return Plan(gguf: true, modelFile: models[0].lastPathComponent, visionFile: vision[0].lastPathComponent, files: ggufs, bytes: bytes)
        }
        let names = Set(usable.map(\.lastPathComponent))
        guard Set(["config.json", "llm.mnn", "llm_config.json", "tokenizer.txt", "visual.mnn"]).isSubset(of: names) else {
            throw Failure.invalid("Choose a complete MNN vision model folder, or a GGUF model with a matching mmproj file.")
        }
        func safe(_ value: Any) -> Bool {
            if let text = value as? String {
                return !text.hasPrefix("/") && !text.hasPrefix("~") && !text.contains("..") && !text.contains("://")
            }
            if let array = value as? [Any] { return array.allSatisfy(safe) }
            if let object = value as? [String: Any] { return object.values.allSatisfy(safe) }
            return true
        }
        for file in usable where file.pathExtension.lowercased() == "json" {
            guard (try file.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0 < 10_000_000 else {
                throw Failure.invalid("Model configuration is too large.")
            }
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
            guard safe(json) else { throw Failure.invalid("Model configuration must use local relative paths without parent-directory references.") }
        }
        return Plan(gguf: false, modelFile: nil, visionFile: nil, files: usable, bytes: bytes)
    }
}
