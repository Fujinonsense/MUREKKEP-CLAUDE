"""Drives the Android emulator for the Mürekkep check: UI dump, taps by label, stylus paths, screenshots.

    py -3 drive.py ui                    # labelled elements with their centres
    py -3 drive.py tap "New notebook"    # tap an element by text or content description
    py -3 drive.py xy 500 600            # tap a point
    py -3 drive.py wave x y w h [n]      # a stylus wave in that box, n periods
    py -3 drive.py line x1 y1 x2 y2      # a straight stylus stroke
    py -3 drive.py finger x1 y1 x2 y2    # a finger drag (pans the page)
    py -3 drive.py shot name             # screenshot to %TEMP%\murekkep-androidcheck
ame.png
    py -3 drive.py log                   # crashes and Mürekkep's warnings from logcat
"""
import math
import os
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

SDK = os.path.join(os.environ["LOCALAPPDATA"], "Android", "Sdk")
ADB = os.path.join(SDK, "platform-tools", "adb.exe")
SHOTS = os.path.join(tempfile.gettempdir(), "murekkep-androidcheck")


def adb(*args, binary=False, check=True):
    out = subprocess.run([ADB, *args], capture_output=True, check=check)
    return out.stdout if binary else out.stdout.decode("utf-8", "replace")


def nodes():
    adb("shell", "uiautomator", "dump", "/sdcard/ui.xml")
    xml = adb("exec-out", "cat", "/sdcard/ui.xml")
    root = ET.fromstring(xml[xml.index("<"):])
    for n in root.iter("node"):
        label = n.get("text") or n.get("content-desc") or ""
        m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.get("bounds", ""))
        if not m:
            continue
        x1, y1, x2, y2 = map(int, m.groups())
        yield label, (x1 + x2) // 2, (y1 + y2) // 2, (x1, y1, x2, y2), n.get("clickable") == "true", n.get("enabled") == "true"


def stylus_path(points):
    """One stylus stroke through the points: DOWN, MOVEs, UP, in one shell call."""
    (x0, y0), rest = points[0], points[1:]
    cmds = [f"input stylus motionevent DOWN {x0:.0f} {y0:.0f}"]
    cmds += [f"input stylus motionevent MOVE {x:.0f} {y:.0f}" for x, y in rest]
    xl, yl = points[-1]
    cmds.append(f"input stylus motionevent UP {xl:.0f} {yl:.0f}")
    adb("shell", " ; ".join(cmds))


def main(argv):
    cmd = argv[1]
    if cmd == "ui":
        for label, x, y, b, click, enabled in nodes():
            if label or click:
                print(f"{label!r:50} centre=({x},{y}) bounds={b}{' click' if click else ''}{'' if enabled else ' DISABLED'}")
    elif cmd == "tap":
        want = argv[2]
        hits = [(x, y) for label, x, y, *_ in nodes() if label == want]
        if not hits:
            hits = [(x, y) for label, x, y, *_ in nodes() if want.lower() in label.lower()]
        if not hits:
            sys.exit(f"no element labelled {want!r}")
        x, y = hits[0]
        adb("shell", "input", "tap", str(x), str(y))
        print(f"tapped {want!r} at ({x},{y})")
    elif cmd == "xy":
        adb("shell", "input", "tap", argv[2], argv[3])
    elif cmd == "wave":
        x, y, w, h = map(float, argv[2:6])
        periods = float(argv[6]) if len(argv) > 6 else 2
        steps = 28
        pts = [(x + w * i / steps, y + h / 2 + h / 2 * math.sin(2 * math.pi * periods * i / steps)) for i in range(steps + 1)]
        stylus_path(pts)
    elif cmd == "line":
        x1, y1, x2, y2 = map(float, argv[2:6])
        stylus_path([(x1 + (x2 - x1) * i / 12, y1 + (y2 - y1) * i / 12) for i in range(13)])
    elif cmd == "finger":
        adb("shell", "input", "touchscreen", "swipe", *argv[2:6], "600")
    elif cmd == "shot":
        os.makedirs(SHOTS, exist_ok=True)
        path = os.path.join(SHOTS, argv[2] + ".png")
        with open(path, "wb") as f:
            f.write(adb("exec-out", "screencap", "-p", binary=True))
        print(path)
    elif cmd == "log":
        crash = adb("logcat", "-d", "-b", "crash", check=False)
        print(crash.strip() or "(no crashes)")
        main_log = adb("logcat", "-d", "-v", "brief", check=False)
        keep = [l for l in main_log.splitlines()
                if re.search(r"murekkep|AndroidRuntime|FATAL|GLSL|shader|glError|E/libEGL|E/OpenGLRenderer|InkRenderer|InkCanvas", l, re.I)]
        print("\n".join(keep[-60:]) or "(nothing from Mürekkep)")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
