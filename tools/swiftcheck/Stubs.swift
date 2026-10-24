import Foundation

// The few app types the checked files refer to, reduced to what they use (the real ones live in
// files that import Apple-only frameworks).

enum AnswerLanguage {
    case turkish
    case english

    var directive: String { "" }
    static var current: AnswerLanguage { .turkish }
}

enum SpeechText {}

/// AIEngine.swift's language pick; the checks read the Turkish side.
func L(_ turkish: String, _ english: String) -> String { turkish }

/// Darwin's constant, which Foundation on Windows does not have (MathEngine reads "e").
let M_E = 2.718281828459045

/// Brushes.swift's palettes name colours; only their existence matters here.
struct InkColor: Equatable, Hashable {
    var hex: UInt32

    init(hex: UInt32) {
        self.hex = hex
    }
}
