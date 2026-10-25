import StoreKit
import SwiftUI
import UIKit

/// Mürekkep Pro in the App Store edition (StoreKit 2): the plans' prices, the purchase, whether Pro is
/// active, and the free plan's daily and weekly allowances (ProPlan). The personal build (without the
/// APPSTORE flag) sells nothing and has everything open.
@MainActor
final class ProStore: ObservableObject {
    static let shared = ProStore()

    static let sells = ProPlan.sells
    /// Planned prices are in lira in Turkey and in dollars elsewhere, until the App Store answers.
    private static let inTurkey = Locale.current.region?.identifier == "TR"

    @Published private(set) var isPro: Bool
    /// The App Store's products by id; empty until it answers (or outside the App Store).
    @Published private(set) var products: [String: Product] = [:]
    /// True when the App Store could not give the prices; the Pro page then says so instead of
    /// showing plans that cannot be bought.
    @Published private(set) var pricesFailed = false
    /// Only when the yearly plan has a free trial in App Store Connect and this account may still use it.
    @Published private(set) var trialEligible = false
    /// The free trial's length, from the App Store's offer.
    @Published private(set) var trialDays = ProPlan.freeTrialDays
    @Published private(set) var purchasing = false
    @Published var message: String?
    @Published private(set) var usage: ProPlan.Usage

    private var updates: Task<Void, Never>?
    private let calendar: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = .current
        return c
    }()

    private static let usageKey = "proUsage"
    private static let cacheKey = "proActiveCache"

    private init() {
        let d = UserDefaults.standard
        isPro = !Self.sells || d.bool(forKey: Self.cacheKey)
        usage = (d.data(forKey: Self.usageKey)).flatMap { try? JSONDecoder().decode(ProPlan.Usage.self, from: $0) } ?? ProPlan.Usage()
        guard Self.sells else { return }
        updates = Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case let .verified(transaction) = result {
                    await transaction.finish()
                }
                await self?.updateEntitlements()
            }
        }
        Task { await refresh() }
    }

    // MARK: The App Store

    func refresh() async {
        guard Self.sells else { return }
        if let loaded = try? await Product.products(for: ProPlan.products.map(\.id)) {
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            if let yearly = products[ProPlan.product(.yearly).id], let subscription = yearly.subscription,
               let offer = subscription.introductoryOffer, offer.paymentMode == .freeTrial {
                trialDays = Self.days(offer.period)
                trialEligible = await subscription.isEligibleForIntroOffer
            } else {
                trialEligible = false
            }
        }
        pricesFailed = products.isEmpty
        await updateEntitlements()
    }

    func updateEntitlements() async {
        guard Self.sells else { return }
        var active = false
        for await result in Transaction.currentEntitlements {
            if case let .verified(transaction) = result, transaction.revocationDate == nil,
               ProPlan.products.contains(where: { $0.id == transaction.productID }) {
                active = true
            }
        }
        isPro = active
        UserDefaults.standard.set(active, forKey: Self.cacheKey)
    }

    func purchase(_ id: String) async {
        guard let product = products[id] else {
            message = Loc.t("Satın alma, Mürekkep App Store'dan yüklendiğinde çalışır.")
            return
        }
        purchasing = true
        defer { purchasing = false }
        do {
            switch try await product.purchase() {
            case let .success(verification):
                if case let .verified(transaction) = verification {
                    await transaction.finish()
                    await updateEntitlements()
                } else {
                    message = Loc.t("Satın alma doğrulanamadı. Biraz sonra \"Geri yükle\"yi dene.")
                }
            case .pending:
                message = Loc.t("Satın alma onay bekliyor (Aile Paylaşımı ya da ödeme onayı).")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func restore() async {
        guard Self.sells else { return }
        try? await AppStore.sync()
        await updateEntitlements()
        message = isPro ? Loc.t("Mürekkep Pro geri yüklendi.") : Loc.t("Bu Apple hesabında Mürekkep Pro bulunamadı.")
    }

    func manageSubscription() async {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        try? await AppStore.showManageSubscriptions(in: scene)
    }

    /// The App Store's price of a plan, or the planned price until it answers.
    func price(_ plan: ProPlan.Product) -> String {
        if let product = products[plan.id] { return product.displayPrice }
        return Self.inTurkey ? plan.fallbackPriceTR : plan.fallbackPriceUS
    }

    private static func days(_ period: Product.SubscriptionPeriod) -> Int {
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return ProPlan.freeTrialDays
        }
    }

    /// How much less the yearly plan costs than twelve months, in whole percent.
    var yearlySaving: Int {
        let monthly = ProPlan.product(.monthly)
        let yearly = ProPlan.product(.yearly)
        if let m = products[monthly.id], let y = products[yearly.id] {
            return ProPlan.yearlySaving(monthly: NSDecimalNumber(decimal: m.price).doubleValue,
                                        yearly: NSDecimalNumber(decimal: y.price).doubleValue)
        }
        return Self.inTurkey
            ? ProPlan.yearlySaving(monthly: monthly.fallbackAmountTR, yearly: yearly.fallbackAmountTR)
            : ProPlan.yearlySaving(monthly: monthly.fallbackAmountUS, yearly: yearly.fallbackAmountUS)
    }

    // MARK: The free plan

    func remaining(_ feature: ProPlan.Feature) -> Int {
        usage.remaining(feature, on: Date(), calendar: calendar)
    }

    /// Counts `count` uses of a limited feature (one video per chapter). With too few left on the free
    /// plan, nothing is counted, the Pro page opens and the answer is false.
    @discardableResult
    func use(_ feature: ProPlan.Feature, count: Int = 1) -> Bool {
        guard Self.sells, !isPro else { return true }
        let now = Date()
        guard usage.remaining(feature, on: now, calendar: calendar) >= count else {
            Paywall.present(reason: feature)
            return false
        }
        for _ in 0..<count {
            _ = usage.consume(feature, isPro: false, on: now, calendar: calendar)
        }
        if let data = try? JSONEncoder().encode(usage) {
            UserDefaults.standard.set(data, forKey: Self.usageKey)
        }
        return true
    }

    /// How much of the nature pens' trial ink is left, 0...1 (1 with Pro or in the personal build).
    var trialInkLeft: Double {
        guard locks else { return 1 }
        return Double(usage.inkLeft()) / Double(ProPlan.trialInk)
    }

    /// Whether a nature pen may draw; with its trial ink gone the Pro page opens and the answer is false.
    func allowsTrialInk() -> Bool {
        guard locks, usage.inkLeft() == 0 else { return true }
        Paywall.present(reason: .trialInk)
        return false
    }

    /// Counts a finished nature-pen stroke against the trial; the stroke that empties it opens the Pro page.
    func spendTrialInk(points length: Double) {
        guard locks else { return }
        _ = usage.spendInk(Int(length.rounded()), isPro: false)
        if let data = try? JSONEncoder().encode(usage) {
            UserDefaults.standard.set(data, forKey: Self.usageKey)
        }
        if usage.inkLeft() == 0 {
            Paywall.present(reason: .trialInk)
        }
    }

    /// Whether a Pro-only thing may be used; without Pro the Pro page opens and the answer is false.
    func unlock(_ feature: ProPlan.Feature) -> Bool {
        guard Self.sells, !isPro else { return true }
        Paywall.present(reason: feature)
        return false
    }

    /// Whether to show a lock on a Pro-only thing.
    var locks: Bool { Self.sells && !isPro }
}

/// Opens the Pro page over whatever is on screen (the library, the editor, a sheet, the pen panel).
/// While a sheet or popover is still opening or closing, iOS refuses a new one without a word, so
/// the page waits for the animation to end and tries again (for up to two seconds).
enum Paywall {
    @MainActor
    static func present(reason: ProPlan.Feature? = nil, attempt: Int = 0) {
        guard ProStore.sells, let top = topViewController(), !(top is PaywallHost) else { return }
        if top.isBeingPresented || top.isBeingDismissed || top.transitionCoordinator != nil
            || top.presentedViewController?.isBeingDismissed == true {
            guard attempt < 20 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                present(reason: reason, attempt: attempt + 1)
            }
            return
        }
        let host = PaywallHost(reason: reason)
        host.modalPresentationStyle = .formSheet
        host.preferredContentSize = CGSize(width: 620, height: 860)
        top.present(host, animated: true)
    }

    /// The controller in front: the last one presented that is not on its way out.
    @MainActor
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first
        var top = window?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed {
            top = next
        }
        return top
    }
}

/// The Pro page in a UIKit sheet, so it opens from anywhere.
final class PaywallHost: UIHostingController<PaywallView> {
    init(reason: ProPlan.Feature?) {
        let closer = Closer()
        super.init(rootView: PaywallView(reason: reason, close: { closer.close() }))
        closer.host = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    private final class Closer {
        weak var host: UIViewController?

        @MainActor
        func close() {
            host?.dismiss(animated: true)
        }
    }
}
