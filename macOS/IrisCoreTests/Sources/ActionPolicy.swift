import Foundation

struct AssistantAction: Codable, Identifiable {
    var type: String
    var folder: String?
    var path: String?
    var content: String?
    var target: String?
    var browser: String?
    var displayName: String {
        switch type {
        case "computerTask": "Work on your computer"; case "openApplication": "Open an app"; case "openURL": "Open a web page"; case "searchWeb": "Search the web"
        case "listFiles": "Browse files"; case "readFile": "Read a file locally"; case "writeFile": "Save a file"
        case "createFolder": "Create a folder"; case "revealFile": "Show in Finder"
        case "createDocument": "Create a document"; case "generateImage": "Generate an image"; case "attachFile": "Add a file to chat"; case "findFiles": "Find files"
        case "playSpotifyPlaylist": "Play a Spotify playlist"; case "startLMStudio": "Host a local model"
        case "guideControl": "Highlight an app control"; case "focusControl": "Look at an app control"; case "drawOnScreen": "Draw an explanation"; case "runProject": "Run a project task"; default: "Review action"
        }
    }
    var id: String { [type, folder ?? "", path ?? "", target ?? "", browser ?? ""].map { "\($0.utf8.count):\($0)" }.joined(separator: "|") }
}
enum ActionPolicy {
    static let types: Set<String> = ["computerTask","openApplication", "openURL", "searchWeb", "listFiles", "readFile", "writeFile", "createFolder", "revealFile", "playSpotifyPlaylist", "startLMStudio", "runProject", "attachFile", "findFiles", "createDocument", "generateImage", "drawOnScreen", "guideControl", "focusControl"]
    static func mayRunAutomatically(_ action: AssistantAction, enabled: Bool) -> Bool {
        // Drawing only updates our own click-through overlay; computer actions retain their saved policy.
        // Separately billed media generation always keeps its explicit charge review.
        let routine = ["drawOnScreen", "guideControl", "focusControl", "openApplication", "openURL", "searchWeb", "listFiles", "readFile", "revealFile", "attachFile", "findFiles", "playSpotifyPlaylist", "startLMStudio", "createFolder"]
        return routine.contains(action.type) || enabled && types.contains(action.type) && action.type != "generateImage" && action.type != "computerTask"
    }
    static func parse(_ reply: String) -> [AssistantAction]? {
        guard let start = reply.range(of: "```iris-actions"), let end = reply.range(of: "```", range: start.upperBound..<reply.endIndex) else { return nil }
        let raw = String(reply[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        struct Plan: Decodable { var actions: [AssistantAction] }
        guard raw.utf8.count<=100000,
              var object=(try? JSONSerialization.jsonObject(with:Data(raw.utf8))) as? [String:Any],
              var actions=object["actions"] as? [[String:Any]],!actions.isEmpty,actions.count<=5 else{return nil}
        for index in actions.indices {
            if actions[index]["type"] as? String == "drawOnScreen",let content=actions[index]["content"] as? [String:Any],let data=try? JSONSerialization.data(withJSONObject:content),data.count<=16000 {
                actions[index]["content"]=String(decoding:data,as:UTF8.self)
            }
        }
        object["actions"]=actions
        guard let data=try? JSONSerialization.data(withJSONObject:object),let plan=try? JSONDecoder().decode(Plan.self,from:data),plan.actions.allSatisfy({types.contains($0.type)}) else{return nil}
        return plan.actions
    }
    static func containedURL(root: URL, path: String) throws -> URL {
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."), !path.contains("\0") else { throw CocoaError(.fileReadNoPermission) }
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        // Resolve each existing ancestor, including when the final file does not exist yet.
        var target = base
        for component in path.split(separator: "/") {
            target = target.appendingPathComponent(String(component)).standardizedFileURL
            if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: target.path) {
                target = URL(fileURLWithPath: destination, relativeTo: target.deletingLastPathComponent()).standardizedFileURL.resolvingSymlinksInPath()
            } else { target = target.resolvingSymlinksInPath() }
            guard target.path == base.path || target.path.hasPrefix(base.path + "/") else { throw CocoaError(.fileReadNoPermission) }
        }
        return target
    }
}
