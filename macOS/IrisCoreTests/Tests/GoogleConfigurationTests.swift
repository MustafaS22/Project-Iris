import XCTest
@testable import IrisCore

final class GoogleConfigurationTests: XCTestCase {
    func testDesktopRegistrationDecodesWithoutUserTokens() throws {
        let bytes = Data(#"{"installed":{"client_id":"fixture.apps.googleusercontent.com","client_secret":"desktop-registration-value","project_id":"fixture-project","redirect_uris":["http://localhost"]}}"#.utf8)
        let configuration = try GoogleAppConfiguration.decodeDesktop(bytes)
        XCTAssertEqual(configuration.clientID, "fixture.apps.googleusercontent.com")
        XCTAssertEqual(configuration.projectID, "fixture-project")
        XCTAssertEqual(configuration.clientSecret, "desktop-registration-value")
    }
    func testWebClientsAndMalformedRegistrationAreRejected() {
        for raw in [#"{"web":{"client_id":"fixture.apps.googleusercontent.com"}}"#, #"{"installed":{"client_id":"wrong.example"}}"#, "{}"] {
            XCTAssertThrowsError(try GoogleAppConfiguration.decodeDesktop(Data(raw.utf8)))
        }
    }
    func testBundledRegistrationLoadsWithoutImportingKeychainConfiguration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(#"{"CFBundleIdentifier":"test.iris.registration","CFBundlePackageType":"BNDL"}"#.utf8).write(to: directory.appendingPathComponent("Info.plist"))
        try Data(#"{"installed":{"client_id":"bundled.apps.googleusercontent.com","project_id":"bundled-project"}}"#.utf8).write(to: directory.appendingPathComponent("GoogleOAuth.json"))
        let bundle = try XCTUnwrap(Bundle(path: directory.path))
        XCTAssertEqual(try GoogleAppConfiguration.bundled(in: bundle)?.clientID, "bundled.apps.googleusercontent.com")
    }
    func testAccessDeniedExplainsAudienceRecovery() {
        let message = GoogleAuthorizationHelp.message(for: "access_denied")
        XCTAssertTrue(message.contains("Test users"))
        XCTAssertTrue(message.contains("exact account"))
        XCTAssertFalse(message.contains("client_secret"))
    }
    func testDisabledAPIHasSpecificRecoveryWithoutLeakingResponseData() {
        let data = Data(#"{"error":{"message":"private provider details","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"SERVICE_DISABLED"}]}}"#.utf8)
        let message = GoogleImportDiagnostics.explanation(status: 403, data: data, service: "gmail.googleapis.com")
        XCTAssertTrue(message.contains("Gmail API is disabled"))
        XCTAssertTrue(message.contains("Signing in again is not required"))
        XCTAssertTrue(message.contains("SERVICE_DISABLED"))
        XCTAssertFalse(message.contains("private provider details"))
    }
    func testMissingScopeAndQuotaErrorsHaveDifferentRecovery() {
        let scope = Data(#"{"error":{"errors":[{"reason":"insufficientPermissions"}]}}"#.utf8)
        let quota = Data(#"{"error":{"errors":[{"reason":"userRateLimitExceeded"}]}}"#.utf8)
        XCTAssertTrue(GoogleImportDiagnostics.explanation(status: 403, data: scope, service: "drive.googleapis.com").contains("Reconnect"))
        XCTAssertTrue(GoogleImportDiagnostics.explanation(status: 403, data: quota, service: "drive.googleapis.com").contains("quota"))
    }
    func testMalformedErrorDoesNotBreakRecovery() {
        let message = GoogleImportDiagnostics.explanation(status: 401, data: Data("bad".utf8), service: "gmail.googleapis.com")
        XCTAssertTrue(message.contains("expired or was revoked"))
        XCTAssertTrue(message.contains("Existing knowledge was kept"))
    }
}
