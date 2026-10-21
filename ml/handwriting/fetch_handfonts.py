"""Downloads the handwriting fonts the font-image generator (font_lines.py) writes with, from the
google/fonts repository on GitHub, into MRK_DATA/handfonts. Every .ttf of each family is taken
(variable fonts included); a family's Turkish coverage (ç ğ ı İ ö ş ü and capitals) is checked from
its character map and stored in handfonts.json, so Turkish text is only ever written with fonts that
can draw it.

usage: python fetch_handfonts.py"""
import json
import os
import time
import urllib.request
from pathlib import Path

from fontTools.ttLib import TTFont

DATA = Path(os.environ.get("MRK_DATA", "C:/Users/orsyu/mrk-ml/data"))
OUT = DATA / "handfonts"
API = "https://api.github.com/repos/google/fonts/contents/ofl/{}"

# Family folder in google/fonts/ofl → what it is meant for.
FAMILIES = {
    # Turkish and English (latin-ext)
    "shantellsans": "tr+en",
    "playpensans": "tr+en",
    "caveat": "tr+en",
    "mynerve": "tr+en",
    "delicioushandrawn": "tr+en",
    "patrickhand": "tr+en",
    "kalam": "tr+en",
    "shadowsintolighttwo": "tr+en",
    # English
    "reeniebeanie": "en",
    "cedarvillecursive": "en",
    "gloriahallelujah": "en",
    "indieflower": "en",
}
TURKISH = "çğıİöşüÇĞÖŞÜ"


def get(url, attempts=4):
    for k in range(attempts):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "murekkep-fonts"})
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read()
        except Exception:
            if k == attempts - 1:
                raise
            time.sleep(2 * (k + 1))


def turkish_ok(path):
    cmap = TTFont(str(path), lazy=True).getBestCmap() or {}
    return all(ord(c) in cmap for c in TURKISH)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    table = {}
    for family, use in FAMILIES.items():
        listing = json.loads(get(API.format(family)))
        files = [f for f in listing if f["name"].lower().endswith(".ttf")]
        got = []
        for f in files:
            target = OUT / f["name"]
            if not target.exists() or target.stat().st_size != f["size"]:
                target.write_bytes(get(f["download_url"]))
            got.append(f["name"])
        tr = all(turkish_ok(OUT / n) for n in got) if got else False
        table[family] = {"files": got, "meant": use, "turkish": tr}
        print(f"{family:22} {len(got)} file(s), Turkish {'yes' if tr else 'no'}")
    (OUT / "handfonts.json").write_text(json.dumps(table, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()
