import Foundation

/// One request owns its timers and insertion eligibility. Focus changes never discard a paid draft.
struct InlineDraftLifetime {
    enum Stage { case capturing, prompt, writing, inserting, finished }
    enum Activation { case keep, dismissPrompt, previewOnly }
    private(set) var id = UUID()
    var stage: Stage = .finished
    private(set) var mayAutoInsert = false
    private(set) var restoringFocus = false
    mutating func begin(id: UUID = UUID()) {
        self.id = id; stage = .capturing; mayAutoInsert = true; restoringFocus = false
    }
    mutating func restoreForWriting() { stage = .writing; restoringFocus = true }
    mutating func restoredFocus() { restoringFocus = false }
    mutating func detach() { mayAutoInsert = false }
    mutating func finish() { id = UUID(); stage = .finished; mayAutoInsert = false; restoringFocus = false }
    func accepts(_ ticket: UUID) -> Bool { id == ticket }
    func activation(frontIsIris: Bool, frontIsTarget: Bool) -> Activation {
        if restoringFocus { return .keep }
        if stage == .writing && !frontIsTarget { return .previewOnly }
        if stage == .prompt && !frontIsIris { return .dismissPrompt }
        return .keep
    }
}
