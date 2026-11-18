import Foundation

struct WeatherPlace: Codable, Identifiable, Equatable {
    var id: Int
    var name: String
    var latitude: Double
    var longitude: Double
    var timezone: String
    var country: String?
    var admin1: String?
    var population: Int?
    var label: String { [name, admin1, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ") }
    var valid: Bool { latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) && TimeZone(identifier: timezone) != nil }
}
struct WeatherSnapshot: Decodable {
    struct Current: Decodable {
        var time: Double
        var temperature_2m: Double?
        var apparent_temperature: Double?
        var relative_humidity_2m: Double?
        var precipitation: Double?
        var weather_code: Int?
        var wind_speed_10m: Double?
    }
    struct Daily: Decodable {
        var time: [Double]
        var weather_code: [Int?]?
        var temperature_2m_max: [Double?]?
        var temperature_2m_min: [Double?]?
        var precipitation_probability_max: [Double?]?
        var sunrise: [Double?]?
        var sunset: [Double?]?
    }
    var timezone: String
    var current: Current
    var current_units: [String: String]
    var daily: Daily
    var daily_units: [String: String]
    func summary(place: WeatherPlace, fetched: Date, now: Date = Date()) throws -> String {
        guard let zone = TimeZone(identifier: timezone), current.time.isFinite, abs(Date(timeIntervalSince1970: current.time).timeIntervalSince(now)) < 10800 else { throw IrisFailure.message("Weather data is outdated or has an invalid time zone. Try again shortly.") }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = zone; formatter.dateFormat = "yyyy-MM-dd HH:mm zzz"
        func value(_ number: Double?, _ unit: String?) -> String {
            guard let number, number.isFinite else { return "unavailable" }
            return String(format: "%.0f", number) + (unit.map { " " + $0 } ?? "")
        }
        var text = "Place: \(place.label). Time zone: \(timezone).\nModelled current conditions valid at \(formatter.string(from: Date(timeIntervalSince1970: current.time))); fetched at \(formatter.string(from: fetched)).\n"
        text += "Conditions: \(Self.condition(current.weather_code)); temperature \(value(current.temperature_2m, current_units["temperature_2m"])); feels like \(value(current.apparent_temperature, current_units["apparent_temperature"])); humidity \(value(current.relative_humidity_2m, current_units["relative_humidity_2m"])); wind \(value(current.wind_speed_10m, current_units["wind_speed_10m"])); precipitation \(value(current.precipitation, current_units["precipitation"])).\nDaily forecast (not observations):\n"
        for index in daily.time.indices.prefix(7) {
            let instant = daily.time[index]
            guard instant.isFinite else { continue }
            formatter.dateFormat = "EEEE yyyy-MM-dd"
            let day = formatter.string(from: Date(timeIntervalSince1970: instant))
            func at<T>(_ items: [T?]?) -> T? { guard let items, items.indices.contains(index) else { return nil }; return items[index] }
            formatter.dateFormat = "HH:mm"
            func clock(_ instant: Double?) -> String { guard let instant, instant.isFinite, instant > 0 else { return "unavailable" }; return formatter.string(from: Date(timeIntervalSince1970: instant)) }
            text += "\(day): \(Self.condition(at(daily.weather_code))); low \(value(at(daily.temperature_2m_min), daily_units["temperature_2m_min"])); high \(value(at(daily.temperature_2m_max), daily_units["temperature_2m_max"])); rain chance \(value(at(daily.precipitation_probability_max), daily_units["precipitation_probability_max"])); sunrise \(clock(at(daily.sunrise))), sunset \(clock(at(daily.sunset))).\n"
        }
        text += "Source: Open-Meteo, https://open-meteo.com/ . Current conditions are weather-model estimates. No severe-weather alert feed or historical weather was fetched."
        return text
    }
    static func condition(_ code: Int?) -> String {
        switch code {
        case 0: "Clear sky"; case 1: "Mainly clear"; case 2: "Partly cloudy"; case 3: "Overcast"
        case 45, 48: "Fog"; case 51, 53, 55: "Drizzle"; case 56, 57: "Freezing drizzle"
        case 61, 63, 65: "Rain"; case 66, 67: "Freezing rain"; case 71, 73, 75: "Snow"; case 77: "Snow grains"
        case 80, 81, 82: "Rain showers"; case 85, 86: "Snow showers"; case 95: "Thunderstorm"; case 96, 99: "Thunderstorm with hail"
        default: "Conditions unavailable"
        }
    }
}

enum LiveDataClient {
    static func search(_ city: String, session: URLSession = .shared) async throws -> [WeatherPlace] {
        let clean = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...100).contains(clean.count), !clean.contains(where: { $0.isNewline || $0.isASCII && $0.asciiValue! < 32 }) else { throw IrisFailure.message("Enter a city name, optionally followed by its country or region.") }
        var parts = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        parts.queryItems = [.init(name: "name", value: clean), .init(name: "count", value: "5"), .init(name: "language", value: "en"), .init(name: "format", value: "json")]
        struct Results: Decodable { var results: [WeatherPlace]? }
        let result: Results = try await get(parts.url!, session: session)
        return (result.results ?? []).filter(\.valid)
    }
    static func weather(place: WeatherPlace, fahrenheit: Bool, session: URLSession = .shared) async throws -> WeatherSnapshot {
        guard place.valid else { throw IrisFailure.message("Choose a valid weather location.") }
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        parts.queryItems = [
            .init(name: "latitude", value: String(place.latitude)), .init(name: "longitude", value: String(place.longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code,wind_speed_10m"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"),
            .init(name: "timezone", value: place.timezone), .init(name: "timeformat", value: "unixtime"), .init(name: "forecast_days", value: "7"),
            .init(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"), .init(name: "wind_speed_unit", value: fahrenheit ? "mph" : "kmh")
        ]
        return try await get(parts.url!, session: session)
    }
    private static func get<T: Decodable>(_ url: URL, session: URLSession) async throws -> T {
        try Task.checkCancellation()
        var request = URLRequest(url: url); request.timeoutInterval = 12; request.cachePolicy = .reloadIgnoringLocalCacheData
        let (bytes, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), bytes.count < 2_000_000 else { throw IrisFailure.message("The live weather service is unavailable or rate-limited. No current weather could be verified.") }
        return try JSONDecoder().decode(T.self, from: bytes)
    }
}

enum LiveDataIntent {
    static func wantsWeather(_ prompt: String) -> Bool {
        let lower = prompt.lowercased()
        if lower.range(of: #"\b(implement|build|code|api|weathering)\b"#, options: .regularExpression) != nil { return false }
        if lower.range(of: #"\b(explain|define|definition)\b"#, options: .regularExpression) != nil,
           lower.range(of: #"\b(today|tomorrow|current|now|tonight)\b"#, options: .regularExpression) == nil { return false }
        if lower.range(of: #"\b(temperature|humidity)\b"#, options: .regularExpression) != nil,
           lower.range(of: #"\b(weather|forecast|current|now|today|tomorrow)\b"#, options: .regularExpression) == nil, city(in: prompt) == nil { return false }
        return lower.range(of: #"\b(weather|forecast|temperature|rain|raining|snowing|humidity|sunrise|sunset|umbrella)\b|\bhow (hot|cold|windy)\b"#, options: .regularExpression) != nil
    }
    static func wantsWorldClock(_ prompt: String) -> Bool {
        if prompt.range(of: #"\b(complexity|format|function|code|python|javascript|swift|algorithm)\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return false }
        return prompt.range(of: #"\b(time|date|day)\b.{0,35}\b(in|at)\b"#, options: [.regularExpression, .caseInsensitive]) != nil }
    static func city(in prompt: String) -> String? {
        let range = ["in", "at", "for"].compactMap { prompt.range(of: "\\b" + $0 + "\\s+(.+)$", options: [.regularExpression, .caseInsensitive]) }.first
        guard let range else { return nil }
        var city = String(prompt[range]).replacingOccurrences(of: #"^(in|for|at)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        city = city.replacingOccurrences(of: #"\s+(today|tomorrow|tonight|now|right now|this (week|weekend|morning|afternoon|evening)|next \w+|please|and tell|and what|and how|on \w+).*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        city = city.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "?.!")))
        guard (2...100).contains(city.count), !["here", "my area", "my location", "my city", "me"].contains(city.lowercased()) else { return nil }
        return city
    }
    static func zone(for city: String) -> TimeZone? {
        if city.uppercased() == "UTC" || city.uppercased() == "GMT" { return TimeZone(secondsFromGMT: 0) }
        if city.contains("/"), let zone = TimeZone(identifier: city) { return zone }
        let name = city.split(separator: ",")[0].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "_").lowercased()
        let matches = TimeZone.knownTimeZoneIdentifiers.filter { $0.split(separator: "/").last?.lowercased() == name }
        return matches.count == 1 ? TimeZone(identifier: matches[0]) : nil
    }
    static func clock(now: Date = Date(), zone: TimeZone = .current) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = zone; formatter.dateFormat = "EEEE, yyyy-MM-dd 'at' HH:mm:ss zzz"
        let iso = ISO8601DateFormatter()
        return "Mac clock reading: \(formatter.string(from: now)). Time zone: \(zone.identifier); UTC offset \(zone.secondsFromGMT(for: now)) seconds. UTC instant: \(iso.string(from: now)). This is a request-time snapshot from the Mac's clock, not a network time check."
    }
}
