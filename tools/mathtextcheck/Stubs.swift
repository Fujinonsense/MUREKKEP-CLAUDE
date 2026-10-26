import Foundation

// What Questions.swift needs from the app (AIEngine.swift imports NaturalLanguage, which Windows lacks).
enum AnswerLanguage {
    case turkish
    case english

    var directive: String {
        self == .english ? "RESPONSE LANGUAGE: English." : "YANIT DİLİ: Türkçe."
    }
}
