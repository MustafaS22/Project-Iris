import Foundation

@MainActor extension IrisOrchestrator {
    var knowledgeScanInputs: [KnowledgeMemoryPlan.Input] {
        knowledge.documents.filter { knowledge.enabled.contains($0.source.rawValue) }.map {
            .init(id: $0.id, source: $0.source.rawValue, title: $0.title, body: $0.body)
        } + data.notes.map { .init(id: "note:" + $0.id.uuidString, source: nil, title: String($0.text.prefix(80)), body: $0.text) }
    }
    var visibleKnowledgeMemories: [KnowledgeMemoryRecord] {
        let ids = Set(knowledgeScanInputs.map(\.id))
        return (data.knowledgeMemories ?? []).filter { ids.contains($0.documentID) && !$0.facts.isEmpty }
    }
    func memoryContext(for query: String) -> String {
        guard preferences.memoryEnabled ?? true else { return "" }
        let manual = MemoryPolicy.context(data.memories ?? [], query: query, enabled: true)
        let valid = KnowledgeMemoryPlan.current(data.knowledgeMemories ?? [], chunks: KnowledgeMemoryPlan.chunks(knowledgeScanInputs))
        return [manual, KnowledgeMemoryPlan.context(valid, query: query)].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
    func forgetKnowledgeMemory(_ id: String) {
        // Keep the fingerprint so an unchanged source won't recreate a forgotten memory.
        if let index = data.knowledgeMemories?.firstIndex(where: { $0.id == id }) { data.knowledgeMemories?[index].facts = []; save() }
    }
    func stopKnowledgeScan() { knowledgeScanTask?.cancel() }
    func scanKnowledgeNow() {
        guard !knowledgeScanning else { return }
        knowledgeScanIssue = nil
        guard preferences.memoryEnabled ?? true else { knowledgeScanIssue = "Enable saved memories in Settings → Memory, then scan again."; return }
        guard preferences.providerVerified || knowledgeScanResponder != nil else { knowledgeScanIssue = "Connect your AI in Settings → AI, then scan again."; return }
        let chunks = KnowledgeMemoryPlan.chunks(knowledgeScanInputs)
        guard !chunks.isEmpty else { knowledgeScanStatus = "Add notes or enable a knowledge connection to scan."; return }
        let pending = KnowledgeMemoryPlan.pending(chunks, records: data.knowledgeMemories ?? [])
        guard !pending.isEmpty else { knowledgeScanStatus = "Already up to date. No AI usage needed."; knowledgeScanProgress = 1; return }
        let batches = KnowledgeMemoryPlan.batches(pending)
        let config = preferences
        knowledgeScanning = true; knowledgeScanProgress = 0
        knowledgeScanStatus = "Preparing \(pending.count) new or changed sections…"
        knowledgeScanTask = Task { [weak self] in
            guard let self else { return }
            var processed = 0, saved = 0
            defer { self.knowledgeScanning = false; self.knowledgeScanTask = nil }
            do {
                for batch in batches {
                    try Task.checkCancellation()
                    guard self.preferences.memoryEnabled ?? true else { throw CancellationError() }
                    // Recheck consent and content before sending, as connections can refresh during a scan.
                    let current = Dictionary(self.knowledgeScanInputs.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
                    let eligible = batch.filter { current[$0.input.id] == $0.input }
                    if eligible.isEmpty { processed += batch.count; continue }
                    self.knowledgeScanStatus = "Reading \(processed + 1)–\(processed + eligible.count) of \(pending.count) · \(eligible.first?.input.title ?? "Knowledge")"
                    let prompt = try KnowledgeMemoryPlan.prompt(eligible)
                    let reply: String
                    if let responder = self.knowledgeScanResponder { reply = try await responder(prompt) }
                    else if config.source == .local {
                        reply = try await ModelService.answer(server: config.server, model: config.model, messages: [.init(role: "user", text: prompt)], context: "", role: config.role, draftInstruction: KnowledgeMemoryPlan.instruction, outputLimit: 2800)
                    } else {
                        reply = try await CloudModelService.answer(source: config.source, model: config.model, messages: [.init(role: "user", text: prompt)], context: "", draftInstruction: KnowledgeMemoryPlan.instruction, outputLimit: 2800)
                    }
                    try Task.checkCancellation()
                    guard self.preferences.memoryEnabled ?? true else { throw CancellationError() }
                    let decoded = try KnowledgeMemoryPlan.decode(reply, batch: eligible)
                    // Never commit results for revoked, deleted or changed material after awaiting the AI.
                    let fresh = Dictionary(self.knowledgeScanInputs.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
                    let stillAllowed = Set(eligible.filter { fresh[$0.input.id] == $0.input }.map(\.id))
                    let accepted = decoded.filter { stillAllowed.contains($0.id) }
                    let old = self.data.knowledgeMemories
                    var records = old ?? []
                    let replacing = Set(accepted.map(\.id))
                    records.removeAll { replacing.contains($0.id) }; records.append(contentsOf: accepted)
                    self.data.knowledgeMemories = records
                    guard self.save() else { self.data.knowledgeMemories = old; throw CocoaError(.fileWriteUnknown) }
                    saved += accepted.reduce(0) { $0 + $1.facts.count }
                    processed += batch.count; self.knowledgeScanProgress = Double(processed) / Double(pending.count)
                }
                let remaining = KnowledgeMemoryPlan.pending(KnowledgeMemoryPlan.chunks(self.knowledgeScanInputs), records: self.data.knowledgeMemories ?? [])
                self.knowledgeScanStatus = "Saved \(saved) \(saved == 1 ? "memory" : "memories"). " + (remaining.isEmpty ? "Knowledge is up to date." : "Some sources changed. Scan again to catch up.")
                if remaining.isEmpty { self.data.knowledgeScanAt = Date(); self.save() }
            } catch is CancellationError {
                self.knowledgeScanStatus = "Stopped · \(saved) memories saved. Scan now resumes unfinished material."
            } catch {
                self.knowledgeScanStatus = "\(saved) memories saved. Finished sections are kept; Scan now resumes the rest."
                self.knowledgeScanIssue = Task.isCancelled ? nil : error.localizedDescription
                if Task.isCancelled { self.knowledgeScanStatus = "Stopped · \(saved) memories saved. Scan now resumes unfinished material." }
            }
        }
    }
}
