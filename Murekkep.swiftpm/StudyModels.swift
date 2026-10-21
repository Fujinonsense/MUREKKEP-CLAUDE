import Foundation

/// The study tools made from a course's sources (NotebookLM's flashcards, quiz, mind map and report).
enum StudyKind: String, Codable, CaseIterable, Identifiable {
    case flashcards
    case quiz
    case mindMap
    case guide

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .flashcards: return "rectangle.on.rectangle.angled"
        case .quiz: return "checklist"
        case .mindMap: return "point.3.connected.trianglepath.dotted"
        case .guide: return "doc.text.magnifyingglass"
        }
    }
}

struct Flashcard: Codable, Identifiable, Equatable {
    var id = UUID()
    var front: String
    var back: String
    var review = CardReview()
}

struct QuizQuestion: Codable, Identifiable, Equatable {
    var id = UUID()
    var question: String
    var choices: [String]
    /// Index of the right choice.
    var answer: Int
    var explanation: String
}

struct MindNode: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var children: [MindNode] = []
}

struct GuideSection: Codable, Equatable {
    var heading: String
    var points: [String]
}

struct GuideTerm: Codable, Equatable {
    var term: String
    var definition: String
}

/// A study guide: the gist, each part's main points, the key terms and questions to think about.
struct StudyGuide: Codable, Equatable {
    var summary: [String]
    var sections: [GuideSection]
    var terms: [GuideTerm]
    var questions: [String]
}

/// One made study tool and what it was made from.
struct StudySet: Codable, Identifiable {
    var id = UUID()
    var kind: StudyKind
    var title: String
    var sectionID: UUID?
    var sourceIDs: [UUID]
    var sourceTitles: [String]
    var created = Date()
    var english: Bool
    /// Which brain wrote it ("Cihazda · Apple Intelligence", "Çevrimdışı"…).
    var engine: String
    var cards: [Flashcard] = []
    var questions: [QuizQuestion] = []
    var map: MindNode?
    var guide: StudyGuide?
    /// The best quiz score so far (right answers).
    var bestScore: Int?

    /// Cards to study now: due ones first, then up to `newLimit` never-seen ones.
    func dueCards(now: Date, newLimit: Int = 20) -> [Flashcard] {
        let seen = cards.filter { $0.review.due != nil && SpacedRepetition.isDue($0.review, now: now) }
            .sorted { ($0.review.due ?? now) < ($1.review.due ?? now) }
        let fresh = cards.filter { $0.review.due == nil }.prefix(newLimit)
        return seen + fresh
    }
}
