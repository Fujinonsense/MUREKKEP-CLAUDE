"""The assistant asks one thing, once: whether its searches may go to the web (1.1). Until the user
answers, the App Store edition sends nothing to Wikipedia or DuckDuckGo."""
import re
from pathlib import Path

APP = Path(__file__).resolve().parent.parent / "Murekkep.swiftpm"


def src(name):
    return (APP / name).read_text(encoding="utf-8")


def test_web_search_starts_off_in_the_app_store_edition_until_asked():
    settings = src("AppSettings.swift")
    assert '"webSearch": !ProPlan.sells,' in settings
    assert '"askedWebSearch": false,' in settings
    assert 'askedWebSearch = d.bool(forKey: "askedWebSearch")' in settings


def test_the_assistant_asks_once_when_it_opens():
    view = src("AssistantView.swift")
    appear = view[view.index(".onAppear {"):view.index("private func answerWebSearch")]
    assert "if !settings.askedWebSearch && settings.engine != .claude { askWebSearch = true }" in appear
    assert 'Loc.t("İnternette arama açılsın mı?"), isPresented: $askWebSearch' in appear
    assert 'Button(Loc.t("Aç")) { answerWebSearch(true) }' in appear
    assert 'Button(Loc.t("Kapalı kalsın"), role: .cancel) { answerWebSearch(false) }' in appear
    answer = view[view.index("private func answerWebSearch"):][:200]
    assert "settings.webSearch = on" in answer and "settings.askedWebSearch = true" in answer
    # Only one alert of this kind: no other consent screens were added to the assistant.
    assert len(re.findall(r"\.alert\(", view)) == 1


def test_the_privacy_policy_says_the_same():
    site = (APP.parent / "docs" / "site" / "privacy.html").read_text(encoding="utf-8")
    assert "The first time you open the assistant, it asks whether to turn on internet search" in site
    assert "Asistanı ilk açtığında internette aramanın açılıp açılmayacağını sana sorar" in site
