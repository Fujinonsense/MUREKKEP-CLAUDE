"""Two fingers on the emulator through Android's `uinput` tool (a multi-touch screen, protocol B),
for what `adb shell input` cannot do: pinching to zoom.

    py -3 fingers.py pinch cx cy d0 d1 [steps]   # two fingers d0 apart, spread (or closed) to d1

Like pen.py, the axes are the panel's own: 2560x1600 landscape (run it with user_rotation 0).
"""
import json
import os
import subprocess
import sys
import tempfile

ADB = os.path.join(os.environ["LOCALAPPDATA"], "Android", "Sdk", "platform-tools", "adb.exe")

EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
SYN_REPORT = 0
BTN_TOUCH = 330
ABS_MT_SLOT, ABS_MT_TOUCH_MAJOR, ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_MT_TRACKING_ID = 47, 48, 53, 54, 57

REGISTER = {
    "id": 2, "command": "register", "name": "Murekkep test fingers", "vid": 6353, "pid": 20226, "bus": "usb",
    "configuration": [
        {"type": 100, "data": [EV_KEY, EV_ABS]},                                            # UI_SET_EVBIT
        {"type": 101, "data": [BTN_TOUCH]},                                                 # UI_SET_KEYBIT
        {"type": 103, "data": [ABS_MT_SLOT, ABS_MT_TOUCH_MAJOR, ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_MT_TRACKING_ID]},
        {"type": 110, "data": [1]},                                                          # INPUT_PROP_DIRECT
    ],
    "abs_info": [
        {"code": ABS_MT_SLOT, "info": {"value": 0, "minimum": 0, "maximum": 9, "fuzz": 0, "flat": 0, "resolution": 0}},
        {"code": ABS_MT_TOUCH_MAJOR, "info": {"value": 0, "minimum": 0, "maximum": 255, "fuzz": 0, "flat": 0, "resolution": 0}},
        {"code": ABS_MT_POSITION_X, "info": {"value": 0, "minimum": 0, "maximum": 2559, "fuzz": 0, "flat": 0, "resolution": 10}},
        {"code": ABS_MT_POSITION_Y, "info": {"value": 0, "minimum": 0, "maximum": 1599, "fuzz": 0, "flat": 0, "resolution": 10}},
        {"code": ABS_MT_TRACKING_ID, "info": {"value": 0, "minimum": 0, "maximum": 65535, "fuzz": 0, "flat": 0, "resolution": 0}},
    ],
}


def frame(*pairs):
    events = []
    for t, c, v in pairs:
        events += [t, c, int(v)]
    return {"id": 2, "command": "inject", "events": events + [EV_SYN, SYN_REPORT, 0]}


def delay(ms):
    return {"id": 2, "command": "delay", "duration": ms}


def run(commands):
    script = [REGISTER, delay(600)] + commands + [delay(300)]
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        for c in script:
            f.write(json.dumps(c) + "\n")
        local = f.name
    subprocess.run([ADB, "push", local, "/data/local/tmp/fingers.json"], capture_output=True, check=True)
    os.unlink(local)
    subprocess.run([ADB, "shell", "uinput", "/data/local/tmp/fingers.json"], check=True)


def pinch(cx, cy, d0, d1, steps=16):
    def at(d):
        return (EV_ABS, ABS_MT_SLOT, 0), (EV_ABS, ABS_MT_POSITION_X, cx - d / 2), (EV_ABS, ABS_MT_POSITION_Y, cy), \
               (EV_ABS, ABS_MT_SLOT, 1), (EV_ABS, ABS_MT_POSITION_X, cx + d / 2), (EV_ABS, ABS_MT_POSITION_Y, cy)
    cmds = [frame((EV_ABS, ABS_MT_SLOT, 0), (EV_ABS, ABS_MT_TRACKING_ID, 101), (EV_ABS, ABS_MT_TOUCH_MAJOR, 40),
                  (EV_ABS, ABS_MT_POSITION_X, cx - d0 / 2), (EV_ABS, ABS_MT_POSITION_Y, cy),
                  (EV_ABS, ABS_MT_SLOT, 1), (EV_ABS, ABS_MT_TRACKING_ID, 102), (EV_ABS, ABS_MT_TOUCH_MAJOR, 40),
                  (EV_ABS, ABS_MT_POSITION_X, cx + d0 / 2), (EV_ABS, ABS_MT_POSITION_Y, cy), (EV_KEY, BTN_TOUCH, 1)),
            delay(30)]
    for k in range(1, steps + 1):
        cmds += [frame(*at(d0 + (d1 - d0) * k / steps)), delay(16)]
    cmds.append(frame((EV_ABS, ABS_MT_SLOT, 0), (EV_ABS, ABS_MT_TRACKING_ID, -1),
                      (EV_ABS, ABS_MT_SLOT, 1), (EV_ABS, ABS_MT_TRACKING_ID, -1), (EV_KEY, BTN_TOUCH, 0)))
    run(cmds)


if __name__ == "__main__":
    if len(sys.argv) < 6 or sys.argv[1] != "pinch":
        sys.exit(__doc__)
    cx, cy, d0, d1 = map(float, sys.argv[2:6])
    pinch(cx, cy, d0, d1, int(sys.argv[6]) if len(sys.argv) > 6 else 16)
