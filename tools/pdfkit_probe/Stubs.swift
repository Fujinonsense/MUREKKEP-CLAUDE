import Foundation

// What the math files need from the app on a Mac (as tools/mathcheck/Stubs.swift, without M_E,
// which Darwin has): the answer language and the language pick L().
enum AnswerLanguage {
    case turkish
    case english

    static var bound: AnswerLanguage?
    static var current: AnswerLanguage { bound ?? .english }

    var directive: String {
        self == .english ? "RESPONSE LANGUAGE: English." : "YANIT DİLİ: Türkçe."
    }
}

func L(_ turkish: String, _ english: String) -> String {
    AnswerLanguage.current == .english ? english : turkish
}
