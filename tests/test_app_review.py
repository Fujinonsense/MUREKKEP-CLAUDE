"""What App Review checks in the App Store edition (ProPlan.sells), held in the source.

From the 2026-10-25 review audit: the 2–6 GB model must not come down before the user says so
(guideline 4.2.3), the Claude key must not ship (5.1.2, the app collects no data), the paywall may
only promise what exists and must show the billed price and period plainly (3.1.2), the privacy
policy needs a real link (5.1.1), AI answers need a way to report them (1.2).

From the 1.1 purchase review: one plan the App Store did not give must not block the other two or
blame the connection, and a failed purchase is told in the app's words, not StoreKit's."""
import re
from pathlib import Path

APP = Path(__file__).resolve().parent.parent / "Murekkep.swiftpm"


def src(name):
    return (APP / name).read_text(encoding="utf-8")


def test_model_download_waits_for_the_user_in_the_app_store_edition():
    assert '"autoBrainDownload": !ProPlan.sells' in src("AppSettings.swift")
    cards = src("BrainViews.swift")
    # The download button asks first, with the size, in the App Store edition.
    assert "confirmDownload" in cards and "ProPlan.sells" in cards
    assert re.search(r'Loc\.t\("\{0\} indirilsin mi\?"', cards)
    assert "mobil veriyi de kullanır" in cards


def test_claude_key_is_left_out_of_the_app_store_edition():
    settings = src("AppSettings.swift")
    key = settings[settings.index("var apiKey: String?"):]
    assert "guard !ProPlan.sells else { return nil }" in key[:200]
    view = src("SettingsView.swift")
    assert re.search(r"if !ProPlan\.sells \{\s*claudeSection", view)
    assert re.search(r"if !ProPlan\.sells \{\s*Toggle\(isOn: \$settings\.handwritingAI\)", view)
    engine = src("AIEngine.swift")
    assert "!ProPlan.sells && (hasKey || current == .claude)" in engine
    assert "case .claude: return ProPlan.sells ? .deviceBrain : .claude" in engine
    assert "Anthropic" not in src("PaywallView.swift").split("static var paragraphs")[1].split("if !ProPlan.sells")[0]


def test_paywall_promises_only_backgrounds_that_exist():
    for name in ("PaywallView.swift", "SettingsView.swift"):
        text = src(name)
        for gone in ("Ebru", "İznik", "Boğaz", "ebru, İznik"):
            assert gone not in text, (name, gone)


def test_paywall_shows_the_billed_price_with_its_period():
    paywall = src("PaywallView.swift")
    assert 'Loc.t("{0}/yıl"' in paywall and 'Loc.t("{0}/ay"' in paywall
    # The trial line says what comes after it, in readable type next to the button.
    assert re.search(r'Loc\.t\("\{0\} gün ücretsiz, sonra yılda \{1\}"', paywall)
    assert "ProPlan.freeTrialDays" not in paywall
    store = src("ProStore.swift")
    assert "@Published private(set) var trialEligible = false" in store
    assert "paymentMode == .freeTrial" in store and "trialDays" in store
    # No prices from the App Store: say so and offer a retry, never fixed prices to buy.
    assert "pricesFailed" in store and 'Loc.t("Fiyatlar yüklenemedi.")' in paywall


def test_paywall_and_settings_link_the_privacy_policy():
    plan = src("ProPlan.swift")
    assert re.search(r'static let privacyURL = URL\(string: "https://[^"]+"\)!', plan)
    assert re.search(r'static let supportEmail = "[^"@]+@[^"]+"', plan)
    assert "Link(Loc.t(\"Gizlilik politikası\"), destination: ProPlan.privacyURL)" in src("PaywallView.swift")
    assert "ProPlan.privacyURL" in src("SettingsView.swift")


def test_an_ai_answer_can_be_reported():
    view = src("AssistantView.swift")
    assert 'Label(Loc.t("Bildir")' in view and "ProPlan.supportMail(" in view
    assert 'parts.scheme = "mailto"' in src("ProPlan.swift")
    assert "Zararlı" in src("AssistantModel.swift")


def test_every_plan_needs_its_app_store_price():
    # A plan the App Store did not return (say, not attached to the version) must not be sold at a
    # planned price; and nothing is for sale before the App Store answers.
    store = src("ProStore.swift")
    assert "func price(_ plan: ProPlan.Product) -> String?" in store
    assert "products[plan.id]?.displayPrice" in store
    assert "fallbackPrice" not in store and "fallbackAmount" not in store
    assert "var yearlySaving: Int?" in store
    paywall = src("PaywallView.swift")
    assert re.search(r"else if store\.products\.isEmpty \{\s*ProgressView\(\)", paywall)
    # The button only ever buys the chosen plan with its App Store price; the saving is claimed from
    # the App Store's prices alone.
    assert re.search(r"if let price = store\.price\(ProPlan\.product\(plan\)\) \{\s*purchase\(price\)", paywall)
    assert "if let saving = store.yearlySaving, saving > 0" in paywall


def test_one_missing_plan_does_not_block_the_others():
    # The full "prices couldn't load" state is for when none came; a plan missing on its own is shown
    # as unavailable, with a neutral note instead of a price, and cannot be chosen.
    store = src("ProStore.swift")
    assert "pricesFailed = products.isEmpty" in store
    assert "pricesFailed = ProPlan.products.contains" not in store
    paywall = src("PaywallView.swift")
    assert 'Text(Loc.t("Şu anda alınamıyor"))' in paywall
    assert "let chosen = plan == kind && price != nil" in paywall
    assert ".disabled(price == nil)" in paywall
    # The chosen plan moves to one the App Store gave, on opening and whenever the products change.
    assert ".onChange(of: store.products, initial: true) { _, _ in keepPlanSellable() }" in paywall
    assert re.search(r"guard store\.price\(ProPlan\.product\(plan\)\) == nil,\s*let first = Self\.shown\.first", paywall)


def test_the_subscriptions_lead_and_the_one_time_purchase_is_a_line_under_them():
    # Lifetime as a third card of the same size looked cheap. It stays for those who would rather not
    # subscribe: a line with its App Store price under the two cards, gone when the store lacks it.
    paywall = src("PaywallView.swift")
    assert "private static let cards: [ProPlan.Product.Kind] = [.yearly, .monthly]" in paywall
    assert "ForEach(Self.cards, id: \\.self)" in paywall and "ForEach(Self.shown" not in paywall
    line = paywall.split("private var lifetimeLine")[1].split("\n    }\n")[0]
    assert "if let price = store.price(ProPlan.product(.lifetime))" in line
    assert 'Loc.t("Abonelik istemezsen: ömür boyu Pro, tek ödeme {0}", price)' in line
    assert "minHeight: 44" in line and ".isSelected" in line


def test_purchase_errors_are_told_in_the_apps_words():
    # StoreKit's texts are English and technical: the raw error goes to the log only, and the common
    # cases get a line of their own. Cancelling says nothing; Ask to Buy is waiting, not failing.
    store = src("ProStore.swift")
    purchase = store[store.index("func purchase("):store.index("func restore(")]
    assert "localizedDescription" not in purchase
    assert re.search(r'print\("Mürekkep: purchase of \\\(id\) failed: \\\(error\)"\)', purchase)
    assert "message = Self.friendly(error)" in purchase
    friendly = purchase[purchase.index("static func friendly("):]
    assert re.search(r"case \.userCancelled:\s*return nil", friendly)
    assert re.search(r"case \.networkError:\s*return network", friendly)
    assert 'let network = Loc.t("İnternet bağlantını kontrol edip yeniden dene.")' in friendly
    assert "case .purchaseNotAllowed:" in friendly and "case .productUnavailable:" in friendly
    assert "case .notAvailableInStorefront:" in friendly
    assert re.search(r'return Loc\.t\("Satın alma tamamlanamadı\. Biraz sonra yeniden dene\."\)\s*\}', friendly)
    assert re.search(r'case \.pending:\s*message = Loc\.t\("Satın alma onay bekliyor', purchase)


def test_no_claude_text_in_the_app_store_edition():
    player = src("OverviewPlayer.swift")
    line = next(l for l in player.splitlines() if "I need Claude" in l)
    assert "if ProPlan.sells" in player.split("I need Claude")[0][-400:], line
