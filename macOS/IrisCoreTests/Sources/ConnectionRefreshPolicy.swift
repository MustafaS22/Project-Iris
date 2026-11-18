import Foundation

enum ConnectionRefreshPolicy {
    static let interval: TimeInterval = 15 * 60
    static func isDue(lastAttempt: Date?, now: Date) -> Bool {
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= interval
    }
}
