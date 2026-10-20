"""Gets every Google Fonts HANDWRITING family through a sparse git clone (no API rate limit).

usage: python fetch_fonts_git.py <data_dir>
"""
import json
import os
import shutil
import subprocess
import sys
import urllib.request

DATA = sys.argv[1]
FONTS = os.path.join(DATA, "fonts")
REPO = os.path.join(DATA, "google-fonts")
os.makedirs(FONTS, exist_ok=True)

raw = urllib.request.urlopen(urllib.request.Request("https://fonts.google.com/metadata/fonts",
                                                    headers={"User-Agent": "murekkep"}), timeout=60).read()
meta = json.loads(raw.decode("utf-8").lstrip(")]}'\n"))
families = [f for f in meta["familyMetadataList"] if f.get("category", "").upper() == "HANDWRITING"]
folders = sorted({f["family"].lower().replace(" ", "").replace("-", "") for f in families})
print("families:", len(families))

if not os.path.isdir(REPO):
    subprocess.run(["git", "-c", "core.longpaths=true", "clone", "-q", "--depth", "1", "--filter=blob:none", "--sparse",
                    "https://github.com/google/fonts.git", REPO], check=True)
paths = [f"{lic}/{name}" for name in folders for lic in ("ofl", "apache", "ufl")]
subprocess.run(["git", "-C", REPO, "sparse-checkout", "set", "--no-cone"] + paths, check=True)

index = []
for name in folders:
    for lic in ("ofl", "apache", "ufl"):
        d = os.path.join(REPO, lic, name)
        if not os.path.isdir(d):
            continue
        ttfs = sorted(x for x in os.listdir(d) if x.lower().endswith(".ttf"))
        ttfs.sort(key=lambda x: (0 if "Regular" in x or "[" in x else 1, x))
        got = []
        for x in ttfs[:2]:
            dest = os.path.join(FONTS, x)
            if not os.path.exists(dest):
                shutil.copy(os.path.join(d, x), dest)
            got.append(x)
        if got:
            index.append({"family": name, "license": lic, "files": got})
        break
json.dump(index, open(os.path.join(FONTS, "index.json"), "w"), indent=1)
print("families with fonts:", len(index), "files:", len(os.listdir(FONTS)) - 1)
