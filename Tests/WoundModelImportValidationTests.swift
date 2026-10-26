import Foundation

@main struct WoundModelImportValidationTests {
    static func main() throws {
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: folder) }
        func rejects() -> Bool { (try? WoundModelImportValidation.inspect(folder)) == nil }
        precondition(rejects())
        let weights = folder.appendingPathComponent("model.gguf")
        let vision = folder.appendingPathComponent("mmproj-test.gguf")
        let fixture = Data("GGUF".utf8) + Data(repeating: 0, count: 28)
        try fixture.write(to: weights)
        precondition(rejects(), "A text model without a vision projector cannot be added")
        try fixture.write(to: vision)
        let gguf = try WoundModelImportValidation.inspect(folder)
        precondition(gguf.gguf && gguf.modelFile == "model.gguf" && gguf.visionFile == "mmproj-test.gguf")
        try Data("not a GGUF".utf8).write(to: vision)
        precondition(rejects())
        try manager.removeItem(at: vision)
        try manager.createSymbolicLink(at: vision, withDestinationURL: weights)
        precondition(rejects())
        try manager.removeItem(at: vision)
        try manager.removeItem(at: weights)
        for name in ["config.json", "llm.mnn", "llm_config.json", "tokenizer.txt", "visual.mnn"] {
            try Data("{}".utf8).write(to: folder.appendingPathComponent(name))
        }
        precondition(tryInspectMNN(folder))
        try Data(#"{"llm_model":"../outside.mnn"}"#.utf8).write(to: folder.appendingPathComponent("config.json"))
        precondition(rejects(), "MNN configuration must not reach outside its import folder")
        print("PASS: GGUF pair selection, missing projector, invalid header, symbolic links, MNN completeness and external paths")
    }
    static func tryInspectMNN(_ folder: URL) -> Bool {
        (try? WoundModelImportValidation.inspect(folder).gguf) == false
    }
}
