import XCTest
@testable import IrisCore
final class IrisLocalStorageTests: XCTestCase {
    func testLegacyAppDataIsReusedWithoutMovingOrDeletingIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let current = root.appendingPathComponent("current"), legacy = root.appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("saved chats".utf8).write(to: legacy.appendingPathComponent("state.json"))
        XCTAssertEqual(IrisLocalStorage.preferredDirectory(current: current, legacy: legacy), legacy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("state.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: current.path))
    }
    func testCurrentStoreIsPreservedWhenBothExist() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let current = root.appendingPathComponent("current"), legacy = root.appendingPathComponent("legacy")
        for dir in [legacy, current] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); try Data("{}".utf8).write(to: dir.appendingPathComponent("state.json")) }
        XCTAssertEqual(IrisLocalStorage.preferredDirectory(current: current, legacy: legacy), current)
    }
    func testPreferenceUpgradeKeepsNewChoicesAndRestoresFolderGrants() {
        let result = IrisLocalStorage.mergingPreferences(current: ["theme":"ocean", "new":true], legacy: ["theme":"sage", "IrisGrantedFolders":Data([1,2,3])])
        XCTAssertEqual(result["theme"] as? String,"ocean")
        XCTAssertEqual(result["IrisGrantedFolders"] as? Data,Data([1,2,3]))
        XCTAssertEqual(result["new"] as? Bool,true)
    }
    func testRestoredStoreOverridesAnOlderOutsideStore() {
        let restored = FileManager.default.temporaryDirectory.appendingPathComponent("Iris-restored-test")
        IrisLocalStorage.restoredSupportDirectory = restored
        defer { IrisLocalStorage.restoredSupportDirectory = nil }
        XCTAssertEqual(IrisLocalStorage.supportDirectory, restored)
    }
    func testDirectDownloadBookmarksRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
        let bookmark = try url.bookmarkData(options: IrisLocalStorage.bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
        var stale = false
        let resolved = try URL(resolvingBookmarkData: bookmark, options: IrisLocalStorage.resolutionOptions, relativeTo: nil, bookmarkDataIsStale: &stale)
        XCTAssertEqual(resolved.resolvingSymlinksInPath().standardizedFileURL,url.resolvingSymlinksInPath().standardizedFileURL)
        XCTAssertFalse(stale)
    }
}
