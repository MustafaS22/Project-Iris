import Foundation
import CoreFoundation

/// Recover only selections whose replacement can be verified; never guess a nonempty caret.
enum InlineDraftSelection {
    static func matchesInserted(expected: String, actual: String) -> Bool {
        func normalize(_ value: String) -> String {
            let sentinels: Set<Character> = ["\u{200B}", "\u{FEFF}", "\u{2060}"]
            return String(value.drop(while: { sentinels.contains($0) })).replacingOccurrences(of: "\r\n", with: "\n").precomposedStringWithCanonicalMapping
        }
        let a = normalize(expected), b = normalize(actual)
        // Rich editors may expose one structural terminal newline; don't accept other edits.
        return a == b || a + "\n" == b || b + "\n" == a
    }
    static func exposedText(value: String?, placeholder: String?, characterCount: Int?) -> String? {
        if characterCount == 0, value == nil || value == placeholder { return "" }
        if let value, !value.isEmpty || characterCount == nil || characterCount == 0 { return value }
        return nil
    }
    struct Capture { let range: CFRange; let exposed: Bool }
    static func capture(original: String?, range: CFRange?, selected: String?) -> Capture? {
        guard let original, original.utf16.count <= 64_000 else { return nil }
        let text = original as NSString
        if let range {
            guard range.location >= 0, range.length >= 0, range.location <= text.length, range.length <= text.length - range.location else { return nil }
            return Capture(range: range, exposed: true)
        }
        if original.isEmpty { return Capture(range: CFRange(location: 0, length: 0), exposed: false) }
        if let selected, !selected.isEmpty {
            let match = text.range(of: selected)
            guard match.location != NSNotFound else { return nil }
            let tail = NSRange(location: match.location + 1, length: text.length - match.location - 1)
            guard text.range(of: selected, range: tail).location == NSNotFound else { return nil }
            return Capture(range: CFRange(location: match.location, length: match.length), exposed: false)
        }
        return nil
    }
}
