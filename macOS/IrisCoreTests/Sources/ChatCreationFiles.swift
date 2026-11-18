import Foundation

/// Only files explicitly created through chat live here; this is not general folder access.
enum ChatCreationFiles {
    static let folderID = "iris-generated-library"
    static var root: URL {
        let base = ProcessInfo.processInfo.arguments.contains("--iris-validation") ? FileManager.default.temporaryDirectory.appendingPathComponent("IrisValidation") : IrisLocalStorage.supportDirectory
        return base.appendingPathComponent("Creations", isDirectory: true)
    }
    static func filename(prompt: String, kind: ChatCreationKind) -> String {
        let title = prompt.split { !$0.isLetter && !$0.isNumber }.prefix(6).joined(separator: "-")
        return String((title.isEmpty ? "Iris-" + kind.rawValue : title).prefix(55)) + "-" + UUID().uuidString.prefix(8) + "." + kind.suffix
    }
    static func fileURL(_ path: String) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try ActionPolicy.containedURL(root: root, path: path)
    }
    @MainActor static func save(reply: String, prompt: String, kind: ChatCreationKind) throws -> ChatFileReference {
        let text = CreationPolicy.editableText(reply)
        guard !text.isEmpty else { throw IrisFailure.message("No content was returned. Your existing files were kept.") }
        let bytes: Data
        if kind == .website {
            guard text.range(of: "<html", options: .caseInsensitive) != nil, text.range(of: "</html>", options: .caseInsensitive) != nil else { throw IrisFailure.message("The model didn't return a complete HTML website. Ask it to return a complete single-file website.") }
            bytes = Data(text.utf8)
        } else { bytes = try DocumentWriter.data(content: text, format: kind.suffix) }
        let name = filename(prompt: prompt, kind: kind)
        try bytes.write(to: fileURL(name), options: .atomic)
        return .init(name: name, folderID: folderID, relativePath: name)
    }
}
