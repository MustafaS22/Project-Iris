import SwiftUI

struct LiveDataSettings: View {
    @ObservedObject var iris: IrisOrchestrator
    @State private var query = ""
    @State private var results: [WeatherPlace] = []
    @State private var loading = false
    @State private var failure: String?
    @State private var searchTask: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                Image(systemName: "sun.max.fill").irisSymbolStyle().font(.system(size: 42)).foregroundStyle(iris.accent)
                VStack(alignment: .leading, spacing: 5) { Text("Here and now").font(.title2.weight(.semibold)); Text("Current weather, local time and dates for your assistant.").foregroundStyle(IrisDesign.secondary) }
            }
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                VStack(alignment: .leading, spacing: 8) {
                    Text(timeline.date, style: .time).font(.system(size: 28, weight: .medium)).monospacedDigit()
                    Text(timeline.date, format: .dateTime.weekday(.wide).day().month(.wide).year()).font(.system(size: 14))
                    Text(TimeZone.current.identifier).font(.caption).foregroundStyle(IrisDesign.secondary)
                }
            }
            Text("Every question includes a fresh clock reading from this Mac. Ask about other cities or IANA time zones; daylight-saving changes use macOS's time-zone database.").font(.caption).foregroundStyle(IrisDesign.secondary)
            Divider()
            Toggle("Fetch weather when I ask", isOn: Binding(get: { iris.preferences.liveWeatherEnabled ?? true }, set: { value in iris.setPreference { $0.liveWeatherEnabled = value } }))
            if let place = iris.preferences.weatherPlace {
                HStack { VStack(alignment: .leading, spacing: 5) { Text("Default weather city").font(.caption).foregroundStyle(IrisDesign.secondary); Text(place.label).font(.headline) }; Spacer(); Button("Remove") { iris.setPreference { $0.weatherPlace = nil } } }
            }
            Text("Choose your weather city").font(.headline)
            HStack(spacing: 12) {
                TextField("City, optionally country or region", text: $query).textFieldStyle(IrisTextFieldStyle()).onSubmit { search() }
                Button(loading ? "Searching…" : "Search", systemImage: "magnifyingglass") { search() }.disabled(loading || query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
            }
            if let failure { Text(failure).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            ForEach(results) { place in
                HStack {
                    VStack(alignment: .leading, spacing: 4) { Text(place.label).font(.system(size: 14, weight: .medium)); Text(place.timezone).font(.caption).foregroundStyle(IrisDesign.secondary) }
                    Spacer()
                    Button(iris.preferences.weatherPlace?.id == place.id ? "Selected" : "Use city") { iris.setPreference { $0.weatherPlace = place }; results = [] }.disabled(iris.preferences.weatherPlace?.id == place.id)
                }.padding(.vertical, 8)
                Divider()
            }
            IrisPicker("Weather units", selection: Binding(get: { iris.preferences.weatherFahrenheit ?? false }, set: { value in iris.setPreference { $0.weatherFahrenheit = value } }), display: (iris.preferences.weatherFahrenheit ?? false) ? "°F · mph" : "°C · km/h", options: [.init(value: false, title: "Celsius", detail: "°C · km/h", symbol: "thermometer.medium"), .init(value: true, title: "Fahrenheit", detail: "°F · mph", symbol: "thermometer.medium")])
            Text("You can also ask “What's the weather in Tokyo tomorrow?” without saving a city. Iris sends only the city name and weather coordinates to Open-Meteo, not your chat or files. GPS and IP-based location lookup are not used. Weather is cached for up to five minutes; readings and forecasts show their time and source.").font(.caption).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true)
            Link("Weather data by Open-Meteo", destination: URL(string: "https://open-meteo.com/")!).font(.caption)
            Text("Live weather and world clocks are supported. General web search, news, prices and severe-weather alerts are not connected.").font(.caption).foregroundStyle(IrisDesign.secondary)
        }.onDisappear { searchTask?.cancel() }
    }
    private func search() {
        searchTask?.cancel(); loading = true; failure = nil
        let city = query
        searchTask = Task {
            defer { loading = false }
            do {
                let places = try await LiveDataClient.search(city)
                try Task.checkCancellation()
                results = places
                if places.isEmpty { failure = "No matching city. Try including its country or region." }
            } catch is CancellationError { }
            catch { failure = "City lookup couldn't finish. Check your connection and try again." }
        }
    }
}
