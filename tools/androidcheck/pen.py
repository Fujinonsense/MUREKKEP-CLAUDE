"""A virtual stylus on the emulator through Android's `uinput` tool: pressure, tilt, hover, the side
button and the eraser end, as an S Pen or a USI pen reports them.

    py -3 pen.py stroke x1 y1 x2 y2 [--p0 0.1 --p1 1.0] [--tilt 0] [--button] [--rubber]
    py -3 pen.py hover x y seconds [--button]

The screen is 2560x1600 (landscape), so the pen's axes use the same range.
"""
import argparse
import json
import os
import subprocess
import tempfile

ADB = os.path.join(os.environ["LOCALAPPDATA"], "Android", "Sdk", "platform-tools", "adb.exe")

EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
SYN_REPORT = 0
BTN_TOOL_PEN, BTN_TOOL_RUBBER, BTN_TOUCH, BTN_STYLUS = 320, 321, 330, 331
ABS_X, ABS_Y, ABS_PRESSURE, ABS_DISTANCE, ABS_TILT_X, ABS_TILT_Y = 0, 1, 24, 25, 26, 27
P_MAX = 4095

REGISTER = {
    "id": 1, "command": "register", "name": "Murekkep test pen", "vid": 6353, "pid": 20225, "bus": "usb",
    "configuration": [
        {"type": 100, "data": [EV_KEY, EV_ABS]},                                            # UI_SET_EVBIT
        {"type": 101, "data": [BTN_TOOL_PEN, BTN_TOOL_RUBBER, BTN_TOUCH, BTN_STYLUS, 332]},  # UI_SET_KEYBIT
        {"type": 103, "data": [ABS_X, ABS_Y, ABS_PRESSURE, ABS_DISTANCE, ABS_TILT_X, ABS_TILT_Y]},  # UI_SET_ABSBIT
        {"type": 110, "data": [1]},                                                          # INPUT_PROP_DIRECT
    ],
    "abs_info": [
        {"code": ABS_X, "info": {"value": 0, "minimum": 0, "maximum": 2559, "fuzz": 0, "flat": 0, "resolution": 10}},
        {"code": ABS_Y, "info": {"value": 0, "minimum": 0, "maximum": 1599, "fuzz": 0, "flat": 0, "resolution": 10}},
        {"code": ABS_PRESSURE, "info": {"value": 0, "minimum": 0, "maximum": P_MAX, "fuzz": 0, "flat": 0, "resolution": 0}},
        {"code": ABS_DISTANCE, "info": {"value": 0, "minimum": 0, "maximum": 255, "fuzz": 0, "flat": 0, "resolution": 0}},
        {"code": ABS_TILT_X, "info": {"value": 0, "minimum": -60, "maximum": 60, "fuzz": 0, "flat": 0, "resolution": 0}},
        {"code": ABS_TILT_Y, "info": {"value": 0, "minimum": -60, "maximum": 60, "fuzz": 0, "flat": 0, "resolution": 0}},
    ],
}


def frame(*pairs):
    """One report: (type, code, value) triples, then SYN_REPORT."""
    events = []
    for t, c, v in pairs:
        events += [t, c, int(v)]
    return {"id": 1, "command": "inject", "events": events + [EV_SYN, SYN_REPORT, 0]}


def delay(ms):
    return {"id": 1, "command": "delay", "duration": ms}


def run(commands, background=False):
    script = [REGISTER, delay(600)] + commands + [delay(300)]
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        for c in script:
            f.write(json.dumps(c) + "\n")
        local = f.name
    subprocess.run([ADB, "push", local, "/data/local/tmp/pen.json"], capture_output=True, check=True)
    os.unlink(local)
    cmd = [ADB, "shell", "uinput", "/data/local/tmp/pen.json"]
    if background:
        return subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(cmd, check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("what", choices=["stroke", "hover"])
    ap.add_argument("nums", nargs="+", type=float)
    ap.add_argument("--p0", type=float, default=0.5)
    ap.add_argument("--p1", type=float, default=0.5)
    ap.add_argument("--tilt", type=float, default=0, help="degrees, along x")
    ap.add_argument("--button", action="store_true", help="hold the side button")
    ap.add_argument("--rubber", action="store_true", help="use the eraser end")
    a = ap.parse_args()
    tool = BTN_TOOL_RUBBER if a.rubber else BTN_TOOL_PEN
    button = 1 if a.button else 0
    cmds = []
    if a.what == "stroke":
        x1, y1, x2, y2 = a.nums
        steps = 60
        # The pen comes near (hover), touches, moves, lifts and leaves.
        cmds.append(frame((EV_KEY, tool, 1), (EV_KEY, BTN_STYLUS, button), (EV_ABS, ABS_X, x1), (EV_ABS, ABS_Y, y1),
                          (EV_ABS, ABS_DISTANCE, 10), (EV_ABS, ABS_TILT_X, a.tilt), (EV_ABS, ABS_TILT_Y, 0)))
        cmds.append(delay(30))
        for i in range(steps + 1):
            k = i / steps
            p = (a.p0 + (a.p1 - a.p0) * k) * P_MAX
            pairs = [(EV_ABS, ABS_X, x1 + (x2 - x1) * k), (EV_ABS, ABS_Y, y1 + (y2 - y1) * k), (EV_ABS, ABS_PRESSURE, p)]
            if i == 0:
                pairs = [(EV_KEY, BTN_TOUCH, 1), (EV_ABS, ABS_DISTANCE, 0)] + pairs
            cmds.append(frame(*pairs))
            cmds.append(delay(8))
        cmds.append(frame((EV_KEY, BTN_TOUCH, 0), (EV_ABS, ABS_PRESSURE, 0), (EV_ABS, ABS_DISTANCE, 10)))
        cmds.append(delay(30))
        cmds.append(frame((EV_KEY, tool, 0), (EV_KEY, BTN_STYLUS, 0)))
        run(cmds)
    else:
        x, y, seconds = a.nums
        cmds.append(frame((EV_KEY, tool, 1), (EV_KEY, BTN_STYLUS, button), (EV_ABS, ABS_X, x), (EV_ABS, ABS_Y, y),
                          (EV_ABS, ABS_DISTANCE, 20)))
        for i in range(int(seconds * 20)):
            cmds.append(delay(50))
            cmds.append(frame((EV_ABS, ABS_X, x + (i % 2)), (EV_ABS, ABS_Y, y)))
        cmds.append(frame((EV_KEY, tool, 0), (EV_KEY, BTN_STYLUS, 0)))
        run(cmds)


if __name__ == "__main__":
    main()
