import Foundation

enum InlineDraftKey: String, CaseIterable {
    case command, option
    var title: String { self == .command ? "Right Command" : "Right Option" }
    var keyCode: UInt16 { self == .command ? 54 : 61 }
    // AppKit preserves the device-specific right modifier bits in flagsChanged.
    var deviceMask: UInt { self == .command ? 0x10 : 0x40 }
}

struct InlineDraftGesture {
    private var pressedAt: TimeInterval?
    private var releasedAt: TimeInterval?

    mutating func reset() { pressedAt = nil; releasedAt = nil }

    mutating func update(down: Bool, at time: TimeInterval) -> Bool {
        if down {
            if pressedAt == nil { pressedAt = time }
            return false
        }
        guard let start = pressedAt else { return false }
        pressedAt = nil
        guard (0...0.35).contains(time - start) else { reset(); return false }
        if let previous = releasedAt, (0.015...0.50).contains(start - previous), time - previous <= 0.85 {
            reset()
            return true
        }
        releasedAt = time
        return false
    }
}
