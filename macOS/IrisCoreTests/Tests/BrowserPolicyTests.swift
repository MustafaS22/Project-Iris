import XCTest
@testable import IrisCore

final class BrowserPolicyTests: XCTestCase {
    private let browsers = [BrowserApplication(id: "com.apple.Safari", name: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app")), BrowserApplication(id: "com.google.Chrome", name: "Google Chrome", url: URL(fileURLWithPath: "/Applications/Google Chrome.app")), BrowserApplication(id: "custom.browser", name: "My Browser", url: URL(fileURLWithPath: "/Applications/My Browser.app"))]
    func testSearchPreservesUnicodeAndSpecialCharactersAsOneQuery() throws {
        let query = "Swift & C++ #examples 日本語"
        let url = try BrowserPolicy.searchURL(query)
        XCTAssertEqual(url.host, "www.google.com")
        XCTAssertTrue(url.absoluteString.contains("%2B%2B"))
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems, [URLQueryItem(name: "q", value: query)])
        XCTAssertThrowsError(try BrowserPolicy.searchURL("   "))
        XCTAssertThrowsError(try BrowserPolicy.searchURL(String(repeating: "x", count: 2001)))
    }
    func testWebLinksRejectNonWebSchemesAndCredentials() throws {
        for target in ["file:///etc/passwd", "javascript:alert(1)", "spotify:playlist:x", "https://user:secret@example.com", "https://"] { XCTAssertThrowsError(try BrowserPolicy.webURL(target)) }
        XCTAssertEqual(try BrowserPolicy.webURL("https://example.com/page?q=x").host, "example.com")
        XCTAssertEqual(try BrowserPolicy.webURL("http://localhost:5173").port, 5173)
    }
    func testNamedAndCustomBrowsersResolveWithoutSilentFallback() throws {
        XCTAssertEqual(try BrowserPolicy.resolve("safari", applications: browsers)?.id, "com.apple.Safari")
        XCTAssertEqual(try BrowserPolicy.resolve("chrome", applications: browsers)?.name, "Google Chrome")
        XCTAssertEqual(try BrowserPolicy.resolve("custom.browser", applications: browsers)?.name, "My Browser")
        XCTAssertEqual(try BrowserPolicy.resolve("My Browser", applications: browsers)?.id, "custom.browser")
        XCTAssertNil(try BrowserPolicy.resolve(nil, applications: browsers))
        XCTAssertNil(try BrowserPolicy.resolve("default browser", applications: browsers))
        XCTAssertThrowsError(try BrowserPolicy.resolve("Not installed", applications: browsers))
    }
    func testBrowserChoiceSurvivesActionParsingAndIdentity() throws {
        let actions = try XCTUnwrap(ActionPolicy.parse("```iris-actions\n{\"actions\":[{\"type\":\"searchWeb\",\"target\":\"Swift tutorials\",\"browser\":\"Safari\"}]}\n```"))
        XCTAssertEqual(actions.first?.browser, "Safari")
        XCTAssertTrue(ActionPolicy.mayRunAutomatically(actions[0], enabled: true))
        XCTAssertNotEqual(AssistantAction(type: "openURL", target: "https://example.com", browser: "Safari").id, AssistantAction(type: "openURL", target: "https://example.com", browser: "Chrome").id)
    }
}
