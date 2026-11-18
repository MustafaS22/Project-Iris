import Foundation
import NaturalLanguage

enum AssistantLanguage {
    static let choices: [(String, String)] = [("auto", "Match my language"), ("en", "English"), ("ar", "العربية"), ("hi", "हिन्दी"), ("ur", "اردو"), ("es", "Español"), ("fr", "Français"), ("de", "Deutsch"), ("pt", "Português"), ("it", "Italiano"), ("zh-Hans", "简体中文"), ("ja", "日本語"), ("ko", "한국어"), ("ru", "Русский"), ("tr", "Türkçe")]
    static func instruction(choice: String) -> String {
        guard choice != "auto", let item = choices.first(where: { $0.0 == choice }) else {
            return "Match the language of the user's latest message, including mixed-language conversation. Honor explicit translation or language requests. Keep code, action JSON keys, filenames and identifiers unchanged."
        }
        return "Reply in \(item.1) unless the user explicitly requests another language or translation. Keep code, action JSON keys, filenames and identifiers unchanged."
    }
    static var instruction: String { instruction(choice: UserDefaults.standard.string(forKey: "IrisReplyLanguage") ?? "auto") }
    static var speechLocale: Locale {
        let code = UserDefaults.standard.string(forKey: "IrisInputLanguage") ?? "auto"
        return code == "auto" ? .current : Locale(identifier: code)
    }
    static func spokenLanguage(_ text: String) -> String {
        NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue ?? Locale.current.language.languageCode?.identifier ?? "en"
    }
}
