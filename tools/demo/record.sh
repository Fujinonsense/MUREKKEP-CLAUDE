#!/usr/bin/env bash
# The ad recordings (tools/demo): installs the DEMO build on a new iPad Pro simulator and films each
# scene with the simulator's own screen recorder, at the iPad's full resolution.
# usage: record.sh <Murekkep.app> <out dir> <scene-lang>...   (say notes-en textpen-tr)
# For each scene: <scene-lang>.mp4, <scene-lang>.json (the pen's track for the edit's zoom),
# <scene-lang>.start (wall clock just before the launch) and <scene-lang>-end.png.
set -euo pipefail
APP="$1"
OUT="$2"
shift 2
mkdir -p "$OUT"
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")

# The newest iPadOS runtime and the largest iPad Pro it has.
read -r RUNTIME TYPE < <(python3 -c '
import json, subprocess
runtimes = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "-j"]))["runtimes"]
ios = [r for r in runtimes if r.get("isAvailable") and ".SimRuntime.iOS-" in r["identifier"]]
ios.sort(key=lambda r: [int(v) for v in r["version"].split(".")])
runtime = ios[-1]
types = runtime.get("supportedDeviceTypes") or json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devicetypes", "-j"]))["devicetypes"]
names = {t["name"]: t["identifier"] for t in types}
for want in ["iPad Pro 13-inch (M5)", "iPad Pro 13-inch (M4)", "iPad Pro (12.9-inch) (6th generation)", "iPad Air 13-inch (M3)", "iPad Air 13-inch (M2)"]:
    if want in names:
        print(runtime["identifier"], names[want])
        break
else:
    ipads = sorted(n for n in names if n.startswith("iPad Pro"))
    print(runtime["identifier"], names[ipads[-1]])
')
echo "Simulator: $TYPE on $RUNTIME"
UDID=$(xcrun simctl create "Murekkep Kayit" "$TYPE" "$RUNTIME")
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl ui "$UDID" appearance light || true
xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --batteryState charged --batteryLevel 100 || true
xcrun simctl install "$UDID" "$APP"
DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
mkdir -p "$DATA/Documents"

# run_scene <scene> <language> <yes: film it>
run_scene() {
  local name="$1" lang="$2" film="$3" locale=en_US rec=""
  if [ "$lang" = "tr" ]; then locale=tr_TR; fi
  local done="$DATA/Documents/demo-done-$name.json"
  rm -f "$done"
  xcrun simctl terminate "$UDID" "$BUNDLE" > /dev/null 2>&1 || true
  sleep 1
  if [ "$film" = "yes" ]; then
    xcrun simctl io "$UDID" recordVideo --codec=hevc --force "$OUT/$name.mp4" 2> "$OUT/$name.rec.log" &
    rec=$!
    for _ in $(seq 1 50); do
      if grep -q "Recording started" "$OUT/$name.rec.log" 2> /dev/null; then break; fi
      sleep 0.2
    done
  fi
  python3 -c 'import time; print(f"{time.time():.3f}")' > "$OUT/$name.start"
  xcrun simctl launch "$UDID" "$BUNDLE" -DemoScene "$name" -AppleLanguages "($lang)" -AppleLocale "$locale" > /dev/null
  for _ in $(seq 1 600); do
    if [ -f "$done" ]; then break; fi
    sleep 0.5
  done
  sleep 1.2
  if [ -n "$rec" ]; then
    kill -INT "$rec"
    wait "$rec" || true
  fi
  if [ -f "$done" ]; then
    cp "$done" "$OUT/$name.json"
  else
    echo "::warning::$name did not finish"
  fi
  xcrun simctl io "$UDID" screenshot "$OUT/$name-end.png" > /dev/null 2>&1 || true
  echo "$name: done"
}

# Once through every ink first, so the filmed scenes do not wait for the shaders.
run_scene warmup en no
for scene in "$@"; do
  run_scene "$scene" "${scene##*-}" yes
done
ls -la "$OUT"
