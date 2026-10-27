"""Writes codemagic.yaml from .github/workflows/main.yml, so the build lives in one place.

Codemagic gives personal accounts 500 free macOS M2 minutes a month; GitHub's free macOS minutes
for a private repo ran out. The Codemagic workflow is the App Store edition's TestFlight upload
only: it skips the separate IPA build (the upload archives the app itself) and the fallback builds.

    python tools/make_codemagic.py          # rewrite codemagic.yaml
    python tools/make_codemagic.py --check  # exit 1 when codemagic.yaml is out of date
"""
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
# The Xcode the TestFlight builds are made with. 26.6 (the default) built 1.0 (201), but on 2026-10-26
# Codemagic's M2 queue for it was hours long; support suggested another version, so 26.5.
XCODE = "26.5"
WORKFLOW = ROOT / ".github" / "workflows" / "main.yml"
OUT = ROOT / "codemagic.yaml"

# What GitHub gives the scripts, from Codemagic's names. The App Store Connect key comes from the
# environment group "app_store_credentials" (Codemagic's own variable names).
PRELUDE = """\
#!/usr/bin/env bash
# Like GitHub's run steps (bash -e): stop at the first failing command.
set -e
export RUNNER_TEMP="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
export ASC_KEY_ID="${ASC_KEY_ID:-$APP_STORE_CONNECT_KEY_IDENTIFIER}"
export ASC_ISSUER_ID="${ASC_ISSUER_ID:-$APP_STORE_CONNECT_ISSUER_ID}"
export ASC_KEY_P8="${ASC_KEY_P8:-$APP_STORE_CONNECT_PRIVATE_KEY}"
# Build numbers above every GitHub upload (100 + GitHub's run number): 200 + Codemagic's count.
export GITHUB_RUN_NUMBER="$((100 + ${PROJECT_BUILD_NUMBER:-${BUILD_NUMBER:-1}}))"
"""


def steps():
    job = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))["jobs"]["build-ipa"]
    return {s.get("name"): s for s in job["steps"]}


def script(name, body, ignore_failure=False):
    item = {"name": name, "script": PRELUDE + body.rstrip("\n") + "\n"}
    if ignore_failure:
        item["ignore_failure"] = True
    return item


def build():
    s = steps()
    full_build = s["IPA Derle"]["run"]
    generate = full_build[: full_build.index("xcodegen generate --spec project.yml")] + "xcodegen generate --spec project.yml\n"
    scripts = [
        script("App Store Anahtarini Dogrula", s["App Store Anahtarini Dogrula"]["run"]),
        script("Xcode Surumu", "xcodebuild -version\n"),
        script("Gomulu Ses Motorunu Derle (onbellekte yoksa)",
               "if [ -d sherpa-out/sherpa-onnx.xcframework ]; then\n"
               "  echo \"Ses motoru onbellekten geldi.\"\n"
               "  exit 0\n"
               "fi\n" + s["Gomulu Ses Motorunu Derle (sherpa-onnx 1.13.8, yalnizca iPad)"]["run"]),
        script("Klasor Yapisini Hazirla", s["Klasor Yapisini Hazirla"]["run"]),
        script("Info.plist ve Xcode Projesi Olustur", s["Info.plist ve Xcode Projesi Olustur"]["run"]),
        script("Metal Araclari", s["Metal Araclari (indirilebilir model icin)"]["run"], ignore_failure=True),
        script("Murekkep Shaderlarini Derle", s["Murekkep Shaderlarini Derle"]["run"]),
        script("Xcode Projesini Uret", generate),
        script("TestFlight'a Yukle", s["TestFlight'a Yukle"]["run"]),
    ]
    return {
        "workflows": {
            "appstore-testflight": {
                "name": "Murekkep App Store -> TestFlight",
                "instance_type": "mac_mini_m2",
                "max_build_duration": 120,
                "environment": {
                    # Pinned (see XCODE): "latest" and 26.6 sat queued on 2026-10-26.
                    "xcode": XCODE,
                    "groups": ["app_store_credentials"],
                    "vars": {"EDITION": "appstore", "TESTFLIGHT": "yes"},
                },
                "cache": {"cache_paths": ["$CM_BUILD_DIR/sherpa-out", "$CM_BUILD_DIR/spm"]},
                "scripts": scripts,
                "artifacts": ["*.log"],
            },
            # A page's text as PDFKit (the iPad's reader) gives it, and the math engine's answers on it:
            # a minute on the Mac, no signing, started by hand when the iPad reads a page differently.
            "pdfkit-probe": {
                "name": "Murekkep PDFKit Metni (deneme)",
                "instance_type": "mac_mini_m2",
                "max_build_duration": 15,
                "environment": {"xcode": XCODE},
                "scripts": [script("PDFKit ile Sayfa Metni", PROBE)],
                "artifacts": ["pdfkit_*"],
            },
            # The ad recordings (tools/demo): the App Store edition's plain build with the DEMO flag on
            # an iPad simulator, every scene filmed once by the simulator (the app in English, the
            # notebook in English and Turkish). No keys, no upload; started by hand.
            "demo-kayit": {
                "name": "Murekkep Reklam Kaydi (simulator)",
                "instance_type": "mac_mini_m2",
                "max_build_duration": 60,
                "environment": {"xcode": XCODE, "vars": {"EDITION": "appstore"}},
                "scripts": [
                    script("Xcode ve Simulatorler", "xcodebuild -version\nxcrun simctl list runtimes\n"),
                    script("Klasor Yapisini Hazirla", s["Klasor Yapisini Hazirla"]["run"]),
                    script("Info.plist ve Xcode Projesi Olustur", s["Info.plist ve Xcode Projesi Olustur"]["run"]),
                    script("Demo Surumunu Hazirla", DEMO_PREPARE),
                    script("Simulator Icin Derle", DEMO_BUILD),
                    script("Sahneleri Kaydet", DEMO_RECORD),
                ],
                "artifacts": ["demo-out/*.mp4", "demo-out/*.json", "demo-out/*.png", "demo-out/*.start",
                              "demo-out/*.log", "*.log"],
            },
        }
    }


# Only the recording build gets the demo player and the scenes; the App Store build never has them.
DEMO_PREPARE = """\
cp tools/demo/DemoPlayer.swift AppSource/
cp tools/demo/scenes/DemoScene-*.json AppSource/
python3 - << 'PYEOF'
text = open("project-plain.yml", encoding="utf-8").read()
assert 'MUREKKEP_PLAIN APPSTORE"' in text, "the plain project lacks the App Store flag"
text = text.replace('MUREKKEP_PLAIN APPSTORE"', 'MUREKKEP_PLAIN APPSTORE DEMO"')
open("project-plain.yml", "w", encoding="utf-8").write(text)
PYEOF
xcodegen generate --spec project-plain.yml
"""

DEMO_BUILD = """\
set -o pipefail
if ! xcodebuild -project Murekkep.xcodeproj -scheme Murekkep -configuration Release \\
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build \\
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build > build.log 2>&1; then
  grep -E "error:" build.log | sort -u | head -60
  echo "::error::Simulator build failed (build.log)"
  exit 1
fi
codesign --force --sign - --deep build/Build/Products/Release-iphonesimulator/Murekkep.app
"""

# The scenes listed in tools/demo/film.txt: a run films only what changed.
DEMO_RECORD = """\
bash tools/demo/record.sh build/Build/Products/Release-iphonesimulator/Murekkep.app demo-out
"""


PROBE = """\
APP=Murekkep.swiftpm
xcrun swiftc -O tools/pdfkit_probe/main.swift tools/pdfkit_probe/Stubs.swift \\
  "$APP/MathEngine.swift" "$APP/ExactMath.swift" "$APP/PageMath.swift" "$APP/MathText.swift" "$APP/Questions.swift" "$APP/PageLayout.swift" "$APP/PageGlyphs.swift" \\
  -o "$RUNNER_TEMP/probe"
"$RUNNER_TEMP/probe" tests/fixtures/calculus_p14.pdf pdfkit_calculus_p14.txt
"""


class Literal(yaml.SafeDumper):
    pass


def _str(dumper, data):
    style = "|" if "\n" in data else None
    return dumper.represent_scalar("tag:yaml.org,2002:str", data, style=style)


Literal.add_representer(str, _str)

HEADER = "# Generated by tools/make_codemagic.py from .github/workflows/main.yml. Do not edit by hand.\n"


def render():
    return HEADER + yaml.dump(build(), Dumper=Literal, sort_keys=False, allow_unicode=True, width=1000)


if __name__ == "__main__":
    text = render()
    if "--check" in sys.argv:
        current = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
        sys.exit(0 if current == text else 1)
    OUT.write_bytes(text.encode("utf-8"))
    print(f"wrote {OUT.name}: {len(build()['workflows']['appstore-testflight']['scripts'])} scripts")
