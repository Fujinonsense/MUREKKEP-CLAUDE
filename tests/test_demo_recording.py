"""The ad recordings (tools/demo): a DEMO-only player that the App Store edition never compiles, the
scenes it plays (the app in English, the notebook in English and Turkish), and the Codemagic job that
films them on a simulator."""
import json
import re
from pathlib import Path

import pytest

yaml = pytest.importorskip("yaml")

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "Murekkep.swiftpm"
DEMO = ROOT / "tools" / "demo"
SCENES = sorted((DEMO / "scenes").glob("DemoScene-*.json"))


def workflows():
    return yaml.safe_load((ROOT / "codemagic.yaml").read_text(encoding="utf-8"))["workflows"]


def test_the_app_store_build_never_gets_the_demo():
    testflight = json.dumps(workflows()["appstore-testflight"])
    assert "tools/demo" not in testflight and "DEMO" not in testflight
    assert not list(APP.glob("Demo*.swift")), "the player lives in tools/demo, outside the app's sources"


def test_every_demo_hook_in_the_app_is_behind_the_flag():
    for path in APP.glob("*.swift"):
        lines = path.read_text(encoding="utf-8").splitlines()
        depth, opened = 0, 0
        for n, line in enumerate(lines, 1):
            s = line.strip()
            if s == "#if DEMO":
                depth += 1
                opened += 1
            elif s.startswith("#if"):
                depth += 0  # other flags may nest inside; only DEMO is counted
            elif s == "#endif" and depth:
                # The #endif closes DEMO when no other #if opened after it on the way.
                depth -= 1
            if re.search(r"\bDemoStage\b|\bDemoClock\b|\bdemoPen|\bdemoWindowPoint|\bdemoFrame\b", line):
                assert depth > 0, f"{path.name}:{n} uses the demo outside #if DEMO"
        assert depth == 0, f"{path.name}: an #if DEMO is never closed"


def test_the_recording_job_films_the_listed_scenes_once():
    flow = workflows()["demo-kayit"]
    assert flow["instance_type"] == "mac_mini_m2" and flow["max_build_duration"] <= 60
    assert "groups" not in flow["environment"], "no keys: nothing is uploaded"
    body = "\n".join(s["script"] for s in flow["scripts"])
    assert "cp tools/demo/DemoPlayer.swift AppSource/" in body
    assert "MUREKKEP_PLAIN APPSTORE DEMO" in body and "-sdk iphonesimulator" in body
    assert "tools/demo/record.sh" in body
    # A run films what tools/demo/film.txt lists: every one a scene, the app in English.
    filmed = [l.strip() for l in (DEMO / "film.txt").read_text(encoding="utf-8").splitlines()
              if l.strip() and not l.startswith("#")]
    names = {p.stem.removeprefix("DemoScene-") for p in SCENES} - {"warmup"}
    assert filmed and set(filmed) <= names
    # One video for everyone: no scene in two languages.
    scenes = [n.rsplit("-", 1)[0] for n in names]
    assert len(scenes) == len(set(scenes)) and all(n.endswith("-en") for n in names)
    assert (DEMO / "record.sh").read_bytes().count(b"\r\n") == 0, "bash on the Mac needs LF line ends"
    assert (DEMO / "film.txt").read_bytes().count(b"\r\n") == 0


def test_scenes_use_only_steps_the_player_knows():
    player = (DEMO / "DemoPlayer.swift").read_text(encoding="utf-8")
    known = set(re.findall(r'case "([a-z.]+)":', player))
    assert {"note", "pen", "textpen", "write", "wait", "games", "layer", "game"} <= known
    enum = (APP / "GameCorner.swift").read_text(encoding="utf-8").split("enum MiniGame")[1]
    games = {g.strip() for g in re.search(r"case ([\w, ]+)\n", enum).group(1).split(",")}
    for path in SCENES:
        steps = json.loads(path.read_text(encoding="utf-8"))["steps"]
        assert steps[0]["op"] == "note", path.name
        for step in steps:
            assert step["op"] in known, f"{path.name}: {step['op']}"
            if step["op"] == "game":
                assert step["name"] in games, step["name"]
            for stroke in step.get("strokes", []):
                times = [s[0] for s in stroke]
                assert times == sorted(times) and all(len(s) == 4 for s in stroke), path.name


def test_the_pen_stays_on_the_page_and_writes_at_a_hands_pace():
    for path in SCENES:
        for step in json.loads(path.read_text(encoding="utf-8"))["steps"]:
            if step["op"] != "write":
                continue
            for stroke in step["strokes"]:
                for t, x, y, force in stroke:
                    assert 0 <= x <= 595.28 and 0 <= y <= 841.89, path.name
                    assert 0.1 <= force <= 2.0
                if len(stroke) > 1:
                    length = sum(((b[1] - a[1]) ** 2 + (b[2] - a[2]) ** 2) ** 0.5 for a, b in zip(stroke, stroke[1:]))
                    speed = length / max(stroke[-1][0] - stroke[0][0], 1e-3)
                    # Points a second; the warm-up is quick on purpose.
                    assert speed < (900 if "warmup" in path.name else 480), (path.name, speed)


def test_the_fonts_come_with_their_licence():
    assert (DEMO / "fonts" / "OFL.txt").exists()
    for font in ("EMSNeato.svg", "EMSTech.svg"):
        text = (DEMO / "fonts" / font).read_text(encoding="utf-8")
        assert "SIL Open Font License" in text
