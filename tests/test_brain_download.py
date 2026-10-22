"""Qwen3.5 downloads on any internet the iPad has: Wi-Fi, mobile data, a phone's hotspot (an
"expensive" network to iOS) and Low Data Mode (a "constrained" one). The user asked for it."""
import re
from pathlib import Path

APP = Path(__file__).resolve().parent.parent / "Murekkep.swiftpm"


def test_background_session_uses_every_network():
    code = (APP / "DeviceBrain.swift").read_text(encoding="utf-8")
    session = code.split("URLSessionConfiguration.background(withIdentifier:", 1)[1].split("return URLSession(", 1)[0]
    assert "configuration.allowsExpensiveNetworkAccess = true" in session
    assert "configuration.allowsConstrainedNetworkAccess = true" in session
    assert "allowsCellularAccess = false" not in session


def test_download_texts_do_not_promise_wifi_only():
    for name in ["SettingsView.swift", "BrainViews.swift", "DeviceBrain.swift"]:
        code = (APP / name).read_text(encoding="utf-8")
        texts = re.findall(r'Loc\.t\("((?:[^"\\]|\\.)*)"', code)
        # "Paylaşılan internet" and the like may name Wi-Fi among the networks; a Wi-Fi-only promise
        # reads "Wi-Fi'de" / "Wi-Fi'ye" / "Wi-Fi önerilir".
        wifi = [t for t in texts if re.search(r"Wi.Fi('de|'ye| önerilir)", t)]
        assert not wifi, (name, wifi)
