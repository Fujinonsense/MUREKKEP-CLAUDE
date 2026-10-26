"""The Codemagic TestFlight build (codemagic.yaml), generated from the GitHub workflow."""
import subprocess
import sys
from pathlib import Path

import pytest

yaml = pytest.importorskip("yaml")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import make_codemagic  # noqa: E402


@pytest.fixture(scope="module")
def flow():
    return yaml.safe_load((ROOT / "codemagic.yaml").read_text(encoding="utf-8"))["workflows"]["appstore-testflight"]


def test_codemagic_yaml_is_up_to_date_with_the_github_workflow():
    assert (ROOT / "codemagic.yaml").read_text(encoding="utf-8") == make_codemagic.render()


def test_the_pdfkit_probe_is_short_and_needs_no_keys():
    probe = yaml.safe_load((ROOT / "codemagic.yaml").read_text(encoding="utf-8"))["workflows"]["pdfkit-probe"]
    assert probe["instance_type"] == "mac_mini_m2" and probe["max_build_duration"] <= 15
    assert "groups" not in probe["environment"]
    body = probe["scripts"][0]["script"]
    assert "tools/pdfkit_probe/main.swift" in body and "tests/fixtures/calculus_p14.pdf" in body
    assert (ROOT / "tests" / "fixtures" / "calculus_p14.pdf").exists()


def test_runs_on_the_free_m2_mac_within_the_limit(flow):
    assert flow["instance_type"] == "mac_mini_m2"
    assert flow["max_build_duration"] <= 120
    env = flow["environment"]
    assert env["vars"] == {"EDITION": "appstore", "TESTFLIGHT": "yes"}
    assert env["groups"] == ["app_store_credentials"]


def test_checks_the_key_first_and_uploads_last(flow):
    names = [s["name"] for s in flow["scripts"]]
    assert names[0] == "App Store Anahtarini Dogrula" and names[-1] == "TestFlight'a Yukle"
    body = {s["name"]: s["script"] for s in flow["scripts"]}
    assert "--check-api" in body["App Store Anahtarini Dogrula"]
    assert "-exportArchive" in body["TestFlight'a Yukle"]
    # No separate release build: the upload archives the app itself.
    assert not any("tee build.log" in s["script"] for s in flow["scripts"])
    assert body["Xcode Projesini Uret"].rstrip().endswith("xcodegen generate --spec project.yml")


def test_every_script_maps_codemagic_names_to_githubs(flow):
    for s in flow["scripts"]:
        assert s["script"].startswith(make_codemagic.PRELUDE), s["name"]
    assert "$APP_STORE_CONNECT_PRIVATE_KEY" in make_codemagic.PRELUDE
    # Build numbers stay above GitHub's uploads (build 109 is on TestFlight).
    out = subprocess.run(["bash", "-c", make_codemagic.PRELUDE + 'echo "$GITHUB_RUN_NUMBER"'],
                         capture_output=True, text=True, env={"BUILD_NUMBER": "1", "PATH": "/usr/bin:/bin"})
    assert 100 + int(out.stdout.strip()) > 109


def test_xcode_is_pinned(flow):
    assert flow["environment"]["xcode"] == make_codemagic.XCODE == "26.5"


def test_shaders_are_compiled_before_the_upload(flow):
    names = [s["name"] for s in flow["scripts"]]
    assert names.index("Murekkep Shaderlarini Derle") < names.index("TestFlight'a Yukle")
    step = next(s for s in flow["scripts"] if s["name"] == "Murekkep Shaderlarini Derle")
    assert "python3 tools/metal_check.py" in step["script"] and "ignore_failure" not in step


def test_voice_engine_is_built_only_without_the_cache(flow):
    sherpa = next(s for s in flow["scripts"] if s["name"].startswith("Gomulu Ses Motorunu"))
    assert "if [ -d sherpa-out/sherpa-onnx.xcframework ]; then" in sherpa["script"]
    assert "$CM_BUILD_DIR/sherpa-out" in flow["cache"]["cache_paths"]


def test_scripts_parse_as_bash(flow, tmp_path):
    for s in flow["scripts"]:
        f = tmp_path / "s.sh"
        f.write_bytes(s["script"].encode("utf-8"))
        r = subprocess.run(["bash", "-n", str(f)], capture_output=True, text=True)
        assert r.returncode == 0, (s["name"], r.stderr)
