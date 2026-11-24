import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ComputerActivityView: View {
    @ObservedObject var session: ComputerUseSession
    var accent: Color
    @State private var history = false
    @State private var preview = false
    var body: some View {
        if session.running {
            VStack(alignment:.leading,spacing:12) {
                HStack(spacing:10) {
                    Image(systemName:session.paused ? "pause.circle.fill" : "cursorarrow.motionlines").foregroundStyle(accent)
                    VStack(alignment:.leading,spacing:3) {
                        Text("Working on your computer").font(.system(size:13,weight:.semibold))
                        Text(session.phase).font(.caption).foregroundStyle(IrisDesign.secondary).lineLimit(2)
                    }
                    Spacer()
                    Button { session.paused ? session.resume() : session.pause() } label: { Image(systemName:session.paused ? "play.fill" : "pause.fill") }.help(session.paused ? "Resume after checking the current app" : "Pause computer task")
                    Button { session.stop() } label: { Image(systemName:"stop.fill") }.help("Stop immediately · Escape")
                }
                Text(session.objective).font(.callout).lineLimit(2)
                Label(session.policy.shareScreen ? "Screen images may be shared with your AI during this task" : "Local interface inspection · images off",systemImage:session.policy.shareScreen ? "eye" : "lock.shield").font(.caption2).foregroundStyle(IrisDesign.secondary)
                if session.awaitingApproval {
                    Divider()
                    Text("Review this action").font(.subheadline.weight(.semibold))
                    ScrollView { Text(session.proposedAction).font(.system(size:12,design:.monospaced)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading) }.frame(maxHeight:180)
                    Text("Approve only if the target, text and effect match your request. Sending, payments, deletion, installation and sharing always need review.").font(.caption).foregroundStyle(IrisDesign.secondary)
                    HStack { Button("Allow once") { session.approve(true) }.buttonStyle(IrisActionStyle(primary:true)); Button("Deny & stop") { session.approve(false) }.buttonStyle(IrisActionStyle()) }
                }
                DisclosureGroup("Action history",isExpanded:$history) {
                    ForEach(session.history.suffix(12)) { item in HStack(alignment:.top) { Image(systemName:item.succeeded ? "checkmark.circle" : "exclamationmark.circle").foregroundStyle(item.succeeded ? accent : .orange); VStack(alignment:.leading) { Text(item.detail); Text(item.tool).foregroundStyle(IrisDesign.secondary) } }.font(.caption).padding(.vertical,3) }
                }.font(.caption)
                if session.policy.shareScreen, let image = session.native.lastImage, let nsImage = NSImage(data:image.data) {
                    DisclosureGroup("Last shared window",isExpanded:$preview) { Image(nsImage:nsImage).resizable().scaledToFit().frame(maxHeight:160).clipShape(RoundedRectangle(cornerRadius:8)) }.font(.caption)
                }
            }.padding(16).background(accent.opacity(0.055),in:RoundedRectangle(cornerRadius:14)).overlay(RoundedRectangle(cornerRadius:14).strokeBorder(accent.opacity(0.18),lineWidth:1))
        }
    }
}
struct ComputerAutonomySettings: View {
    @ObservedObject var session: ComputerUseSession
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Computer use").font(.headline)
            IrisPicker("Execution mode",selection:$session.policy.mode,options:ComputerMode.allCases.map{.init(value:$0,title:$0.rawValue)})
            Text("Observe inspects without acting. Assist reviews changes. Autonomous permits app focus, window resizing, scrolling and cursor movement; clicks, typing, shortcuts, file changes and external MCP tools still require explicit approval.").font(.callout).foregroundStyle(IrisDesign.secondary)
            Toggle("Allow task screenshots to be shared with my AI",isOn:$session.policy.shareScreen).toggleStyle(.switch)
            Text("Off by default. Images are captured only when a task requests them, kept in memory, and removed when it stops. Password controls and excluded apps are blocked when detectable. AX labels, OCR and approved file text can also be sent to your selected AI. Escape stops the task; manual interaction pauses it.").font(.caption).foregroundStyle(IrisDesign.secondary)
            Button("Exclude an application…") {
                let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.directoryURL = URL(fileURLWithPath:"/Applications"); panel.prompt = "Exclude app"
                if panel.runModal() == .OK, let url = panel.url, let identifier = Bundle(url:url)?.bundleIdentifier, !session.policy.excludedApps.contains(identifier) { session.policy.excludedApps.append(identifier) }
            }.buttonStyle(IrisActionStyle())
            TextField("Excluded app bundle IDs (comma separated)",text:Binding(get:{session.policy.excludedApps.joined(separator:", ")},set:{session.policy.excludedApps = $0.split(separator:",").map{$0.trimmingCharacters(in:.whitespaces)}})).textFieldStyle(IrisTextFieldStyle())
            DisclosureGroup("Individual native tool permissions") {
                ForEach(NativeComputerUse.tools + ComputerUseFiles.tools,id:\.name) { tool in
                    Toggle(tool.name,isOn:Binding(get:{!session.policy.deniedTools.contains(tool.name)},set:{allowed in if allowed { session.policy.deniedTools.removeAll{$0 == tool.name} } else { session.policy.deniedTools.append(tool.name) } })).toggleStyle(.switch).font(.caption).padding(.vertical,3)
                }
            }
            ComputerActivityView(session:session,accent:Color.accentColor)
            if !session.history.isEmpty {
                Text("Last task · \(session.phase)").font(.caption).foregroundStyle(IrisDesign.secondary)
                Button("Clear computer task history") { session.clearHistory() }.disabled(session.running)
            }
        }
    }
}
struct MCPSettingsView: View {
    @ObservedObject var session: ComputerUseSession
    @ObservedObject var manager: IrisMCPManager
    @State private var name = ""
@State private var endpoint = ""
@State private var command = ""
@State private var arguments = ""
@State private var token = ""
@State private var raw = ""
    @State private var issue: String?
    @State private var local = false
    @State private var importing = false
    @State private var adding = false
    @State private var trusted: IrisMCPConfiguration?
    init(session:ComputerUseSession) { self.session = session; self.manager = session.mcp }
    var body: some View {
        VStack(alignment:.leading,spacing:24) {
            VStack(alignment:.leading,spacing:8) {
                Label("Connect tools Iris can use",systemImage:"puzzlepiece.extension.fill").font(.headline)
                Text("Connect trusted app APIs and browser tools. Iris discovers their tools, resources and prompts. Each external tool call requires review; importing a configuration never runs it.").foregroundStyle(IrisDesign.secondary)
                HStack { Button("Add server") { adding.toggle() }.buttonStyle(IrisActionStyle(primary:true)); Button("Import JSON") { importing.toggle() }.buttonStyle(IrisActionStyle()) }
            }
            HStack(spacing:12) {
                Button("Browser tools") {
                    name = "Playwright"; local = true; command = ["/opt/homebrew/bin/npx", "/usr/local/bin/npx"].first(where:FileManager.default.isExecutableFile(atPath:)) ?? "/usr/local/bin/npx"
                    arguments = "[\"--yes\",\"@playwright/mcp@0.0.86\",\"--isolated\"]"; adding = true
                }
                Button("GitHub") { name = "GitHub"; local = false; endpoint = "https://api.githubcopilot.com/mcp/"; adding = true }
                Button("Fetch") {
                    name = "Fetch"; local = true; command = ["/opt/homebrew/bin/uvx", "/usr/local/bin/uvx", NSHomeDirectory() + "/.local/bin/uvx"].first(where:FileManager.default.isExecutableFile(atPath:)) ?? "/opt/homebrew/bin/uvx"
                    arguments = "[\"mcp-server-fetch==2026.11.11\"]"; adding = true
                }
            }.font(.caption)
            Text("Browser tools need Node.js 20+ and use an isolated Playwright browser, separate from your Safari tabs. Fetch needs uv. GitHub accepts your own PAT as the Bearer token. These presets only fill the form; review the server before enabling it. Approved-folder file tools are already built in.").font(.caption).foregroundStyle(IrisDesign.secondary)
            if adding {
                VStack(alignment:.leading,spacing:12) {
                    TextField("Server name",text:$name).textFieldStyle(IrisTextFieldStyle())
                    Toggle("Local executable (stdio)",isOn:$local).toggleStyle(.switch)
                    if local {
                        TextField("Absolute executable path",text:$command).textFieldStyle(IrisTextFieldStyle())
                        TextField("Arguments as a JSON array",text:$arguments).textFieldStyle(IrisTextFieldStyle())
                        Text("Local servers run as your macOS account with your account’s file and network access. Install only trusted servers. Iris does not install packages or run imported commands without your confirmation.").font(.caption).foregroundStyle(.orange)
                    } else {
                        TextField("https://example.com/mcp",text:$endpoint).textFieldStyle(IrisTextFieldStyle())
                        SecureField("Bearer token (optional, stored in Keychain)",text:$token).textFieldStyle(IrisTextFieldStyle())
                    }
                    Button("Save disabled server") {
                        do {
                            let args = arguments.isEmpty ? [] : try JSONDecoder().decode([String].self,from:Data(arguments.utf8))
                            try manager.add(.init(name:name,command:local ? command : nil,arguments:args,url:local ? nil : endpoint),secret:token)
                            token = ""; name = ""; endpoint = ""; command = ""; arguments = ""; adding = false; issue = nil
                        } catch { issue = error.localizedDescription }
                    }.buttonStyle(IrisActionStyle(primary:true))
                }
            }
            if importing {
                TextEditor(text:$raw).font(.system(size:12,design:.monospaced)).frame(height:150).accessibilityLabel("MCP configuration JSON")
                Button("Import disabled servers") { do { try manager.importJSON(raw); raw = ""; importing = false; issue = nil } catch { issue = error.localizedDescription } }
            }
            if let issue { Text(issue).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            ForEach(manager.configurations) { config in
                VStack(alignment:.leading,spacing:12) {
                    HStack {
                        VStack(alignment:.leading,spacing:4) { Text(config.name).font(.headline); Text(manager.status[config.id] ?? "Disabled").font(.caption).foregroundStyle(IrisDesign.secondary) }
                        Spacer()
                        Toggle("Enabled",isOn:Binding(get:{config.enabled},set:{enabled in if enabled { trusted = config } else { if let index = manager.configurations.firstIndex(where:{$0.id == config.id}) { manager.configurations[index].enabled = false; manager.save(); Task { await manager.disconnect(config.id) } } } })).toggleStyle(.switch)
                    }
                    Text(config.url ?? (config.command ?? "") + " " + config.arguments.joined(separator:" ")).font(.system(size:11,design:.monospaced)).foregroundStyle(IrisDesign.secondary).textSelection(.enabled)
                    HStack { Button("Test / reconnect") { Task { await manager.connect(config.id) } }.disabled(!config.enabled); Button("Remove",role:.destructive) { Task { await manager.remove(config.id) } } }
                    DisclosureGroup("Tools · \(manager.tools.filter{$0.server == config.id}.count)") {
                        ForEach(manager.tools.filter{$0.server == config.id}) { tool in
                            Toggle(isOn:Binding(get:{!session.policy.deniedTools.contains(tool.id)},set:{allowed in if allowed { session.policy.deniedTools.removeAll{$0 == tool.id} } else { session.policy.deniedTools.append(tool.id) } })) {
                                VStack(alignment:.leading,spacing:3) { Text(tool.name).font(.subheadline.weight(.medium)); Text(tool.description).font(.caption).foregroundStyle(IrisDesign.secondary) }
                            }.toggleStyle(.switch).padding(.vertical,5)
                        }
                    }
                    if let resources = manager.resources[config.id], !resources.isEmpty { Text("Resources: " + resources.joined(separator:", ")).font(.caption).foregroundStyle(IrisDesign.secondary) }
                    if let prompts = manager.prompts[config.id], !prompts.isEmpty { Text("Prompts: " + prompts.joined(separator:", ")).font(.caption).foregroundStyle(IrisDesign.secondary) }
                    Divider()
                }
            }
            if manager.configurations.isEmpty { Label("No external servers connected. Native computer controls work without MCP setup.",systemImage:"desktopcomputer").font(.callout).foregroundStyle(IrisDesign.secondary) }
            DisclosureGroup("Connection log") { ForEach(Array(manager.logs.enumerated()),id:\.offset) { _,line in Text(line).font(.system(size:11,design:.monospaced)).textSelection(.enabled) } }
        }.confirmationDialog("Enable this MCP server?",isPresented:Binding(get:{trusted != nil},set:{if !$0 {trusted = nil}}),titleVisibility:.visible) {
            if let config = trusted {
                Button("Trust and connect") { if let index = manager.configurations.firstIndex(where:{$0.id == config.id}) { manager.configurations[index].enabled = true; manager.save(); Task { await manager.connect(config.id) } }; trusted = nil }
                Button("Cancel",role:.cancel) { trusted = nil }
            }
        } message: { Text(trusted?.command != nil ? "This executable runs outside Iris with your account’s access. Tool review cannot sandbox the server itself. Continue only if you trust its publisher and arguments." : "This service can receive the arguments you approve. Its tool results are untrusted; credentials stay in Keychain.") }
    }
}
