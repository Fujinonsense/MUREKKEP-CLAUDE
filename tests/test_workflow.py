"""The IPA workflow: macOS 26 with Xcode 26.6 (so Apple's on-device model compiles in), sherpa-onnx
built once and cached, the Supertonic voices bundled as a folder, and a plain second build when the
first one fails so the user always gets an IPA."""
import re
from pathlib import Path

import pytest

yaml = pytest.importorskip("yaml")

WORKFLOW = Path(__file__).resolve().parent.parent / ".github" / "workflows" / "main.yml"


@pytest.fixture(scope="module")
def job():
    return yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))["jobs"]["build-ipa"]


def runs(job):
    return "\n".join(s.get("run", "") for s in job["steps"])


def step_with(job, text):
    found = [s for s in job["steps"] if text in s.get("run", "") or text in str(s.get("uses", ""))]
    assert found, f"no step contains {text!r}"
    return found[0]


def test_runs_on_macos_26(job):
    assert job["runs-on"] == "macos-26"
    assert "sudo xcode-select -s /Applications/Xcode_26.6.app" in runs(job)


def test_sherpa_built_and_cached(job):
    cache = step_with(job, "actions/cache@v4")
    key = cache["with"]["key"]
    assert "1.13.8" in key and "1.28.2" in key
    script = runs(job)
    assert "--branch v1.13.8" in script
    assert "-DPLATFORM=OS64" in script
    assert "-DSHERPA_ONNX_ENABLE_C_API=ON" in script
    assert "Modules/module.modulemap" in script
    assert "framework module SherpaOnnxC" in script
    assert "xcodebuild -create-xcframework" in script
    build = step_with(job, "-DPLATFORM=OS64")
    assert "cache-hit" in str(build.get("if", ""))


def test_voices_bundled(job):
    script = runs(job)
    assert ("https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/"
            "sherpa-onnx-supertonic-3-tts-int8-2026-05-11.tar.bz2") in script
    assert "AppVoices/supertonic3" in script
    assert "path: AppSource/AppVoices" in script
    assert "type: folder" in script
    assert "buildPhase: resources" in script


def test_frameworks_linked(job):
    script = runs(job)
    assert "framework: Frameworks/sherpa-onnx.xcframework" in script
    assert "framework: Frameworks/onnxruntime.xcframework" in script
    assert script.count("embed: false") >= 2
    assert "OTHER_LDFLAGS" in script and "-lc++" in script


def test_fallback_build(job):
    first = [s for s in job["steps"] if s.get("id") == "build"]
    assert first and first[0].get("continue-on-error") is True
    fallback = [s for s in job["steps"] if "steps.build.outcome == 'failure'" in str(s.get("if", ""))]
    assert fallback, "no fallback build step"
    text = "\n".join(s.get("run", "") for s in fallback)
    assert "project-plain.yml" in text
    assert "::warning::" in text
    plain = runs(job).split("project-plain.yml", 1)[1].split("EOF", 1)[0]
    assert "sherpa-onnx.xcframework" not in plain
    # The plain build also leaves out Apple's on-device model code (it is the one most likely to break).
    assert "MUREKKEP_PLAIN" in plain


def test_liquid_glass_off(job):
    assert re.search(r"<key>UIDesignRequiresCompatibility</key>\s*<true/>", runs(job))
