import AppKit

@MainActor
enum BrowserService {
    private static var cachedApplications: (date: Date, apps: [BrowserApplication])?
    static var applications: [BrowserApplication] {
        if let cachedApplications, Date().timeIntervalSince(cachedApplications.date) < 30 { return cachedApplications.apps }
        var seen = Set<String>()
        let result: [BrowserApplication] = NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!).compactMap { url -> BrowserApplication? in
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, seen.insert(id).inserted else { return nil }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? url.deletingPathExtension().lastPathComponent
            return BrowserApplication(id: id, name: name, url: url)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        cachedApplications = (Date(), result)
        return result
    }
    static func open(_ url: URL, browser: String? = nil) async throws -> String {
        let checked = try BrowserPolicy.webURL(url.absoluteString)
        if let app = try BrowserPolicy.resolve(browser, applications: applications) {
            _ = try await NSWorkspace.shared.open([checked], withApplicationAt: app.url, configuration: .init())
            return app.name
        }
        guard NSWorkspace.shared.open(checked) else { throw IrisFailure.message("Your default browser couldn't open this page.") }
        return "your default browser"
    }
}
