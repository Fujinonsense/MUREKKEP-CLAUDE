import Foundation

// The few app types the checked files refer to, reduced to what they use (the real ones live in
// files that import Apple-only frameworks).

enum AnswerLanguage {
    case turkish
    case english

    var directive: String { "" }
}

enum SpeechText {}
