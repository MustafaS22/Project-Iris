import Foundation

enum StudioTools {
    static func formatJSON(_ text: String) throws -> String {
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
    static func cards(from text: String) -> [StudyCard] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let pieces = line.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pieces.count == 2, !pieces[0].isEmpty, !pieces[1].isEmpty else { return nil }
            return StudyCard(question: pieces[0], answer: pieces[1])
        }
    }
}
