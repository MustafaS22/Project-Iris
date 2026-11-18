import XCTest
@testable import IrisCore
final class ScreenQuestionTests: XCTestCase {
    func testDiagramAndScreenRequestsGetVisualInput() {
        for prompt in ["Label the parts of this diagram", "What is on my screen?", "Help me understand this graph", "Circle the button here", "What am I looking at?", "look at this", "Annotate these parts"] {
            XCTAssertTrue(ScreenQuestionPolicy.wantsSnapshot(prompt), prompt)
        }
    }
    func testOrdinaryQuestionsDoNotShareScreen() {
        for prompt in ["Hi", "What is 2 + 2?", "What is photosynthesis?", "Write a letter to Sam", "Create a folder", "Explain gravity"] {
            XCTAssertFalse(ScreenQuestionPolicy.wantsSnapshot(prompt), prompt)
        }
    }
    func testExplicitNoCaptureOverridesVisualTerms() {
        for prompt in ["Don't look at my screen", "Do not capture this diagram", "Without looking at the screen explain gravity", "Stop sharing my screen", "Don’t capture the window"] {
            XCTAssertFalse(ScreenQuestionPolicy.wantsSnapshot(prompt), prompt)
            XCTAssertTrue(ScreenQuestionPolicy.forbidsSnapshot(prompt), prompt)
        }
    }
}
