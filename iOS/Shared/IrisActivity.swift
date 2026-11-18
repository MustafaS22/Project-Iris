import ActivityKit
import Foundation

struct IrisActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String
        var message: String
        var theme: String?
    }
    var session: String
}
