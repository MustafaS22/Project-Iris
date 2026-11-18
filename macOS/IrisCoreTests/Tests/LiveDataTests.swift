import XCTest
import Foundation
@testable import IrisCore

final class LiveDataTests: XCTestCase {
    private var session: URLSession!
    private var place: WeatherPlace { .init(id: 2950159, name: "Berlin", latitude: 52.52, longitude: 13.41, timezone: "Europe/Berlin", country: "Germany", admin1: "Berlin", population: 3400000) }
    override func setUp() { let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [FixtureProtocol.self]; session = URLSession(configuration: configuration) }
    override func tearDown() { session.invalidateAndCancel(); FixtureProtocol.handler = nil }
    func testClockIsFreshAndUsesRequestedZoneAcrossDST() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-01T12:00:00Z"))
        let dubai = try XCTUnwrap(LiveDataIntent.zone(for: "Dubai"))
        let newYork = try XCTUnwrap(LiveDataIntent.zone(for: "New York"))
        XCTAssertTrue(LiveDataIntent.clock(now: now, zone: dubai).contains("16:00:00"))
        XCTAssertTrue(LiveDataIntent.clock(now: now, zone: newYork).contains("07:00:00"))
        XCTAssertTrue(LiveDataIntent.clock(now: now, zone: newYork).contains("-18000"))
        XCTAssertNil(LiveDataIntent.zone(for: "IST"))
    }
    func testWeatherAndWorldClockIntentAvoidUnrelatedQuestions() {
        for prompt in ["What's the weather in Dubai tomorrow?", "Will it rain in Berlin today?", "How hot is it in Tokyo?", "Explain the weather in Paris today"] { XCTAssertTrue(LiveDataIntent.wantsWeather(prompt), prompt) }
        for prompt in ["Build a weather app", "Explain temperature", "What is temperature?", "Weathering in geography", "Review this weather API code"] { XCTAssertFalse(LiveDataIntent.wantsWeather(prompt), prompt) }
        XCTAssertTrue(LiveDataIntent.wantsWorldClock("What time is it in Tokyo?"))
        XCTAssertFalse(LiveDataIntent.wantsWorldClock("Explain time complexity in Swift"))
        XCTAssertEqual(LiveDataIntent.city(in: "Weather in New York tomorrow please?"), "New York")
        XCTAssertEqual(LiveDataIntent.city(in: "Forecast for tomorrow in Berlin?"), "Berlin")
        XCTAssertEqual(LiveDataIntent.city(in: "What's the weather for Paris, France today?"), "Paris, France")
        XCTAssertNil(LiveDataIntent.city(in: "Weather here?"))
    }
    func testCityLookupEncodesOnlyLocationAndValidatesResults() async throws {
        FixtureProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "geocoding-api.open-meteo.com")
            XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "name" })?.value, "Berlin, Germany")
            return (200, try JSONSerialization.data(withJSONObject: ["results": [["id": 2950159, "name": "Berlin", "latitude": 52.52, "longitude": 13.41, "timezone": "Europe/Berlin", "country": "Germany"]]]))
        }
        let found = try await LiveDataClient.search("Berlin, Germany", session: session)
        XCTAssertEqual(found.count, 1); XCTAssertTrue(found[0].valid)
    }
    func testWeatherPayloadIncludesCurrentDailyUnitsAndNoPrompt() async throws {
        FixtureProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "api.open-meteo.com")
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(items.first { $0.name == "temperature_unit" }?.value, "fahrenheit")
            XCTAssertEqual(items.first { $0.name == "wind_speed_unit" }?.value, "mph")
            XCTAssertEqual(items.first { $0.name == "timeformat" }?.value, "unixtime")
            XCTAssertEqual(items.first { $0.name == "forecast_days" }?.value, "7")
            XCTAssertNil(request.httpBody)
            return (200, try Self.weatherData())
        }
        let data = try await LiveDataClient.weather(place: place, fahrenheit: true, session: session)
        XCTAssertEqual(data.current.temperature_2m, 18)
    }
    func testWeatherSummaryRetainsTimestampUnitsAndSource() throws {
        let snapshot = try JSONDecoder().decode(WeatherSnapshot.self, from: Self.weatherData())
        let text = try snapshot.summary(place: place, fetched: Date())
        XCTAssertTrue(text.contains("18 °C")); XCTAssertTrue(text.contains("45 %")); XCTAssertTrue(text.contains("12 km/h"))
        XCTAssertTrue(text.contains("Open-Meteo")); XCTAssertTrue(text.contains("Daily forecast")); XCTAssertTrue(text.contains("fetched at"))
        var old = snapshot; old.current.time = 0
        XCTAssertThrowsError(try old.summary(place: place, fetched: Date()))
    }
    @MainActor func testMissingOrDisabledWeatherNeverFabricatesConditions() async throws {
        FixtureProtocol.handler = { _ in XCTFail("No network expected"); return (500, Data()) }
        let service = LiveDataService()
        var preferences = Preferences()
        let missing = try await service.prepare(prompt: "What's the weather?", preferences: preferences, conversation: UUID(), session: session)
        XCTAssertFalse(missing.hasWeather); XCTAssertTrue(missing.context.contains("needs a city"))
        preferences.liveWeatherEnabled = false
        let disabled = try await service.prepare(prompt: "Weather in Berlin", preferences: preferences, conversation: UUID(), session: session)
        XCTAssertFalse(disabled.hasWeather); XCTAssertTrue(disabled.context.contains("disabled"))
    }
    @MainActor func testCachingAndSameConversationFollowupAvoidRepeatedWeatherCalls() async throws {
        var count = 0
        FixtureProtocol.handler = { _ in count += 1; return (200, try Self.weatherData()) }
        let service = LiveDataService(), conversation = UUID()
        var preferences = Preferences(); preferences.weatherPlace = place
        let first = try await service.prepare(prompt: "Weather today", preferences: preferences, conversation: conversation, session: session)
        let second = try await service.prepare(prompt: "What about tomorrow?", preferences: preferences, conversation: conversation, session: session)
        XCTAssertTrue(first.hasWeather); XCTAssertTrue(second.hasWeather); XCTAssertEqual(count, 1)
    }
    @MainActor func testAmbiguousCitiesAndOfflineFailuresAreReported() async throws {
        FixtureProtocol.handler = { _ in (200, Data(#"{"results":[{"id":1,"name":"Springfield","latitude":40,"longitude":-89,"timezone":"America/Chicago","admin1":"Illinois","population":100000},{"id":2,"name":"Springfield","latitude":42,"longitude":-72,"timezone":"America/New_York","admin1":"Massachusetts","population":150000}]}"#.utf8)) }
        let service = LiveDataService()
        let ambiguous = try await service.prepare(prompt: "Weather in Springfield", preferences: Preferences(), conversation: UUID(), session: session)
        XCTAssertFalse(ambiguous.hasWeather); XCTAssertTrue(ambiguous.context.contains("Several cities"))
        FixtureProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let offline = try await service.prepare(prompt: "Weather in Berlin", preferences: Preferences(), conversation: UUID(), session: session)
        XCTAssertFalse(offline.hasWeather); XCTAssertTrue(offline.context.contains("Do not guess"))
    }
    private static func weatherData() throws -> Data {
        let now = Date().timeIntervalSince1970
        return try JSONSerialization.data(withJSONObject: ["timezone": "Europe/Berlin", "current": ["time": now, "temperature_2m": 18, "apparent_temperature": 17, "relative_humidity_2m": 45, "precipitation": 0, "weather_code": 2, "wind_speed_10m": 12], "current_units": ["temperature_2m": "°C", "apparent_temperature": "°C", "relative_humidity_2m": "%", "precipitation": "mm", "wind_speed_10m": "km/h"], "daily": ["time": [now], "weather_code": [2], "temperature_2m_max": [20], "temperature_2m_min": [10], "precipitation_probability_max": [20], "sunrise": [now - 10000], "sunset": [now + 10000]], "daily_units": ["temperature_2m_max": "°C", "temperature_2m_min": "°C", "precipitation_probability_max": "%"]])
    }
}
