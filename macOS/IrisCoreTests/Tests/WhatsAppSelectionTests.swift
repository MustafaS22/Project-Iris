import XCTest
@testable import IrisCore
final class WhatsAppSelectionTests: XCTestCase {
    func testRevocationStillRemovesUnselectedCopiesWhenRefreshFails() async throws {
        try await MainActor.run {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: dir) }
            let name = "IrisWhatsAppTests-" + UUID().uuidString
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            let store = KnowledgeStore(directory: dir)
            try store.ingest([.init(externalID: "a", source: .whatsapp, title: "A", body: "Keep", updatedAt: Date()), .init(externalID: "b", source: .whatsapp, title: "B", body: "Revoke", updatedAt: Date())])
            let service = WhatsAppConnection(store: store, defaults: defaults)
            service.save(["a"])
            XCTAssertEqual(store.documents.map(\.externalID), ["a"])
            XCTAssertEqual(service.selected, ["a"])
            XCTAssertNotNil(service.error) // No folder grant exists, so refresh must fail.
            service.save([])
            XCTAssertTrue(store.documents.isEmpty)
            XCTAssertNil(service.error)
        }
    }
    func testDisconnectRemovesOnlyWhatsAppAndTurnsOffAISharing() async throws {
        try await MainActor.run {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: dir) }
            let name = "IrisWhatsAppTests-" + UUID().uuidString
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            defaults.set(["a"], forKey: "IrisWhatsAppChats")
            let store = KnowledgeStore(directory: dir)
            try store.ingest([.init(externalID: "a", source: .whatsapp, title: "A", body: "Chat", updatedAt: Date()), .init(externalID: "file", source: .files, title: "File", body: "Keep", updatedAt: Date())])
            try store.setSharing(.whatsapp, enabled: true)
            let service = WhatsAppConnection(store: store, defaults: defaults)
            service.disconnect()
            XCTAssertEqual(store.documents.map(\.source), [.files])
            XCTAssertFalse(store.enabled.contains("whatsapp")); XCTAssertTrue(service.selected.isEmpty)
            XCTAssertNil(defaults.object(forKey: "IrisWhatsAppChats"))
        }
    }
}
