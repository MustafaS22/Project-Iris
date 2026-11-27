import XCTest
@testable import IrisCore

final class AutomaticPermissionTests: XCTestCase {
    func testRoutineActionsStartWithoutAdditionalPermissions() {
        for type in ["openApplication", "openURL", "searchWeb", "findFiles", "readFile", "playSpotifyPlaylist", "drawOnScreen"] {
            XCTAssertTrue(ActionPolicy.mayRunAutomatically(.init(type: type), enabled: false), type)
        }
        for type in ["writeFile", "createDocument", "runProject", "generateImage", "computerTask"] {
            XCTAssertFalse(ActionPolicy.mayRunAutomatically(.init(type: type), enabled: false), type)
        }
    }
    func testAlwaysAllowCoversSupportedComputerActions() {
        for type in ActionPolicy.types.subtracting(["generateImage", "computerTask"]) { XCTAssertTrue(ActionPolicy.mayRunAutomatically(.init(type: type), enabled: true), type) }
    }
    func testPaidAndUnknownActionsStillNeedReview() {
        XCTAssertFalse(ActionPolicy.mayRunAutomatically(.init(type: "generateImage"), enabled: true))
        XCTAssertFalse(ActionPolicy.mayRunAutomatically(.init(type: "shell"), enabled: true))
        XCTAssertFalse(ActionPolicy.mayRunAutomatically(.init(type: "deleteFile"), enabled: true))
    }
    func testAdditionalPermissionsChoicePersists() throws {
        var preferences = Preferences()
        let old = try JSONEncoder().encode(preferences)
        XCTAssertNil(try JSONDecoder().decode(Preferences.self, from: old).alwaysAllowComputerActions)
        preferences.alwaysAllowComputerActions = true
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences)).alwaysAllowComputerActions, true)
    }
    func testAutomaticDiscoverySkipsEmbeddingModels() throws {
        XCTAssertEqual(try ProviderReadiness.model(requested: "", available: ["", "text-embedding", "reranker", "chat-model"]), "chat-model")
        XCTAssertThrowsError(try ProviderReadiness.model(requested: "", available: []))
    }
    func testConfiguredModelDoesNotRequireCatalogVerification() throws {
        XCTAssertEqual(try ProviderReadiness.model(requested: " my-chat-model ", available: []), "my-chat-model")
    }
}
