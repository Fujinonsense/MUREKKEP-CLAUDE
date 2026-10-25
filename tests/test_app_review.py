"""What App Review checks in the App Store edition (ProPlan.sells), held in the source.

From the 2026-10-25 review audit: the 2–6 GB model must not come down before the user says so
(guideline 4.2.3), the Claude key must not ship (5.1.2, the app collects no data), the paywall may
only promise what exists and must show the billed price and period plainly (3.1.2), the privacy
policy needs a real link (5.1.1), AI answers need a way to report them (1.2)."""
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
