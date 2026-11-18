import Foundation

/// Selection is deliberate: a pass over another avatar must not replace the open agent.
struct AgentPeekState {
    static let hoverDelay: TimeInterval = 0.7
    var selectedID: UUID?
    private(set) var hoveredID: UUID?
    private var hoverStarted: TimeInterval?
    mutating func hover(_ id: UUID, inside: Bool, at time: TimeInterval) {
        if inside {
            if hoveredID != id { hoveredID = id; hoverStarted = time }
        } else if hoveredID == id { hoveredID = nil; hoverStarted = nil }
    }
    mutating func advance(at time: TimeInterval) {
        if let hoveredID, let start = hoverStarted, time-start >= Self.hoverDelay {
            selectedID = hoveredID; hoverStarted = nil
        }
    }
    mutating func click(_ id: UUID) {
        selectedID = selectedID == id ? nil : id
        // Clicking to close must not immediately reopen from the same hover.
        hoverStarted = nil
    }
    mutating func retain(_ ids: Set<UUID>) {
        if let selectedID, !ids.contains(selectedID) { self.selectedID = nil }
        if let hoveredID, !ids.contains(hoveredID) { self.hoveredID = nil; hoverStarted = nil }
    }
}
