"""Turns the generated background artwork (one square PNG per background) into the app's asset
catalog entries: bg-<name> (2752 px JPEG for the library: the long side of a 13-inch iPad Pro, so
the picture is never enlarged) and bg-<name>-thumb (320 px for the
Settings tiles), plus a contact sheet to look at. Every <name>.png in the folder becomes one
background; artwork in the catalog that is no longer in the folder is removed, unless --keep is
given (then the folder's pictures are only added or replaced: for a few new themes when the older
source pictures are not at hand).

    python tools/make_backgrounds.py [--keep] <folder with glass.png, silk.png, ...> [contact-sheet.png]
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Murekkep.swiftpm" / "Assets.xcassets" / "Backgrounds"
FULL = 2752
THUMB = 320


def imageset(name, image, quality):
    folder = CATALOG / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.glob("*.jpg"):
        old.unlink()
    image.save(folder / f"{name}.jpg", "JPEG", quality=quality, optimize=True, progressive=True)
    contents = {"images": [{"filename": f"{name}.jpg", "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8", newline="\n")


def main(source, sheet=None, keep=False):
    CATALOG.mkdir(parents=True, exist_ok=True)
    (CATALOG / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n",
                                           encoding="utf-8", newline="\n")
    names = sorted(f.stem for f in Path(source).glob("*.png"))
    if not keep:
        for old in CATALOG.glob("bg-*.imageset"):
            if old.name.removesuffix(".imageset").removeprefix("bg-").removesuffix("-thumb") not in names:
                for f in old.iterdir():
                    f.unlink()
                old.rmdir()
    thumbs = []
    for name in names:
        art = Image.open(Path(source) / f"{name}.png").convert("RGB")
        side = min(art.size)
        art = art.crop(((art.width - side) // 2, (art.height - side) // 2, (art.width + side) // 2, (art.height + side) // 2))
        full = art if side >= FULL else art.resize((FULL, FULL), Image.LANCZOS).filter(
            ImageFilter.UnsharpMask(radius=1.2, percent=40, threshold=2))
        if side > FULL:
            full = art.resize((FULL, FULL), Image.LANCZOS)
        thumb = art.resize((THUMB, THUMB), Image.LANCZOS)
        imageset(f"bg-{name}", full, 90)
        imageset(f"bg-{name}-thumb", thumb, 84)
        thumbs.append((name, thumb))
        print(name, f"{(CATALOG / f'bg-{name}.imageset' / f'bg-{name}.jpg').stat().st_size // 1024} KB")
    if sheet:
        cols = 5
        board = Image.new("RGB", (cols * (THUMB + 12) + 12, 2 * (THUMB + 12) + 12), (24, 26, 32))
        for i, (_, thumb) in enumerate(thumbs):
            board.paste(thumb, (12 + (i % cols) * (THUMB + 12), 12 + (i // cols) * (THUMB + 12)))
        board.save(sheet)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--keep"]
    main(args[0], args[1] if len(args) > 1 else None, keep="--keep" in sys.argv[1:])
