"""Every pen has a sound family, every family's bank has recordings in the asset catalog, and the
recordings are short, even and never clip (decoding needs miniaudio: run with --with miniaudio)."""
import json
import re
from pathlib import Path

import pytest

APP = Path(__file__).resolve().parent.parent / "Murekkep.swiftpm"
SOUND = (APP / "PaperSound.swift").read_text(encoding="utf-8")
ASSETS = APP / "Assets.xcassets"


def banks():
    m = re.search(r"static let banks = \[(.*?)\]", SOUND, re.S)
    return re.findall(r'"([^"]+)"', m.group(1))


def brush_cases():
    src = (APP / "Brushes.swift").read_text(encoding="utf-8")
    body = src.split("enum Brush:")[1].split("\n}\n")[0]
    return re.findall(r"^\s+case (\w+) = \d+", body, re.M)


def test_every_bank_has_recordings():
    for bank in banks():
        assert (ASSETS / f"{bank}-1.dataset").is_dir(), bank


def test_every_brush_has_a_family():
    mapping = SOUND.split("var soundFamily: SoundFamily {")[1].split("\n    }\n")[0]
    mapped = set(re.findall(r"\.(\w+)", "\n".join(line.split(": return")[0] for line in mapping.splitlines() if "case " in line)))
    assert set(brush_cases()) == mapped


def test_asset_folders_are_valid():
    for folder in ASSETS.glob("ses-*.dataset"):
        contents = json.loads((folder / "Contents.json").read_text(encoding="utf-8"))
        name = contents["data"][0]["filename"]
        assert (folder / name).is_file() and name == folder.name.replace(".dataset", ".mp3")
        assert (folder / name).stat().st_size < 80_000


def test_recordings_are_short_even_and_clean():
    miniaudio = pytest.importorskip("miniaudio")
    np = pytest.importorskip("numpy")
    for path in sorted(ASSETS.glob("ses-*.dataset/*.mp3")):
        d = miniaudio.decode_file(str(path), output_format=miniaudio.SampleFormat.FLOAT32, nchannels=1, sample_rate=44100)
        x = np.frombuffer(d.samples, dtype=np.float32)
        seconds = len(x) / 44100
        rms = float(np.sqrt((x.astype(np.float64) ** 2).mean()))
        assert 0.8 <= seconds <= 8, (path.name, seconds)
        assert 0.07 <= rms <= 0.15, (path.name, rms)
        assert np.abs(x).max() < 0.99, path.name
