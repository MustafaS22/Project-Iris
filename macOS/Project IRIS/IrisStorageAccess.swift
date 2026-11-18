import AppKit

/// A one-time user-mediated grant for Iris's own former container, never a general disk scan.
@MainActor enum IrisStorageAccess {
    private static let key = "Iris.directStorageLibrary.v1"
    private static var heldLibrary: URL?
    static func prepare() -> Bool {
        guard !IrisLocalStorage.isSandboxed, let bundle = Bundle.main.bundleIdentifier else { return true }
        let library = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Containers/\(bundle)/Data/Library", isDirectory: true)
        let state = library.appendingPathComponent("Application Support/Project IRIS/state.json")
        guard FileManager.default.fileExists(atPath: state.path) else { return true }
        if let data = UserDefaults.standard.data(forKey: key) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale), !stale, accept(url, expected: library) { return true }
        }
        if accept(library, expected: library) { return true }
        let panel = NSOpenPanel()
        panel.title = "Keep your existing Iris data"
        panel.message = "Iris needs one-time access to its previous Library folder to keep your chats, knowledge and preferences. Your original data will stay in place."
        panel.prompt = "Use existing Iris data"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.directoryURL = library
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url, accept(url, expected: library) else {
            let alert = NSAlert(); alert.messageText = "Your existing Iris data is safe"
            alert.informativeText = "Iris has not replaced or deleted your previous data. Open Iris again and choose its previous Library folder to continue."
            alert.runModal(); return false
        }
        let bookmark = (try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)) ?? (try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil))
        if let bookmark { UserDefaults.standard.set(bookmark, forKey: key) }
        return true
    }
    private static func accept(_ url: URL, expected: URL) -> Bool {
        guard url.standardizedFileURL.resolvingSymlinksInPath() == expected.standardizedFileURL.resolvingSymlinksInPath() else { return false }
        let scoped = url.startAccessingSecurityScopedResource()
        let state = url.appendingPathComponent("Application Support/Project IRIS/state.json")
        guard let data = try? Data(contentsOf: state), (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
            if scoped { url.stopAccessingSecurityScopedResource() }; return false
        }
        heldLibrary = url
        IrisLocalStorage.restoredSupportDirectory = url.appendingPathComponent("Application Support/Project IRIS")
        return true
    }
}
