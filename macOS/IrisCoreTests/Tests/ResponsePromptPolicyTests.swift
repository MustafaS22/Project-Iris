import XCTest
@testable import IrisCore

final class ResponsePromptPolicyTests: XCTestCase {
    private func compact(_ prompt: String, skill: String = "", images: Bool = false, context: String = "") -> Bool {
        ResponsePromptPolicy.usesCompactPrompt(prompt: prompt, skill: skill, hasImages: images, context: context)
    }
    func testStandaloneQuestionsUseShortInstructions() {
        for prompt in ["Hello!", "What is photosynthesis?", "Explain gravity", "Why is the sky blue?", "2 + 2?"] {
            XCTAssertTrue(compact(prompt), prompt)
        }
    }
    func testActionsAndFollowupsKeepFullCapabilities() {
        for prompt in ["What is in my downloads?", "Explain this", "What does that mean?", "Create a PDF", "Open Safari", "How do I build a website?", "What is the weather?", "Continue", "What is Iris?", "What are the files in Documents?"] {
            XCTAssertFalse(compact(prompt), prompt)
        }
    }
    func testAttachmentsStudioAndGuidanceKeepFullPrompt() {
        XCTAssertFalse(compact("Explain gravity", skill: "Use these references"))
        XCTAssertFalse(compact("Explain gravity", images: true))
        XCTAssertFalse(compact("Explain gravity", context: "Attachment: lesson.pdf"))
        XCTAssertFalse(compact("Explain gravity", context: "Floating desktop mode is active"))
    }
}
