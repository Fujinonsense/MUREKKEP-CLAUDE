import Foundation

/// The app's language. Every user-facing string is written in Turkish in the code and goes through
/// `Loc.t`, which gives it back in the chosen language (the English texts are in `Translations`).
enum AppLanguage: String, CaseIterable, Identifiable {
    case turkish = "tr"
    case english = "en"

    var id: String { rawValue }

    /// Each language names itself, so it can be found whatever language is on screen.
    var title: String {
        switch self {
        case .turkish: return "Türkçe"
        case .english: return "English"
        }
    }

    static let storageKey = "appLanguage"

    /// The saved choice; until one is made, the device's language (Turkish stays Turkish, any
    /// other language gets English).
    static var stored: AppLanguage {
        if let raw = UserDefaults.standard.string(forKey: storageKey), let saved = AppLanguage(rawValue: raw) {
            return saved
        }
        let device = Locale.preferredLanguages.first ?? "tr"
        return device.hasPrefix("tr") ? .turkish : .english
    }
}

enum Loc {
    private static let lock = NSLock()
    private static var cached: AppLanguage?

    static var language: AppLanguage {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let current = AppLanguage.stored
        cached = current
        return current
    }

    static var isEnglish: Bool { language == .english }

    /// Called after the user picked another language.
    static func reload() {
        lock.lock()
        cached = nil
        lock.unlock()
    }

    /// `turkish` in the app's language. `{0}`, `{1}`… in it are filled with `args`, in order; in an
    /// English text `{0|page|pages}` becomes the word that goes with that number.
    static func t(_ turkish: String, _ args: String...) -> String {
        fill(isEnglish ? (Translations.english[turkish] ?? turkish) : turkish, args)
    }

    /// A name that means something else elsewhere in the app ("Doğru" is a line among the shapes
    /// but a check mark among the stickers): looked up as "kind|name" first.
    static func named(_ turkish: String, kind: String) -> String {
        guard isEnglish else { return turkish }
        return Translations.english["\(kind)|\(turkish)"] ?? Translations.english[turkish] ?? turkish
    }

    private static func fill(_ template: String, _ args: [String]) -> String {
        var text = template
        for (i, arg) in args.enumerated() {
            let one = arg.trimmingCharacters(in: .whitespaces) == "1"
            // {i|singular|plural}
            while let open = text.range(of: "{\(i)|"), let close = text[open.upperBound...].firstIndex(of: "}") {
                let forms = text[open.upperBound..<close].split(separator: "|", omittingEmptySubsequences: false)
                let word = forms.count == 2 ? String(one ? forms[0] : forms[1]) : String(forms.first ?? "")
                text.replaceSubrange(open.lowerBound...close, with: word)
            }
            text = text.replacingOccurrences(of: "{\(i)}", with: arg)
        }
        return text
    }

    /// Numbers and dates follow the app's language.
    static var locale: Locale {
        Locale(identifier: isEnglish ? "en_US" : "tr_TR")
    }
}
