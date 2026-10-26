import Foundation

// What the checked files need from the app (AIEngine.swift imports NaturalLanguage, which Windows
// lacks): the answer language, switchable by the checks, and the language pick L().
enum AnswerLanguage {
    case turkish
    case english

    static var bound: AnswerLanguage?
    static var current: AnswerLanguage { bound ?? .turkish }

    var directive: String {
        self == .english ? "RESPONSE LANGUAGE: English." : "YANIT DİLİ: Türkçe."
    }
}

func L(_ turkish: String, _ english: String) -> String {
    AnswerLanguage.current == .english ? english : turkish
}

/// Darwin's constant, which Foundation on Windows does not have (MathEngine reads "e").
let M_E = 2.718281828459045
