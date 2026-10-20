"""Reads the pen sections straight from Brushes.swift (the source of the pen panel)."""
import os
import re
from pathlib import Path

SOURCE = Path(os.environ.get("BRUSHES_SWIFT", Path(__file__).parent.parent / "Murekkep.swiftpm" / "Brushes.swift"))


def swift():
    return SOURCE.read_text(encoding="utf-8")


def all_brushes():
    body = swift().split("enum Brush:")[1]
    return re.findall(r"^\s+case (\w+) = \d+", body, re.M)


def sections():
    body = swift().split("var group: BrushGroup {")[1].split("\n    }\n")[0]
    out = {}
    for names, group in re.findall(r"case ([.\w, ]+): return \.(\w+)", body):
        out[group] = [n.strip().lstrip(".") for n in names.split(",")]
    return out


def palette_order():
    body = swift().split("static let paletteOrder: [Brush] = [")[1].split("]")[0]
    return re.findall(r"\.(\w+)", body)


def test_four_sections_cover_every_pen_once():
    s = sections()
    assert list(s) == ["writing", "paint", "nature", "shine"]
    names = [b for group in s.values() for b in group]
    assert sorted(names) == sorted(all_brushes())


def test_lava_galaxy_and_lightning_are_nature():
    nature = sections()["nature"]
    for b in ["sea", "wave", "grass", "lava", "ice", "lightning", "galaxy"]:
        assert b in nature


def test_panel_order_follows_the_sections():
    s = sections()
    assert palette_order() == [b for group in s.values() for b in group]
