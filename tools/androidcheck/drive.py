"""Drives the Android emulator for the Mürekkep check: UI dump, taps by label, stylus paths, screenshots.

    py -3 drive.py ui                    # labelled elements with their centres
    py -3 drive.py tap "New notebook"    # tap an element by text or content description
    py -3 drive.py xy 500 600            # tap a point
    py -3 drive.py wave x y w h [n]      # a stylus wave in that box, n periods
    py -3 drive.py line x1 y1 x2 y2      # a straight stylus stroke
    py -3 drive.py loop cx cy rx ry      # a stylus loop round an ellipse (the lasso)
    py -3 drive.py hold kind cx cy r [name] [dx dy]
                                         # a shaky circle, square, triangle or line, the pen resting
                                         # 1 s at its end (hold-to-shape); with a name, screenshots
                                         # while it rests, and after sliding the pen by dx dy if given
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


def shaky(kind, cx, cy, r):
    """A hand-drawn shape: a little tremor and an overshoot, as a person draws it."""
    if kind == "circle":
        pts = [(cx + r * math.cos(2 * math.pi * i / 36), cy + r * 0.96 * math.sin(2 * math.pi * i / 36)) for i in range(39)]
    elif kind == "square":
        corners = [(cx - r, cy - r), (cx + r, cy - r), (cx + r, cy + r), (cx - r, cy + r), (cx - r, cy - r)]
        pts = []
        for (ax, ay), (bx, by) in zip(corners, corners[1:]):
            pts += [(ax + (bx - ax) * k / 8, ay + (by - ay) * k / 8) for k in range(8)]
        pts.append((cx - r, cy - r + 6))
    elif kind == "triangle":
        corners = [(cx, cy - r), (cx + r * 0.95, cy + r * 0.7), (cx - r, cy + r * 0.72), (cx, cy - r)]
        pts = []
        for (ax, ay), (bx, by) in zip(corners, corners[1:]):
            pts += [(ax + (bx - ax) * k / 9, ay + (by - ay) * k / 9) for k in range(9)]
        pts.append((cx + 4, cy - r + 6))
    else:
        pts = [(cx - r + 2 * r * k / 16, cy - r * 0.3 + 0.6 * r * k / 16) for k in range(17)]
    return [(x + 3 * math.sin(i * 1.7), y + 3 * math.cos(i * 2.3)) for i, (x, y) in enumerate(pts)]


def hold(argv):
    kind, cx, cy, r = argv[2], float(argv[3]), float(argv[4]), float(argv[5])
    name = argv[6] if len(argv) > 6 else None
    pts = shaky(kind, cx, cy, r)
    (x0, y0), rest = pts[0], pts[1:]
    cmds = [f"input stylus motionevent DOWN {x0:.0f} {y0:.0f}"] + [f"input stylus motionevent MOVE {x:.0f} {y:.0f}" for x, y in rest]
    adb("shell", " ; ".join(cmds))
    xl, yl = pts[-1]
    # The pen rests: the canvas turns what it drew into a shape after 0.55 s.
    adb("shell", "sleep 1")
    if name:
        shot(name + "-held")
    if len(argv) > 8:
        dx, dy = float(argv[7]), float(argv[8])
        adb("shell", " ; ".join(f"input stylus motionevent MOVE {xl + dx * k / 6:.0f} {yl + dy * k / 6:.0f}" for k in range(1, 7)))
        xl, yl = xl + dx, yl + dy
        if name:
            shot(name + "-slid")
    adb("shell", f"input stylus motionevent UP {xl:.0f} {yl:.0f}")


def shot(name):
    os.makedirs(SHOTS, exist_ok=True)
    path = os.path.join(SHOTS, name + ".png")
    with open(path, "wb") as f:
        f.write(adb("exec-out", "screencap", "-p", binary=True))
    print(path)


def main(argv):
    # The Windows console's code page cannot print every log line (emoji in other apps' logs).
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
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
    elif cmd == "hold":
        hold(argv)
    elif cmd == "loop":
        cx, cy, rx, ry = map(float, argv[2:6])
        steps = 40
        stylus_path([(cx + rx * math.cos(2 * math.pi * i / steps), cy + ry * math.sin(2 * math.pi * i / steps)) for i in range(steps + 1)])
    elif cmd == "line":
        x1, y1, x2, y2 = map(float, argv[2:6])
        stylus_path([(x1 + (x2 - x1) * i / 12, y1 + (y2 - y1) * i / 12) for i in range(13)])
    elif cmd == "finger":
        adb("shell", "input", "touchscreen", "swipe", *argv[2:6], "600")
    elif cmd == "shot":
        shot(argv[2])
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
