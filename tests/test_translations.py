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


def test_no_part_holds_a_text_twice():
    # A Swift dictionary literal with a key twice stops the app the first time it is read; the
    # parts are merged keeping the first, so a text may stand in two parts but never twice in one.
    text = (APP / "Translations.swift").read_text(encoding="utf-8")
    parts = re.split(r"private static let part\d+: \[String: String\] = \[", text)[1:]
    assert len(parts) >= 14
    for i, part in enumerate(parts, 1):
        keys = re.findall(r"^\s*" + LITERAL + r"\s*:", part, re.M)
        twice = sorted({k for k in keys if keys.count(k) > 1})
        assert not twice, (f"part{i}", twice)
    merged = re.search(r"for part in \[([^\]]+)\]", text).group(1)
    assert merged.count("part") == len(parts)


def test_every_ui_text_has_english():
    missing = sorted(keys_in_code() - translated())
    assert not missing, "\n".join(missing[:40])
