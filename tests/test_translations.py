"""Every Turkish interface text passed to Loc.t has its English entry in Translations.swift."""
import re
from pathlib import Path

APP = Path(__file__).resolve().parent.parent / "Murekkep.swiftpm"
LITERAL = r'"((?:[^"\\]|\\.)*)"'


def keys_in_code():
    keys = set()
    for f in APP.glob("*.swift"):
        if f.name == "Translations.swift":
            continue
        keys |= set(re.findall(r"Loc\.t\(\s*" + LITERAL, f.read_text(encoding="utf-8")))
    return {k for k in keys if re.search(r"[A-Za-zÇĞİÖŞÜçğıöşü]", k) and "\\(" not in k}


def translated():
    text = (APP / "Translations.swift").read_text(encoding="utf-8")
    return set(re.findall(r"^\s*" + LITERAL + r"\s*:", text, re.M))


def test_every_ui_text_has_english():
    missing = sorted(keys_in_code() - translated())
    assert not missing, "\n".join(missing[:40])
