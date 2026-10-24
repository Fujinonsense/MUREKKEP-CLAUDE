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
    assert job["runs-on"] == "${{ inputs.runner || 'macos-26' }}"
    assert "sudo xcode-select -s /Applications/Xcode_26.6.app" in runs(job)


def test_intel_mac_can_be_chosen_when_the_arm_queue_is_full():
    # GitHub cancels a job no arm64 Mac picked up; macos-26-intel has the same Xcode 26.6 path.
    triggers = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))[True]  # YAML reads "on" as true
    runner = triggers["workflow_dispatch"]["inputs"]["runner"]
    assert runner["default"] == "macos-26"
    assert runner["options"] == ["macos-26", "macos-26-intel"]
    assert triggers["push"]["branches"] == ["main", "master"]


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


def test_mlx_packages_in_the_full_build(job):
    """The downloadable model (MLX) is linked only in the first build, at pinned versions."""
    script = runs(job)
    full = script.split("cat << 'EOF' > project.yml", 1)[1].split("EOF", 1)[0]
    for url, version in [("https://github.com/ml-explore/mlx-swift", "0.32.3"),
                         ("https://github.com/ml-explore/mlx-swift-lm", "3.32.3"),
                         ("https://github.com/huggingface/swift-transformers", "1.3.5")]:
        assert f"url: {url}\n" in full and f"exactVersion: {version}" in full
    for product in ["MLX", "MLXLLM", "MLXLMCommon", "Tokenizers"]:
        assert f"product: {product}\n" in full
    plain = script.split("cat << 'EOF' > project-plain.yml", 1)[1].split("EOF", 1)[0]
    assert "package" not in plain
    first = [s for s in job["steps"] if s.get("id") == "build"][0]["run"]
    assert "-clonedSourcePackagesDirPath spm" in first and "-skipMacroValidation" in first


def test_mlx_has_its_own_fallback(job):
    """When MLX does not build, a build without it keeps the voices and Apple's model; the plain build
    only comes when that fails too."""
    script = runs(job)
    assert 'open("project-nomlx.yml", "w"' in script
    nomlx = [s for s in job["steps"] if s.get("id") == "nomlx"]
    assert nomlx and nomlx[0].get("continue-on-error") is True
    assert nomlx[0]["if"] == "steps.build.outcome == 'failure'"
    assert "xcodegen generate --spec project-nomlx.yml" in nomlx[0]["run"]
    plain = [s for s in job["steps"] if "project-plain.yml" in s.get("run", "") and "xcodegen generate" in s.get("run", "")]
    assert plain and "steps.nomlx.outcome != 'success'" in plain[0]["if"]
    metal = step_with(job, "downloadComponent MetalToolchain")
    assert metal.get("continue-on-error") is True
    order = [s.get("id") or s.get("name") for s in job["steps"]]
    assert order.index("build") < order.index("nomlx")


def test_app_store_edition_can_be_chosen(job):
    """The App Store edition (APPSTORE flag) sells Mürekkep Pro; it comes out as Murekkep-AppStore."""
    triggers = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))[True]
    edition = triggers["workflow_dispatch"]["inputs"]["edition"]
    assert edition["options"] == ["personal", "appstore"] and edition["default"] == "personal"
    assert job["env"]["EDITION"] == "${{ inputs.edition || 'personal' }}"
    script = runs(job)
    assert 'SWIFT_ACTIVE_COMPILATION_CONDITIONS: \\"$(inherited) APPSTORE\\"' in script
    assert "MUREKKEP_PLAIN APPSTORE" in script
    # Patched before the MLX-less project is cut from project.yml, so all three builds get the flag.
    assert script.index("MUREKKEP_PLAIN APPSTORE") < script.index('open("project-nomlx.yml", "w"')
    assert "Murekkep-AppStore.ipa" in script
    upload = step_with(job, "actions/upload-artifact@v4")
    assert upload["with"]["name"] == "${{ inputs.edition == 'appstore' && 'Murekkep-AppStore' || 'Murekkep-IPA' }}"
    assert upload["with"]["path"] == "Murekkep*.ipa"


def test_privacy_manifest_is_a_resource_in_every_project(job):
    script = runs(job)
    for name in ["project.yml", "project-plain.yml"]:
        spec = script.split(f"cat << 'EOF' > {name}", 1)[1].split("EOF", 1)[0]
        assert '- "PrivacyInfo.xcprivacy"' in spec, name
        assert "- path: AppSource/PrivacyInfo.xcprivacy\n" in spec, name
        entry = spec.split("- path: AppSource/PrivacyInfo.xcprivacy", 1)[1].split("- ", 1)[0]
        assert "buildPhase: resources" in entry, name


def test_app_store_edition_is_ipad_only(job):
    # Marked for iPhone, review would want iPhone screenshots and test it there.
    script = runs(job)
    patch = script.split('if [ "$EDITION" = "appstore" ]; then', 1)[1].split("fi\n", 1)[0]
    assert 'TARGETED_DEVICE_FAMILY: \\"1,2\\"' in patch and 'TARGETED_DEVICE_FAMILY: \\"2\\"' in patch


def test_the_ipa_asks_for_the_larger_memory_limit(job):
    # Without it iOS lets the app hold about 5 GB, too little for the downloaded model next to the
    # page. The IPA is unsigned, so it is signed ad hoc with the entitlement: Sideloadly and SideStore
    # read the entitlements from the app when they sign it again.
    entitlements = WORKFLOW.parent.parent.parent / "Murekkep.swiftpm" / "Murekkep.entitlements"
    assert "<key>com.apple.developer.kernel.increased-memory-limit</key>\n\t<true/>" in entitlements.read_text(encoding="utf-8")
    script = runs(job)
    for name in ["project.yml", "project-plain.yml"]:
        spec = script.split(f"cat << 'EOF' > {name}", 1)[1].split("EOF", 1)[0]
        assert "CODE_SIGN_ENTITLEMENTS: AppSource/Murekkep.entitlements" in spec, name
        assert '- "*.entitlements"' in spec, name
    pack = step_with(job, "zip -qry")["run"]
    assert "--entitlements AppSource/Murekkep.entitlements" in pack
    assert pack.index("--entitlements") < pack.index("zip -qry")
