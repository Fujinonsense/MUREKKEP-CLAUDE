"""Compiles the Metal shaders the app builds at run time (`device.makeLibrary(source:)`), so a broken
shader fails the CI build instead of blanking every page on the iPad.

    python3 tools/metal_check.py              # compile each shader with xcrun (CI's Mac)
    python3 tools/metal_check.py --extract D  # only write the .metal files into D

Standard library only. Without a Metal compiler (Windows, or the toolchain failed to download) it
warns and exits 0: it cannot tell either way.
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

APP = Path(__file__).resolve().parent.parent / "Murekkep.swiftpm"

# (file, the line that opens the string): raw strings end at `"""#`, plain ones at `"""`.
SOURCES = [
    ("InkShaders.swift", 'static let source = #"""'),
    ("Stickers.swift", 'private static let source = #"""'),
    ("InkLayer.swift", 'static let shaderSource = """'),
]


def extract(name, opener):
    """The shader text of one Swift string literal, as the app hands it to Metal."""
    lines = (APP / name).read_text(encoding="utf-8").split("\n")
    start = next(i for i, line in enumerate(lines) if line.strip() == opener)
    raw = opener.endswith('#"""')
    closer = '"""#' if raw else '"""'
    end = next(i for i in range(start + 1, len(lines)) if lines[i].strip() == closer)
    # Swift strips the closing delimiter's indentation from every line.
    indent = len(lines[end]) - len(lines[end].lstrip())
    body = "\n".join(line[indent:] if line[:indent].strip() == "" else line for line in lines[start + 1:end])
    if not raw:
        if "\\(" in body:
            raise ValueError(f"{name}: the shader string interpolates values; check it by hand")
        body = body.replace('\\"', '"').replace("\\\\", "\\")
    return body + "\n"


def write_all(directory):
    out = []
    for name, opener in SOURCES:
        path = Path(directory) / (Path(name).stem + ".metal")
        path.write_text(extract(name, opener), encoding="utf-8")
        out.append(path)
    return out


def main(argv):
    if "--extract" in argv:
        for path in write_all(argv[argv.index("--extract") + 1]):
            print(path)
        return 0
    if shutil.which("xcrun") is None:
        print("warning: no xcrun here; the shaders were not compiled")
        return 0
    probe = subprocess.run(["xcrun", "-sdk", "iphoneos", "metal", "-v"], capture_output=True, text=True)
    if probe.returncode != 0:
        print("warning: the Metal toolchain is missing; the shaders were not compiled")
        return 0
    failed = 0
    with tempfile.TemporaryDirectory() as tmp:
        for path in write_all(tmp):
            result = subprocess.run(["xcrun", "-sdk", "iphoneos", "metal", "-std=metal3.0", "-c", str(path),
                                     "-o", str(path.with_suffix(".air"))], capture_output=True, text=True)
            if result.returncode == 0:
                print(f"ok   {path.name}")
            else:
                failed += 1
                print(f"FAIL {path.name}\n{result.stderr}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
