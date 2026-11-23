import XCTest
@testable import IrisCore

final class DefaultVoiceTests: XCTestCase {
    func testNewAndLegacyPreferencesUseDefaultVoice() throws {
        let old = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(Preferences()))
        XCTAssertEqual(old.speechProvider, "fish")
        for stored in ["system", "native", "fish", ""] {
            var preferences = old
            preferences.voiceProvider = stored
            XCTAssertEqual(preferences.speechProvider, "fish")
        }
    }

    func testExplicitAlternativeProvidersArePreserved() {
        for provider in ["gemini", "voicebox"] {
            var preferences = Preferences()
            preferences.voiceProvider = provider
            XCTAssertEqual(preferences.speechProvider, provider)
        }
    }
}
