import Foundation

struct BrowserApplication: Identifiable, Equatable {
    let id: String
    let name: String
    let url: URL
}
enum BrowserPolicy {
    static func webURL(_ target: String) throws -> URL {
        guard let url = URL(string: target.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
            throw IrisFailure.message("Choose an http or https web address without embedded credentials.")
        }
        return url
    }
    static func searchURL(_ query: String) throws -> URL {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 2000 else { throw IrisFailure.message("Use a search between 1 and 2,000 characters.") }
        var parts = URLComponents(string: "https://www.google.com/search")!
        parts.queryItems = [URLQueryItem(name: "q", value: query)]
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return parts.url!
    }
    static func resolve(_ requested: String?, applications: [BrowserApplication]) throws -> BrowserApplication? {
        let requested = (requested ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if requested.isEmpty || ["default", "default browser", "system default"].contains(requested) { return nil }
        let aliases = ["safari": "com.apple.safari", "chrome": "com.google.chrome", "google chrome": "com.google.chrome", "edge": "com.microsoft.edgemac", "microsoft edge": "com.microsoft.edgemac", "firefox": "org.mozilla.firefox", "brave": "com.brave.browser", "arc": "company.thebrowser.browser", "opera": "com.operasoftware.opera"]
        let identifier = aliases[requested] ?? requested
        guard let match = applications.first(where: { $0.id.lowercased() == identifier || $0.name.lowercased() == requested || $0.url.deletingPathExtension().lastPathComponent.lowercased() == requested }) else {
            throw IrisFailure.message("That browser isn't installed or registered to open web pages. Choose an installed browser or use Default browser.")
        }
        return match
    }
}
