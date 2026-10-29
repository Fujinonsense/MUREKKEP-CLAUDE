#!/usr/bin/env bash
# Reproduces the lost save: a fresh app opened on the demo page, one stylus line, then is ink.bin there?
# Also: a notebook made with "New notebook", a line, Back to the library (refresh on return), reopen.
# Clears the app's data on the emulator (pm clear) before each run.  bash savecheck.sh [runs]
ADB="$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
HERE="$(cd "$(dirname "$0")" && pwd)"
D="py -3 $HERE/drive.py"
pkg=com.murekkep.notebook
wait_s() { timeout "$1" tail -f /dev/null 2>/dev/null; }
files() { "$ADB" shell run-as $pkg ls files/notebooks/"$1" 2>/dev/null | tr -d '\r' | tr '\n' ' '; }
ids() { "$ADB" shell run-as $pkg ls files/notebooks 2>/dev/null | tr -d '\r'; }

runs=${1:-3}
for r in $(seq 1 "$runs"); do
  "$ADB" shell pm clear $pkg >/dev/null
  "$ADB" shell am start -W -n $pkg/.MainActivity --es murekkep.demo pens >/dev/null
  wait_s 3
  $D line 700 1200 1500 1200
  wait_s 2.5
  id=$(ids | head -1)
  echo "demo run $r: $id -> $(files "$id")"
done

# The library path: create, draw, back (the library refreshes as it returns), check the record.
"$ADB" shell pm clear $pkg >/dev/null
"$ADB" shell am start -W -n $pkg/.MainActivity >/dev/null
wait_s 2
$D xy 2365 1448
wait_s 2
$D line 700 700 1500 700
$D xy 56 104
wait_s 2.5
id=$(ids | head -1)
echo "library: $id -> $(files "$id")"
"$ADB" shell run-as $pkg cat files/notebooks/"$id"/meta.json | tr -d '\r' | grep -E "modified|pageCount"
