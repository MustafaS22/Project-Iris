import XCTest
@testable import IrisCore
final class PersonalityTests: XCTestCase {
    func testLegacyAndUnknownIDsKeepPreferencesReadable() throws {
        XCTAssertEqual(IrisPersonality.resolve(nil), .companion)
        XCTAssertEqual(IrisPersonality.resolve("unknown-future-character"), .companion)
        var original = Preferences(); original.name = "Alex"; original.geminiSpeechStyle = "Focused"
        let bytes = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Preferences.self, from: bytes)
        XCTAssertEqual(restored.personality, .companion); XCTAssertEqual(restored.replySpeechStyle,"Focused")
        XCTAssertEqual(restored.name,"Alex")
    }
    func testSelectionAndVoiceOptOutPersist() throws {
        for personality in IrisPersonality.allCases {
            var prefs = Preferences(); prefs.personalityID = personality.rawValue; prefs.geminiSpeechStyle = "Focused"
            let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(prefs))
            XCTAssertEqual(restored.personality,personality); XCTAssertEqual(restored.replySpeechStyle,personality.delivery)
            prefs.personalityVoiceTone = false; XCTAssertEqual(prefs.replySpeechStyle,"Focused")
        }
    }
    func testPersonalitiesHaveDistinctScenariosAndBoundedLocalSamples() {
        XCTAssertEqual(IrisPersonality.allCases.count,6)
        for scenario in PersonalityScenario.allCases {
            let replies = IrisPersonality.allCases.map { $0.sample(scenario) }
            XCTAssertEqual(Set(replies).count,6)
            XCTAssertTrue(replies.allSatisfy { !$0.isEmpty && $0.count < 400 && !$0.contains("iris-actions") })
        }
        XCTAssertEqual(Set(IrisPersonality.allCases.map(\.instruction)).count,6)
    }
    func testPersonalityCannotOverrideGroundingFormatOrPermissionRules() {
        for personality in IrisPersonality.allCases {
            XCTAssertTrue(personality.instruction.contains("strict output formats take priority"))
            XCTAssertTrue(personality.instruction.contains("source grounding"))
            XCTAssertTrue(personality.instruction.contains("not identity, capabilities or permissions"))
            XCTAssertTrue(personality.instruction.contains("surrounding conversation only"))
            XCTAssertTrue(["Warm","Calm","Natural","Focused"].contains(personality.delivery))
        }
    }
}
