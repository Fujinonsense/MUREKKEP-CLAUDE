import Foundation

/// Mürekkep Pro: the plans, and what the free plan allows (checked in tools/swiftcheck).
///
/// The free plan keeps everything a student needs to take notes: notebooks, PDFs, the everyday pens,
/// the text pen, shapes, the student templates, plain colour backgrounds. It also gets 15 AI answers
/// a day, one video or audio overview a week and three study sets a week. Pro takes the limits off
/// and opens the 3D inks, the special templates and the creative backgrounds.
///
/// The AI runs on the iPad, so there are no servers to pay for, and Pro costs less than the note
/// apps that charge for theirs. App Store, Turkey, October 2026:
/// - Goodnotes Pro: ₺1.369,99 a year (+₺379 a month for AI).
/// - Notability Plus: ₺349,99 a month or ₺599,99 a year.
/// - Notability Pro: ₺899,99 a month or ₺4.499,99 a year.
/// - Noteshelf: ₺399,99 a month or ₺999,99 a year.
enum ProPlan {
    enum Feature: String, Codable, CaseIterable {
        case aiAnswer
        case overview
        case studySet
        case premiumInk
        case premiumTemplate
        case premiumBackground
    }

    /// The App Store edition sells Pro; the personal build (without the APPSTORE flag) has it all.
    #if APPSTORE
    static let sells = true
    #else
    static let sells = false
    #endif

    static let dailyAnswers = 15
    static let weeklyOverviews = 1
    static let weeklyStudySets = 3
    static let freeTrialDays = 7

    /// How many a free user may use, and whether the count starts again each week (else each day);
    /// nil for what only Pro opens.
    static func limit(_ feature: Feature) -> (count: Int, weekly: Bool)? {
        switch feature {
        case .aiAnswer: return (dailyAnswers, false)
        case .overview: return (weeklyOverviews, true)
        case .studySet: return (weeklyStudySets, true)
        case .premiumInk, .premiumTemplate, .premiumBackground: return nil
        }
    }

    /// What the free plan has used, per day or per ISO week.
    struct Usage: Codable, Equatable {
        var counts: [String: Int] = [:]

        static func key(_ feature: Feature, on date: Date, calendar: Calendar) -> String {
            guard let limit = ProPlan.limit(feature) else { return feature.rawValue }
            if limit.weekly {
                let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
                return "\(feature.rawValue)|\(c.yearForWeekOfYear ?? 0)-W\(c.weekOfYear ?? 0)"
            }
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            return "\(feature.rawValue)|\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
        }

        /// Uses the free plan has left today (or this week).
        func remaining(_ feature: Feature, on date: Date, calendar: Calendar) -> Int {
            guard let limit = ProPlan.limit(feature) else { return 0 }
            return max(0, limit.count - (counts[Self.key(feature, on: date, calendar: calendar)] ?? 0))
        }

        func allows(_ feature: Feature, isPro: Bool, on date: Date, calendar: Calendar) -> Bool {
            isPro || remaining(feature, on: date, calendar: calendar) > 0
        }

        /// Counts one use; false, with nothing counted, when the free plan has none left.
        mutating func consume(_ feature: Feature, isPro: Bool, on date: Date, calendar: Calendar) -> Bool {
            guard allows(feature, isPro: isPro, on: date, calendar: calendar) else { return false }
            if !isPro {
                let key = Self.key(feature, on: date, calendar: calendar)
                counts[key, default: 0] += 1
                // Earlier days and weeks are forgotten.
                let prefix = feature.rawValue + "|"
                counts = counts.filter { !$0.key.hasPrefix(prefix) || $0.key == key }
            }
            return true
        }
    }

    struct Product: Equatable {
        enum Kind: Equatable {
            case monthly
            case yearly
            case lifetime
        }

        var id: String
        var kind: Kind
        /// Shown until the App Store answers (and in builds not from the App Store).
        var fallbackPriceTR: String
        var fallbackPriceUS: String
        var fallbackAmountTR: Double
        var fallbackAmountUS: Double
    }

    static let products: [Product] = [
        Product(id: "murekkep.pro.monthly", kind: .monthly, fallbackPriceTR: "₺129,99", fallbackPriceUS: "$3.99",
                fallbackAmountTR: 129.99, fallbackAmountUS: 3.99),
        Product(id: "murekkep.pro.yearly", kind: .yearly, fallbackPriceTR: "₺899,99", fallbackPriceUS: "$24.99",
                fallbackAmountTR: 899.99, fallbackAmountUS: 24.99),
        Product(id: "murekkep.pro.lifetime", kind: .lifetime, fallbackPriceTR: "₺1.299,99", fallbackPriceUS: "$39.99",
                fallbackAmountTR: 1299.99, fallbackAmountUS: 39.99),
    ]

    static func product(_ kind: Product.Kind) -> Product {
        products.first { $0.kind == kind }!
    }

    /// How much less a year of Pro costs than twelve months of it, in whole percent.
    static func yearlySaving(monthly: Double, yearly: Double) -> Int {
        guard monthly > 0 else { return 0 }
        return max(0, Int((100 * (1 - yearly / (12 * monthly))).rounded(.down)))
    }

    /// Templates a student needs stay free; planners, CV and special papers are Pro.
    static func isPremium(template rawValue: String) -> Bool {
        ["isometric", "hexagon", "music", "todo", "daily", "weekly", "monthly", "meeting", "resume", "letter", "storyboard"]
            .contains(rawValue)
    }

    /// Apple's standard licence for apps without their own.
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}
