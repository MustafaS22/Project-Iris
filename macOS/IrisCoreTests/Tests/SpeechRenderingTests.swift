import XCTest
@testable import IrisCore
final class SpeechRenderingTests:XCTestCase {
    func testScientificUnitsAreSpokenWithoutChangingOrdinaryWords() {
        XCTAssertEqual(SpeechRendering.text("kgm^2/s"),"kilogram meters squared per second")
        XCTAssertEqual(SpeechRendering.text("9.81 m/s²"),"9.81 meters per second squared")
        XCTAssertEqual(SpeechRendering.text(#"$9.81\,\mathrm{m}/\mathrm{s}^{2}$"#),"9.81 meters per second squared")
        XCTAssertEqual(SpeechRendering.text(#"\frac{\mathrm{kg}\cdot m^{2}}{\mathrm{s}}"#),"kilogram meters squared per second")
        XCTAssertEqual(SpeechRendering.text("1 kg"),"1 kilogram")
        XCTAssertEqual(SpeechRendering.text("5 kg"),"5 kilograms")
        XCTAssertEqual(SpeechRendering.text("kg·m²·s⁻²"),"kilogram meters squared per second squared")
        XCTAssertEqual(SpeechRendering.text("I am listening. This is normal."),"I am listening. This is normal.")
        XCTAssertEqual(SpeechRendering.text("1.2e-3"),"1.2 times ten to the power of minus 3")
    }
    func testPacingLeavesRoomForUnfinishedPhrases(){XCTAssertGreaterThan(RecognitionPacing.pause(after:"and then with"),RecognitionPacing.pause(after:"that's everything"))}
}
