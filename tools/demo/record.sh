#!/usr/bin/env bash
# The ad recordings (tools/demo): installs the DEMO build on a new iPad simulator and films each
# scene with the simulator's own screen recorder (H.264), at the iPad's full resolution.
# usage: record.sh <Murekkep.app> <out dir> [<scene-lang>...]   (say notes-en textpen-tr; none: the
# scenes listed in tools/demo/film.txt)
# For each scene: <scene-lang>.mp4, <scene-lang>.json (the pen's track for the edit's zoom),
# <scene-lang>.start (wall clock just before the launch) and <scene-lang>-end.png.
set -euo pipefail
APP="$1"
OUT="$2"
shift 2
mkdir -p "$OUT"
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")

# The newest iPadOS runtime and an 11-inch iPad on it.
read -r RUNTIME TYPE < <(python3 -c '
import json, subprocess
runtimes = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "-j"]))["runtimes"]
ios = [r for r in runtimes if r.get("isAvailable") and ".SimRuntime.iOS-" in r["identifier"]]
ios.sort(key=lambda r: [int(v) for v in r["version"].split(".")])
runtime = ios[-1]
types = runtime.get("supportedDeviceTypes") or json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devicetypes", "-j"]))["devicetypes"]
names = {t["name"]: t["identifier"] for t in types}
# An 11-inch iPad: fewer pixels for the recorder to encode a second, so it keeps more frames.
for want in ["iPad Air 11-inch (M3)", "iPad Air 11-inch (M2)", "iPad Pro 11-inch (M4)", "iPad (A16)", "iPad Pro 13-inch (M4)"]:
    if want in names:
        print(runtime["identifier"], names[want])
        break
else:
    ipads = sorted(n for n in names if n.startswith("iPad"))
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
    xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$OUT/$name.mp4" 2> "$OUT/$name.rec.log" &
    rec=$!
    for _ in $(seq 1 50); do
      if grep -q "Recording started" "$OUT/$name.rec.log" 2> /dev/null; then break; fi
      sleep 0.2
    done
  fi
  # The scene's own launch arguments (its stretched timings), from its file in the app.
  local extra=()
  while IFS= read -r arg; do
    if [ -n "$arg" ]; then extra+=("$arg"); fi
  done < <(python3 -c '
import json, sys
print("\n".join(json.load(open(sys.argv[1])).get("launch", [])))' "$APP/DemoScene-$name.json")
  python3 -c 'import time; print(f"{time.time():.3f}")' > "$OUT/$name.start"
  local pid
  pid=$(xcrun simctl launch "$UDID" "$BUNDLE" -DemoScene "$name" -AppleLanguages "($lang)" -AppleLocale "$locale" \
    ${extra[@]+"${extra[@]}"} | awk -F': ' '{print $NF}')
  # The app's CPU (%) and memory (KB) once a second: a view that keeps redrawing itself shows here.
  ( while kill -0 "$pid" 2> /dev/null; do
      echo "$(date +%s) $(ps -o %cpu=,rss= -p "$pid")" >> "$OUT/$name.cpu.txt"
      sleep 1
    done ) &
  local sampler=$!
  for _ in $(seq 1 600); do
    if [ -f "$done" ]; then break; fi
    if ! kill -0 "$pid" 2> /dev/null; then echo "::warning::$name: the app quit or crashed"; break; fi
    sleep 0.5
  done
  sleep 1.2
  kill "$sampler" 2> /dev/null || true
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

if [ "$#" -eq 0 ]; then
  set -- $(grep -v '^#' "$(dirname "$0")/film.txt")
fi
# SwiftUI's own warnings about views that keep changing their state, for the whole run.
xcrun simctl spawn "$UDID" log stream --style compact \
  --predicate 'eventMessage CONTAINS "multiple times per frame" OR eventMessage CONTAINS "during view update"' \
  > "$OUT/swiftui-warnings.log" 2>&1 &
LOGGER=$!
# Once through every ink first, so the filmed scenes do not wait for the shaders.
run_scene warmup en no
for scene in "$@"; do
  run_scene "$scene" "${scene##*-}" yes
done
kill "$LOGGER" 2> /dev/null || true
# Crash reports of the app written during the run (the simulator's land on the host).
find "$HOME/Library/Logs/DiagnosticReports" -type f -newer "$OUT/warmup.start" \( -name '*.ips' -o -name '*.crash' \) \
  -exec cp {} "$OUT/" \; 2> /dev/null || true
ls -la "$OUT"
