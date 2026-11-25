import SwiftUI

extension AgentRun {
    var color: Color { Color(hue: hue, saturation: 0.56, brightness: 0.98) }
    var avatarState: IrisState {
        switch status { case .running: .thinking; case .completed: .celebration; case .failed: .error; case .waiting: .attention; case .interrupted, .stopped: .dormant; default: .idle }
    }
}
struct AgentAvatar: View {
    let run: AgentRun
    var size: CGFloat = 44
    var body: some View {
        IrisAvatar(state: run.avatarState, color: run.color, size: size / 1.375, animated: true, desktop: true)
            .frame(width: size, height: size)
            .accessibilityLabel("\(run.name), \(run.status.title)")
    }
}

struct AgentPicker: View {
    let run: AgentRun
    var selected = false
    var body: some View {
        VStack(spacing: 8) {
            AgentAvatar(run: run, size: 58)

            Text(run.name).font(.system(size: 12, weight: selected ? .semibold : .medium)).lineLimit(1)
            HStack(spacing: 4) { Circle().fill(run.color.opacity(run.status.active ? 1 : 0.4)).frame(width: 4, height: 4); Text(run.status.title).font(.system(size: 10)).foregroundStyle(IrisDesign.secondary) }
        }.frame(width: 96).padding(.vertical, 12)
            .background(selected ? IrisDesign.control.opacity(0.45) : .clear, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}
struct AgentWorkspace: View {
    @ObservedObject var iris: IrisOrchestrator
    @ObservedObject var store: IrisAgentStore
    @State private var deploying = false
    @State private var removing: UUID?
    private var selected: AgentRun? { store.selectedID.flatMap(store.run) ?? store.runs.first }
    private var ordered: [AgentRun] { store.active + store.runs.filter { !$0.status.active } }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your team").font(.system(size: 23, weight: .semibold)).tracking(-0.4)
                    Text(store.runs.isEmpty ? "A little help with the bigger things." : "\(store.runningCount) working · \(store.runs.filter { $0.status == .waiting }.count) waiting")
                        .font(.system(size: 12)).foregroundStyle(IrisDesign.secondary)
                }
                Spacer()
                Button { deploying = true } label: { Label("New agent", systemImage: "plus").font(.system(size: 12, weight: .medium)) }.buttonStyle(IrisActionStyle())
            }.padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 12)
            if store.computerBusy && iris.computer.delegated {
                ComputerActivityView(session:iris.computer,accent:iris.accent)
                    .padding(.horizontal,28).padding(.bottom,8)
            }
            if let error = store.storageError { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal, 28) }
            if store.runs.isEmpty {
                Spacer()
                HStack(spacing: 20) {
                    ForEach(Array(AgentSpecialty.allCases.prefix(3).enumerated()), id: \.element) { index, role in
                        let sample = AgentRun(name: role.name, specialty: role, hue: [0.55,0.95,0.36][index], task: "", context: "", preferences: iris.preferences)
                        AgentAvatar(run: sample, size: 76).accessibilityHidden(true)
                    }
                }.frame(maxWidth: .infinity)
                Text("Who’s helping today?").font(.system(size: 24, weight: .semibold)).frame(maxWidth: .infinity).padding(.top, 24)
                Text("Give a specialist a project, a set of sources, or a detailed brief.\nStart here, or type @agent in chat.")
                    .font(.system(size: 13)).multilineTextAlignment(.center).lineSpacing(5).foregroundStyle(IrisDesign.secondary).frame(maxWidth: .infinity).padding(.top, 8)
                Spacer()
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) { ForEach(ordered) { run in
                        Button { store.selectedID = run.id } label: { AgentPicker(run: run, selected: selected?.id == run.id) }.buttonStyle(.plain)
                            .accessibilityLabel("Open \(run.name), \(run.status.title)")
                    } }.padding(.horizontal, 28).padding(.vertical, 8)
                }.scrollIndicators(.hidden).fixedSize(horizontal: false, vertical: true)
                Divider().opacity(0.35).padding(.horizontal, 28).padding(.top, 8)
                if let selected { AgentDetail(iris: iris, store: store, run: selected) { removing = selected.id }.id(selected.id) }
            }
            HStack { Text("Peek at your team in the top-right corner."); Spacer(); Text("Runs while Iris is open") }
                .font(.system(size: 10)).foregroundStyle(IrisDesign.secondary).padding(.horizontal, 28).padding(.vertical, 14)
        }
        .sheet(isPresented: $deploying) { AgentDeploySheet(iris: iris) }
        .alert("Remove this agent's saved work?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Cancel", role: .cancel) { removing = nil }
            Button("Remove", role: .destructive) { if let removing { store.remove(removing) }; removing = nil }
        } message: { Text("Created files remain in Library. This removes the agent's saved conversation and activity log.") }
    }
}
private struct AgentDetail: View {
    @ObservedObject var iris: IrisOrchestrator
    @ObservedObject var store: IrisAgentStore
    let run: AgentRun
    var remove: () -> Void
    @State private var reviewing = false
    @State private var direction = ""
    @State private var showActivity = false
    @Environment(\.irisReduceMotion) private var reduceMotion
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) { Text(run.name).font(.system(size: 17, weight: .semibold)); Text(run.specialty.title).font(.system(size: 11)).foregroundStyle(run.color) }
                    Spacer()
                    if run.status.active { Button("Stop", systemImage: "stop.fill") { store.stop(run.id) }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)) }
                    else { Button("Remove", systemImage: "trash", action: remove).buttonStyle(.plain).font(.caption).foregroundStyle(IrisDesign.secondary) }
                }
                Text(run.task).font(.system(size: 20, weight: .medium)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if run.status == .running { ProgressView().controlSize(.small).tint(run.color) }
                    Text(run.phase).font(.system(size: 12, weight: .medium)).foregroundStyle(run.color)
                    Spacer()
                }.padding(.vertical, 2)
                if let error = run.error { Text(error).font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                if run.status == .waiting, !run.pending.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Computer actions need review").font(.system(size: 14, weight: .semibold))
                        ForEach(run.pending) { action in Label(action.displayName, systemImage: "hand.raised.fill").font(.system(size: 12)).foregroundStyle(IrisDesign.secondary) }
                        Button("Review actions") { reviewing = true }.buttonStyle(IrisActionStyle(primary: true))
                    }
                }
                if !run.partial.isEmpty || !run.result.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        FormattedResponse(text: run.partial.isEmpty ? run.result : run.partial, fontSize: 15)
                    }.padding(.vertical, 10)
                }
                ForEach(run.files) { file in ChatFileCard(iris: iris, file: file) }
                if !run.events.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Button { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showActivity.toggle() } } label: {
                            HStack(spacing: 7) { Text("Activity"); Image(systemName: showActivity ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .semibold)); Spacer(); Text("\(run.modelTurns) of 4 responses this window").font(.system(size: 10)) }
                        }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(IrisDesign.secondary)
                        if showActivity {
                            ForEach(run.events.suffix(8)) { event in
                                HStack(alignment: .top, spacing: 10) { Circle().fill(run.color.opacity(0.7)).frame(width: 4, height: 4).padding(.top, 5); Text(event.text).font(.system(size: 11)).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true) }
                            }
                        }
                    }.padding(.top, 12)
                }
                if !run.status.active {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Add direction or a follow-up…", text: $direction, axis: .vertical).lineLimit(2...4).textFieldStyle(IrisTextFieldStyle())
                        Button(direction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Continue task" : "Send follow-up") { store.continueRun(run.id, direction: direction); direction = "" }.buttonStyle(IrisActionStyle(primary: true))
                    }
                }
            }.padding(.horizontal, 28).padding(.vertical, 24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity, alignment: .center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $reviewing) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Review \(run.name)'s actions").font(.system(size: 22, weight: .semibold))
                ScrollView { VStack(alignment: .leading, spacing: 20) { ForEach(run.pending) { action in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(action.displayName).font(.headline)
                        Text([action.path, action.target, action.folder].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(IrisDesign.secondary)
                        if let content = action.content { Text(verbatim: String(content.prefix(12000))).font(.system(size: 11, design: .monospaced)).fixedSize(horizontal: false, vertical: true) }
                    }
                } } }.frame(maxHeight: 330)
                Text("Only the actions shown will run. Existing folder access still applies.").font(.caption).foregroundStyle(IrisDesign.secondary)
                HStack { Button("Cancel") { reviewing = false }; Spacer(); Button("Run these actions") { store.approve(run.id); reviewing = false }.buttonStyle(IrisActionStyle(primary: true)) }
            }.padding(28).frame(width: 540).background(IrisDesign.canvas).preferredColorScheme(.dark)
        }
    }
}
struct AgentDeploySheet: View {
    @ObservedObject var iris: IrisOrchestrator
    @Environment(\.dismiss) private var dismiss
    @State private var task = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Give a bigger task its own space.").font(.system(size: 24, weight: .semibold)).tracking(-0.5)
            Text("Iris chooses a specialist from your brief. Include the outcome you want and any constraints.").font(.system(size: 13)).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("What should the agent work on?", text: $task, axis: .vertical).lineLimit(4...8).textFieldStyle(IrisTextFieldStyle())
            if !task.isEmpty { Label(AgentPolicy.specialty(for: task).title, systemImage: AgentPolicy.specialty(for: task).symbol).font(.caption).foregroundStyle(iris.accent) }
            Text("Uses your selected AI and existing Computer settings. For source files or connectors, use @agent with attachments or @sources in chat.").font(.system(size: 11)).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack { Button("Cancel") { dismiss() }; Spacer(); Button("Deploy agent") {
                do {
                    let mention = ChatMentionRequest(text: task, agent: true)
                    try iris.deployAgent(mention: mention, task: task, typed: "@agent " + task, shared: [], origin: iris.currentAgentConversation, fromChat: false)
                    dismiss()
                } catch { self.error = error.localizedDescription }
            }.buttonStyle(IrisActionStyle(primary: true)).disabled(task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(28).frame(width: 480).background(IrisDesign.canvas).foregroundStyle(IrisDesign.text).preferredColorScheme(.dark)
    }
}
struct NotchAgentsView: View {
    @ObservedObject var iris: IrisOrchestrator
    @ObservedObject var store: IrisAgentStore
    @State private var selection: UUID?
    private var ordered: [AgentRun] { store.active + store.runs.filter { !$0.status.active } }
    private var selected: AgentRun? { selection.flatMap(store.run) ?? ordered.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Your team").font(.system(size: 20, weight: .semibold)); Spacer(); Text("\(store.runningCount) working").font(.system(size: 11)).foregroundStyle(IrisDesign.secondary) }
            if store.computerBusy && iris.computer.delegated && iris.computer.running {
                Button("Review active computer task",systemImage:"cursorarrow") { iris.showWorkspace(.agents) }
                    .buttonStyle(IrisActionStyle())
            }
            if ordered.isEmpty { Text("Give a bigger task its own specialist. Use @agent in chat to get started.").font(.system(size: 13)).lineSpacing(4).foregroundStyle(IrisDesign.secondary) }
            else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) { ForEach(ordered) { run in
                        Button { selection = run.id } label: {
                            VStack(spacing: 7) { AgentAvatar(run: run, size: 44); Text(run.name).font(.system(size: 11, weight: .medium)).lineLimit(1) }
                                .frame(width: 66).padding(.vertical, 8)
                                .foregroundStyle(selected?.id == run.id ? run.color : IrisDesign.secondary)
                                .background(selected?.id == run.id ? run.color.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityLabel("Show \(run.name)'s progress")
                    } }
                }.scrollIndicators(.hidden)
                if let run = selected {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text(run.name).font(.system(size: 14, weight: .semibold)); Text(run.status.title).font(.system(size: 10)).foregroundStyle(run.color); Spacer(); if run.status.active { Button("Stop", systemImage: "stop.fill") { store.stop(run.id) }.font(.system(size: 11)).buttonStyle(.plain) } }
                        Text(AgentPolicy.title(for: run.task)).font(.system(size: 13)).lineLimit(2)
                        HStack(spacing: 7) { if run.status == .running { ProgressView().controlSize(.mini) }; Text(run.phase).font(.system(size: 11)).foregroundStyle(run.color).lineLimit(2) }
                        if let error = run.error { Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(2) }
                        Button("Open \(run.name)", systemImage: "arrow.up.right") { store.selectedID = run.id; iris.showWorkspace(.agents) }.font(.system(size: 11, weight: .medium)).buttonStyle(.plain).padding(.top, 2)
                    }.padding(.top, 4)
                }
            }
            HStack {
                Button { iris.draft = iris.draft.isEmpty ? "@agent " : "@agent " + iris.draft; iris.tab = .ask; iris.notchPinned = true } label: { Label("New agent", systemImage: "plus") }
                Spacer(); Button("All agents") { iris.showWorkspace(.agents) }
            }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(IrisDesign.secondary).padding(.top, 6)
        }
    }
}
