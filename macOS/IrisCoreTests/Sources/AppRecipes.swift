import Foundation

enum AppRecipes {
    static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
    static func appleQuote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r") + "\""
    }
    static func spotifyURI(_ target: String) throws -> String {
        var identifier = ""
        if target.hasPrefix("spotify:playlist:") { identifier = String(target.dropFirst("spotify:playlist:".count)) }
        else if let url = URL(string: target), url.scheme == "https", url.host == "open.spotify.com", url.pathComponents.count == 3, url.pathComponents[1] == "playlist" { identifier = url.pathComponents[2] }
        guard identifier.count == 22, identifier.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else { throw NSError(domain: "IrisAppRecipe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose a supported task, valid model identifier or Spotify playlist link."]) }
        return "spotify:playlist:" + identifier
    }
    static func projectCommand(root: URL, recipe: String) throws -> String {
        let command: String
        switch recipe {
        case "install": command = "npm install"
        case "build": command = "npm run build"
        case "dev": command = "npm run dev -- --host 127.0.0.1"
        case "preview": command = "python3 -m http.server 5173 --bind 127.0.0.1"
        default: throw NSError(domain: "IrisAppRecipe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose a supported task, valid model identifier or Spotify playlist link."])
        }
        return "cd " + shellQuote(root.path) + " && " + command
    }
    static func lmCommand(model: String) throws -> String {
        guard model.count <= 160, !model.hasPrefix("-"), model.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,47,58,64,95].contains($0) }) else { throw NSError(domain: "IrisAppRecipe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose a supported task, valid model identifier or Spotify playlist link."]) }
        let executable = "\"$HOME/.lmstudio/bin/lms\""
        let load = model.isEmpty ? "" : executable + " load " + shellQuote(model) + " && "
        return load + executable + " server start"
    }
}
