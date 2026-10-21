import Foundation

/// How well a card was remembered.
enum ReviewRating: Int, Codable, CaseIterable {
    case again = 1
    case hard
    case good
    case easy
}

/// A flashcard's memory state.
struct CardReview: Codable, Equatable {
    /// How much the interval grows on "good" (starts at 2.5, never below 1.3).
    var ease = 2.5
    /// Days between reviews once learned (0 while new).
    var interval: Double = 0
    /// In the short learning (or relearning) steps.
    var learning = true
    /// Which learning step the card is on.
    var step = 0
    /// After a lapse: the interval the card comes back with once relearned.
    var relearnInterval: Double?
    var reps = 0
    var lapses = 0
    /// nil = never studied.
    var due: Date?
}

/// An Anki-like scheduler (SM-2 with learning steps). New cards go through 1 and 10 minutes; "good"
/// on the last step graduates them to a day, "easy" straight to four. Learned cards grow by their
/// ease on "good" (×1.2 on "hard", ×ease×1.3 on "easy", which also raises the ease); "again" costs
/// 0.2 ease, brings the card back in 10 minutes and, once relearned, at half its interval.
enum SpacedRepetition {
    static let learningSteps: [TimeInterval] = [60, 600]
    static let relearningSteps: [TimeInterval] = [600]
    static let graduatingInterval = 1.0
    static let easyInterval = 4.0
    static let minimumEase = 1.3
    private static let day: TimeInterval = 86_400

    static func isDue(_ r: CardReview, now: Date) -> Bool {
        guard let due = r.due else { return true }
        return due <= now
    }

    static func review(_ card: CardReview, rating: ReviewRating, now: Date) -> CardReview {
        var r = card
        r.reps += 1
        if r.learning {
            let steps = r.relearnInterval == nil ? learningSteps : relearningSteps
            switch rating {
            case .again:
                r.step = 0
                r.due = now.addingTimeInterval(steps[0])
            case .hard:
                // The current step once more, a little longer on the first.
                let wait = r.step == 0 && steps.count > 1 ? (steps[0] + steps[1]) / 2 : steps[min(r.step, steps.count - 1)]
                r.due = now.addingTimeInterval(wait)
            case .good:
                if r.step + 1 < steps.count {
                    r.step += 1
                    r.due = now.addingTimeInterval(steps[r.step])
                } else {
                    graduate(&r, interval: r.relearnInterval ?? graduatingInterval, now: now)
                }
            case .easy:
                graduate(&r, interval: r.relearnInterval.map { $0 * 1.5 } ?? easyInterval, now: now)
            }
            return r
        }
        switch rating {
        case .again:
            r.lapses += 1
            r.ease = max(minimumEase, r.ease - 0.2)
            r.relearnInterval = max(1, r.interval * 0.5)
            r.learning = true
            r.step = 0
            r.due = now.addingTimeInterval(relearningSteps[0])
            return r
        case .hard:
            r.interval *= 1.2
            r.ease = max(minimumEase, r.ease - 0.15)
        case .good:
            r.interval = max(r.interval + 1, r.interval * r.ease)
        case .easy:
            r.interval = max(r.interval + 1, r.interval * r.ease * 1.3)
            r.ease += 0.15
        }
        r.due = now.addingTimeInterval(r.interval * day)
        return r
    }

    private static func graduate(_ r: inout CardReview, interval: Double, now: Date) {
        r.learning = false
        r.step = 0
        r.relearnInterval = nil
        r.interval = interval
        r.due = now.addingTimeInterval(interval * day)
    }

    /// How long until the card comes back after `rating` (for the buttons' labels).
    static func wait(after rating: ReviewRating, for card: CardReview, now: Date) -> TimeInterval {
        (review(card, rating: rating, now: now).due ?? now).timeIntervalSince(now)
    }
}
