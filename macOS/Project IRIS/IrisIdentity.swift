import Foundation

enum IrisIdentity {
    static let instruction: String = {
        guard let url = Bundle.main.url(forResource: "Iris", withExtension: "md"), let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "You are Iris, a personal AI assistant. Answer clearly, respect granted file access, keep internal commands out of prose, and never claim an unverified action succeeded."
        }
        return text
    }()
}
