import Foundation
import Security

/// Direct-download builds retain Iris's own legacy data; no user documents are migrated or scanned.
enum IrisLocalStorage {
    static var restoredSupportDirectory: URL?
    static var isSandboxed: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil }
        return (SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil) as? Bool) == true
    }
    static var bookmarkOptions: URL.BookmarkCreationOptions { isSandboxed ? .withSecurityScope : .minimalBookmark }
    static var resolutionOptions: URL.BookmarkResolutionOptions { isSandboxed ? [.withSecurityScope, .withoutUI] : .withoutUI }
    static var supportDirectory: URL {
        if let restoredSupportDirectory { return restoredSupportDirectory }
        let current = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Project IRIS")
        guard !isSandboxed, let bundle = Bundle.main.bundleIdentifier else { return current }
        let legacy = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Containers/\(bundle)/Data/Library/Application Support/Project IRIS")
        return preferredDirectory(current: current, legacy: legacy)
    }
    static func preferredDirectory(current: URL, legacy: URL) -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: current.appendingPathComponent("state.json").path) { return current }
        if fm.fileExists(atPath: legacy.appendingPathComponent("state.json").path) { return legacy }
        return current
    }
    static func restoreLegacyPreferences() {
        guard !isSandboxed, !ProcessInfo.processInfo.arguments.contains("--iris-validation"), let bundle = Bundle.main.bundleIdentifier else { return }
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Containers/\(bundle)/Data/Library/Preferences/\(bundle).plist")
        guard let data = try? Data(contentsOf: url), let legacy = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return }
        let defaults = UserDefaults.standard
        let current = defaults.persistentDomain(forName: bundle) ?? [:]
        defaults.setPersistentDomain(mergingPreferences(current: current, legacy: legacy), forName: bundle)
    }
    static func mergingPreferences(current: [String: Any], legacy: [String: Any]) -> [String: Any] {
        // Current preferences win; this never replaces newer choices or deletes the old store.
        legacy.merging(current) { _, current in current }
    }
}
