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


def test_the_assistant_scenes_ask_only_what_the_math_engine_answers():
    """The recording build has no language model (MUREKKEP_PLAIN): its scenes ask the assistant only
    what the math engine settles by itself, open the panel first, and wait for every answer."""
    player = (DEMO / "DemoPlayer.swift").read_text(encoding="utf-8")
    known = set(re.findall(r'case "([a-z.]+)":', player))
    assert {"assistant", "assistant.ask", "assistant.type", "assistant.wait", "convert"} <= known
    enum = (APP / "AssistantModel.swift").read_text(encoding="utf-8").split("enum QuickAction")[1].split("var id")[0]
    actions = set(re.findall(r"^\s*case (\w+)\s*$", enum, re.M))
    assert {"check", "solve"} <= actions
    asked = 0
    for path in SCENES:
        steps = json.loads(path.read_text(encoding="utf-8"))["steps"]
        ops = [s["op"] for s in steps]
        for i, step in enumerate(steps):
            if step["op"] in ("assistant.ask", "assistant.type"):
                asked += 1
                assert "assistant" in ops[:i], f"{path.name}: the panel opens before it is asked"
                assert ops[i + 1] == "assistant.wait", f"{path.name}: every question waits for its answer"
            if step["op"] == "assistant.ask":
                assert step["name"] in {"check", "solve"}, f"{path.name}: {step['name']} needs a language model"
            if step["op"] == "assistant.type":
                assert step["text"].strip(), path.name
    assert asked >= 3


def _make_scenes():
    pytest.importorskip("numpy")
    import importlib.util
    spec = importlib.util.spec_from_file_location("make_scenes", DEMO / "make_scenes.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _is_prose(line):
    """PageMath.isProse: two words of three letters or more, or one with a "?"."""
    words = [w for w in re.findall(r"[^\W\d_]+", line) if len(w) >= 3]
    return len(words) >= 2 or (len(words) == 1 and "?" in line)


def test_the_math_pages_hold_no_sentence():
    """A sentence on a math page sends it to the language model (PageMath.engineSettles); a typed
    question is answered by the engine only when it holds nothing but asking words (PageMath.question)."""
    text = _make_scenes().TEXT["en"]
    for key in ("check", "solve"):
        for line in [text[f"{key}.label"]] + text[f"{key}.lines"]:
            assert not _is_prose(line), line
    source = (APP / "PageMath.swift").read_text(encoding="utf-8")
    asking = set(re.findall(r'"([^"]+)"', source.split("askingWords: Set<String> = [")[1].split("]")[0]))
    for word in re.findall(r"[^\W\d_]+", text["solve.chat"]):
        assert len(word) == 1 or word.lower() in asking, word


def test_the_assistant_opens_in_recordings_without_the_web_question():
    """The panel asks about web search the first time it opens; the recordings answer "keep it off"
    before opening it, so no alert covers the page."""
    editor = (APP / "EditorView.swift").read_text(encoding="utf-8")
    block = next(b.split("#endif")[0] for b in editor.split("#if DEMO")[1:] if "assistantPanel" in b)
    assert "settings.askedWebSearch = true" in block and "settings.webSearch = false" in block
    assert block.index("settings.askedWebSearch = true") < block.index("showAssistant =")
    assert "DemoStage.shared.assistant = assistant" in block


def test_the_solution_check_counts_its_mistakes_in_both_languages():
    """The check's first line is on screen in the ads: one mistake is singular, more are plural."""
    source = (APP / "OfflineBrain.swift").read_text(encoding="utf-8")
    assert "mistake(s)" not in source
    assert '"Bir yerde hata var."' in source and '"There is 1 mistake."' in source
    assert '"There are \\(wrong) mistakes."' in source and '"\\(wrong) yerde hata var."' in source


def test_the_fonts_come_with_their_licence():
    assert (DEMO / "fonts" / "OFL.txt").exists()
    for font in ("EMSNeato.svg", "EMSTech.svg"):
        text = (DEMO / "fonts" / font).read_text(encoding="utf-8")
        assert "SIL Open Font License" in text
