import SwiftUI

struct ProjectRunnerView: View {
    @ObservedObject var iris: IrisOrchestrator
    @State private var folder = ""
    @State private var path = ""
    @State private var recipe = "preview"
    @State private var model = ""
    @State private var playlist = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Run on your Mac").font(.headline)
            Text("Tasks follow your Computer permission setting. Review mode lets you inspect commands first. Iris uses Terminal and Spotify through macOS Automation.").font(.caption).foregroundStyle(IrisDesign.secondary)
            HStack {
                IrisPicker("Project folder", selection: $folder, display: iris.actions.folders.first(where: { $0.id == folder })?.name ?? "Choose a folder", options: [.init(value: "", title: "Choose a folder")] + iris.actions.folders.map { .init(value: $0.id, title: $0.name, symbol: "folder") })
                Button("Grant folder…") { iris.actions.grant() }
            }
            TextField("Project subfolder (optional)", text: $path).textFieldStyle(IrisTextFieldStyle())
            IrisPicker("Task", selection: $recipe, display: ["preview": "Preview website", "install": "Install dependencies", "build": "Build project", "dev": "Start development server"][recipe] ?? recipe, options: [.init(value: "preview", title: "Preview website", detail: "Static site · localhost:5173", symbol: "globe"), .init(value: "install", title: "Install dependencies", detail: "npm install", symbol: "shippingbox"), .init(value: "build", title: "Build project", detail: "npm run build", symbol: "hammer"), .init(value: "dev", title: "Start development server", detail: "Vite · localhost", symbol: "terminal")])
            Button((iris.preferences.alwaysAllowComputerActions ?? false) ? "Run project task" : "Review project task") { iris.queueActions([.init(type: "runProject", folder: folder, path: path, target: recipe)]) }.disabled(folder.isEmpty)
            Divider()
            TextField("Downloaded LM Studio model identifier (optional)", text: $model).textFieldStyle(IrisTextFieldStyle())
            Button((iris.preferences.alwaysAllowComputerActions ?? false) ? "Start local model hosting" : "Review local model hosting") { iris.queueActions([.init(type: "startLMStudio", target: model)]) }
            TextField("Spotify playlist link", text: $playlist).textFieldStyle(IrisTextFieldStyle())
            Button((iris.preferences.alwaysAllowComputerActions ?? false) ? "Play playlist" : "Review playlist playback") { iris.queueActions([.init(type: "playSpotifyPlaylist", target: playlist)]) }.disabled(playlist.isEmpty)
            ActionReview(iris: iris)
        }
    }
}
