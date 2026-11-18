import XCTest
@testable import IrisCore

final class GreetingTests: XCTestCase {
    func testGreetingUsesLocalHourAndTrimsName() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 4 * 3600)!
        for (hour, prefix) in [(0, "Good night"), (4, "Good night"), (5, "Good morning"), (11, "Good morning"), (12, "Good afternoon"), (16, "Good afternoon"), (17, "Good evening"), (21, "Good evening"), (22, "Good night")] {
            let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: hour)))
            XCTAssertEqual(GreetingPolicy.text(at: date, name: " Mustafa ", calendar: calendar), prefix + ", Mustafa.")
            XCTAssertEqual(GreetingPolicy.text(at: date, name: "   ", calendar: calendar), prefix + ".")
        }
    }
}
