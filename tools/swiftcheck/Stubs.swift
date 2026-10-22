import Foundation

// The few app types the checked files refer to, reduced to what they use (the real ones live in
// files that import Apple-only frameworks).

enum AnswerLanguage {
    case turkish
    case english

    var directive: String { "" }
}

enum SpeechText {}

/// Brushes.swift's palettes name colours; only their existence matters here.
struct InkColor: Equatable, Hashable {
    var hex: UInt32

    init(hex: UInt32) {
        self.hex = hex
    }
}
