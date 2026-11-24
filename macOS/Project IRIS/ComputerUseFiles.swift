import Foundation
import MCP

/// Prefer direct file operations inside existing Iris folder grants over Finder clicks.
@MainActor enum ComputerUseFiles {
    static let tools: [ComputerTool] = {
        let text: Value = .object(["type":"string"])
        let base: [String:Value] = ["folder":text,"path":text]
        return [
            .init(name:"file_list",detail:"List files inside an approved folder; path is relative.",properties:base,required:["folder"]),
            .init(name:"file_read",detail:"Read a UTF-8 file locally; contents enter the selected AI context after approval.",properties:base,required:["folder","path"]),
            .init(name:"file_write",detail:"Create a new UTF-8 file in an approved folder; never overwrite an existing file.",properties:base.merging(["content":text]) { a,_ in a },required:["folder","path","content"]),
            .init(name:"file_move",detail:"Move a file within one approved folder. No overwrites, cross-folder moves or deletion.",properties:base.merging(["destination":text]) { a,_ in a },required:["folder","path","destination"]),
            .init(name:"file_create_folder",detail:"Create a directory inside an approved folder.",properties:base,required:["folder","path"])
        ]
    }()
    static func execute(_ name: String, arguments: [String:Value], files: AssistantActions) throws -> ComputerObservation {
        guard let tool = tools.first(where:{$0.name == name}), Set(arguments.keys).isSubset(of:Set(tool.properties.keys)), tool.required.allSatisfy({arguments[$0]?.stringValue != nil}), let folderID = arguments["folder"]?.stringValue, let folder = files.folders.first(where:{$0.id == folderID}) else { throw IrisFailure.message("Choose an approved folder identifier and the documented file arguments.") }
        var stale = false
        let root = try URL(resolvingBookmarkData:folder.bookmark,options:IrisLocalStorage.resolutionOptions,relativeTo:nil,bookmarkDataIsStale:&stale)
        guard !stale else { throw IrisFailure.message("The folder grant expired. Grant it again in Settings → Computer.") }
        let scoped = root.startAccessingSecurityScopedResource(); defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        guard scoped || !IrisLocalStorage.isSandboxed else { throw IrisFailure.message("This folder is not accessible.") }
        let path = arguments["path"]?.stringValue ?? ""
        guard !path.split(separator:"/").contains(where:{$0.hasPrefix(".")}), !["keychain","credentials","password"].contains(where:path.lowercased().contains) else { throw IrisFailure.message("Hidden and credential-related files are excluded from computer tasks.") }
        let url = try ActionPolicy.containedURL(root:root,path:path)
        switch name {
        case "file_list":
            let rows = try FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:[.isDirectoryKey],options:.skipsHiddenFiles).prefix(200).map { item in item.lastPathComponent + (((try? item.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) == true) ? "/" : "") }
            return .init(text:rows.joined(separator:"\n"),image:nil)
        case "file_read":
            guard (try url.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile) == true, (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max) < 60000 else { throw IrisFailure.message("Read only regular text files smaller than 60 KB.") }
            return .init(text:String(try String(contentsOf:url,encoding:.utf8).prefix(16000)),image:nil)
        case "file_write":
            guard !path.isEmpty, !FileManager.default.fileExists(atPath:url.path), let content = arguments["content"]?.stringValue, content.utf8.count < 100000 else { throw IrisFailure.message("Choose a new filename and text under 100 KB. Existing files are never replaced.") }
            try Data(content.utf8).write(to:url,options:.withoutOverwriting)
        case "file_move":
            guard let destination = arguments["destination"]?.stringValue, !destination.isEmpty, !destination.split(separator:"/").contains(where:{$0.hasPrefix(".")}) else { throw IrisFailure.message("Choose a visible destination inside the same approved folder.") }
            let target = try ActionPolicy.containedURL(root:root,path:destination)
            guard (try url.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile) == true, !FileManager.default.fileExists(atPath:target.path) else { throw IrisFailure.message("Move only regular files to new destinations; nothing will be overwritten.") }
            try FileManager.default.moveItem(at:url,to:target)
        case "file_create_folder": guard !path.isEmpty else { throw IrisFailure.message("Enter a relative directory name.") }; try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        default: throw IrisFailure.message("Unknown file tool.")
        }
        return .init(text:"File operation completed. Read or list the resulting path to verify the expected content.",image:nil)
    }
}
