"""Downloads the raw material for the handwriting recognizer.

- Every Google Fonts family in the HANDWRITING category (all are OFL or Apache licensed), as TTF
  files from the google/fonts GitHub repository.
- Turkish and English sentences from Tatoeba (CC-BY 2.0 FR).

usage: python fetch_data.py <data_dir>
"""
import bz2
import json
import os
import sys
import time
import urllib.request

DATA = sys.argv[1]
FONTS = os.path.join(DATA, "fonts")
TEXT = os.path.join(DATA, "text")
os.makedirs(FONTS, exist_ok=True)
os.makedirs(TEXT, exist_ok=True)
UA = {"User-Agent": "murekkep-handwriting-data/1.0"}


def get(url, tries=3):
    for i in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
                return r.read()
        except Exception as e:  # network hiccups: retry, then give up on this file
            if i == tries - 1:
                print("  failed:", url, e)
                return None
            time.sleep(2 * (i + 1))


# --- Fonts -------------------------------------------------------------------------------------
meta_raw = get("https://fonts.google.com/metadata/fonts")
meta = json.loads(meta_raw.decode("utf-8").lstrip(")]}'\n"))
families = [f for f in meta["familyMetadataList"] if f.get("category", "").upper() == "HANDWRITING"]
print("handwriting families:", len(families))
index = []
for f in families:
    name = f["family"]
    folder = name.lower().replace(" ", "")
    got = None
    for lic in ("ofl", "apache", "ufl"):
        listing = get(f"https://api.github.com/repos/google/fonts/contents/{lic}/{folder}", tries=1)
        if not listing:
            continue
        try:
            files = json.loads(listing)
        except Exception:
            continue
        ttfs = [x for x in files if x["name"].lower().endswith(".ttf")]
        # Regular weight first; variable fonts keep their axes in the name.
        ttfs.sort(key=lambda x: (0 if "Regular" in x["name"] or "[" in x["name"] else 1, x["name"]))
        for x in ttfs[:2]:
            dest = os.path.join(FONTS, x["name"])
            if not os.path.exists(dest):
                data = get(x["download_url"])
                if data:
                    open(dest, "wb").write(data)
            if os.path.exists(dest):
                got = got or []
                got.append(x["name"])
        if got:
            index.append({"family": name, "license": lic, "files": got, "subsets": f.get("subsets", [])})
            break
    time.sleep(0.2)
json.dump(index, open(os.path.join(FONTS, "index.json"), "w"), indent=1)
print("fonts downloaded:", len(index))

# --- Sentences ---------------------------------------------------------------------------------
for lang in ("tur", "eng"):
    dest = os.path.join(TEXT, f"{lang}_sentences.tsv")
    if os.path.exists(dest):
        continue
    raw = get(f"https://downloads.tatoeba.org/exports/per_language/{lang}/{lang}_sentences.tsv.bz2")
    if raw:
        open(dest, "wb").write(bz2.decompress(raw))
        print(lang, "sentences:", sum(1 for _ in open(dest, encoding="utf-8")))
print("done")
