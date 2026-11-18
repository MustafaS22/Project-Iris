import XCTest
@testable import IrisCore

final class StudioIntegrationTests: XCTestCase {
    func testPlaylistOnlyAcceptsExactSpotifyPlaylists() throws {
        let id = "37i9dQZF1DXcBWIGoYBM5M"
        XCTAssertEqual(try AppRecipes.spotifyURI("https://open.spotify.com/playlist/\(id)?si=test"), "spotify:playlist:" + id)
        XCTAssertThrowsError(try AppRecipes.spotifyURI("https://evil.example/playlist/\(id)"))
        XCTAssertThrowsError(try AppRecipes.spotifyURI("spotify:playlist:bad\"\nactivate"))
    }
    func testRecipesRejectFreeformCommandsAndQuoteFolderNames() throws {
        let command = try AppRecipes.projectCommand(root: URL(fileURLWithPath: "/tmp/a'b;echo injected"), recipe: "preview")
        XCTAssertTrue(command.hasPrefix("cd '/tmp/a'\"'\"'b;echo injected' && "))
        XCTAssertTrue(command.hasSuffix("--bind 127.0.0.1"))
        XCTAssertThrowsError(try AppRecipes.projectCommand(root: URL(fileURLWithPath: "/tmp"), recipe: "rm -rf x"))
        XCTAssertThrowsError(try AppRecipes.lmCommand(model: "$(touch /tmp/x)"))
        XCTAssertThrowsError(try AppRecipes.lmCommand(model: "--help"))
        XCTAssertTrue(try AppRecipes.lmCommand(model: "org/model-q4").contains("'org/model-q4'"))
    }
    func testProjectActionsWithDifferentRecipesHaveDistinctIdentities() {
        let install = AssistantAction(type: "runProject", folder: "folder", path: "site", target: "install")
        let build = AssistantAction(type: "runProject", folder: "folder", path: "site", target: "build")
        XCTAssertNotEqual(install.id, build.id)
    }
    func testStructuredOutputsValidateBeforeRendering() throws {
        XCTAssertNotNil(StudioArtifact.parse("```iris-study\n{\"kind\":\"flashcards\",\"cards\":[{\"question\":\"Q\",\"answer\":\"A\"}]}\n```"))
        XCTAssertNil(StudioArtifact.parse("```iris-study\n{\"kind\":\"flashcards\",\"cards\":[]}\n```"))
        XCTAssertNotNil(StudioArtifact.parse("```iris-study\n{\"kind\":\"mindmap\",\"root\":\"Topic\",\"branches\":[{\"title\":\"Branch\",\"details\":[\"Fact\"]}]}\n```"))
        XCTAssertNil(StudioArtifact.parse("```iris-study\n{\"kind\":\"mindmap\",\"branches\":[]}\n```"))
    }
}
