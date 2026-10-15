#!/usr/bin/env bash
# Runs the paired journey on a paired iPhone and Apple Watch simulator pair: the companion's and
# the watch's XCUITest steps, one `xcodebuild test-without-building` at a time, in this order:
#
#   1. watch:  a fresh install has no inputs (and the states screen shows the missing-settings view)
#   2. iPhone: send the sample mosque's timetable that ended yesterday
#   3. watch:  receives and stores it, and shows the ended-timetable view
#   4. iPhone: send Makkah, different inputs
#   5. watch:  receives and stores them, and shows the next prayer
#   6. shell:  terminate the companion and check that it isn't running
#   7. watch:  a new launch shows Makkah's schedule from the watch's own storage
#   8. watch:  add the complication to the Smart Stack, so WidgetKit runs the extension
#   9. watch:  store the ended timetable (`-preset mosqueEnded`), which reloads the complication
#  10. watch:  remove the inputs (`-resetInputs`), which reloads the complication
#  11. shell:  read the complication extension's timeline log from the watch's App Group and
#              check that the extension built, after the companion closed, a timeline from
#              Makkah's inputs, one with the ended-timetable state and one with the setup
#              state; collect the example's os_log lines from both simulators
#
# Usage: Scripts/paired-journeys.sh <iPhone UDID> <Watch UDID> [derived data path]
#
# Create and pair the simulators first (README, The paired journey). The script boots both and
# shuts them down at the end. Results, logs and the timeline log go to
# <derived data>/paired-results.

set -euo pipefail

cd "$(dirname "$0")/.."

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <iPhone UDID> <Watch UDID> [derived data path]" >&2
  exit 2
fi
phone="$1"
watch="$2"
derived="${3:-.derived/paired}"
results="${derived}/paired-results"
project=WatchComplication.xcodeproj
companion_id=io.github.salah-kit.WatchComplication
watch_id=io.github.salah-kit.WatchComplication.watchkitapp
group_id=group.io.github.salah-kit.WatchComplication
mkdir -p "${results}"
started="$(date '+%Y-%m-%d %H:%M:%S')"

shutdown() {
  xcrun simctl shutdown "${phone}" 2>/dev/null || true
  xcrun simctl shutdown "${watch}" 2>/dev/null || true
}
trap shutdown EXIT

echo "== Building for both simulators"
xcodebuild build-for-testing -project "${project}" -scheme WatchComplication \
  -destination "id=${phone}" -derivedDataPath "${derived}" -quiet
xcodebuild build-for-testing -project "${project}" -scheme WatchComplicationWatch \
  -destination "id=${watch}" -derivedDataPath "${derived}" -quiet

echo "== Booting the pair"
xcrun simctl boot "${phone}" 2>/dev/null || true
xcrun simctl boot "${watch}" 2>/dev/null || true
xcrun simctl bootstatus "${phone}" -b >/dev/null
xcrun simctl bootstatus "${watch}" -b >/dev/null
xcrun simctl list pairs | grep -A2 -E "${watch}|${phone}" || true

echo "== Fresh installs"
xcrun simctl uninstall "${phone}" "${companion_id}" 2>/dev/null || true
xcrun simctl uninstall "${watch}" "${watch_id}" 2>/dev/null || true
xcrun simctl install "${phone}" "${derived}/Build/Products/Debug-iphonesimulator/WatchComplication.app"
xcrun simctl install "${watch}" \
  "${derived}/Build/Products/Debug-watchsimulator/WatchComplicationWatch.app"

# One journey step: an XCUITest method on one simulator. TEST_RUNNER_ passes the variable to the
# test runner without the prefix.
step() {
  local name="$1" scheme="$2" udid="$3" test="$4"
  echo "== Step ${name}: ${test}"
  rm -rf "${results:?}/${name}.xcresult"
  TEST_RUNNER_WATCHCOMPLICATION_PAIRED=1 xcodebuild test-without-building \
    -project "${project}" -scheme "${scheme}" -destination "id=${udid}" \
    -derivedDataPath "${derived}" -only-testing:"${test}" \
    -resultBundlePath "${results}/${name}.xcresult" 2>&1 \
    | tee "${results}/${name}.log" | grep -E "Test Case|error:|WATCHCOMPLICATION|TEST (SUCC|FAIL)"
}

step 1-watch-fresh WatchComplicationWatch "${watch}" \
  WatchUITests/WatchPairedJourney/test1FreshWatchHasNoSettings
step 2-phone-send-ended WatchComplication "${phone}" \
  CompanionUITests/CompanionPairedJourney/test1SendTheEndedTimetable
step 3-watch-receive-ended WatchComplicationWatch "${watch}" \
  WatchUITests/WatchPairedJourney/test2ReceivesTheEndedTimetable
step 4-phone-send-makkah WatchComplication "${phone}" \
  CompanionUITests/CompanionPairedJourney/test2SendMakkah
step 5-watch-receive-makkah WatchComplicationWatch "${watch}" \
  WatchUITests/WatchPairedJourney/test3ReceivesMakkah

echo "== Step 6: terminating the companion"
xcrun simctl terminate "${phone}" "${companion_id}" 2>/dev/null || true
sleep 2
if xcrun simctl spawn "${phone}" launchctl list | grep -q "UIKitApplication:${companion_id}\["; then
  echo "error: the companion is still running" >&2
  exit 1
fi
closed="$(date +%s)"
echo "Companion not running since $(date -r "${closed}")"

step 7-watch-phone-app-closed WatchComplicationWatch "${watch}" \
  WatchUITests/WatchPairedJourney/test4WorksWithThePhoneAppClosed

step 8-watch-smart-stack WatchComplicationWatch "${watch}" \
  WatchUITests/WatchSmartStackJourney/test5AddTheComplicationToTheSmartStack
step 9-watch-ended-in-complication WatchComplicationWatch "${watch}" \
  WatchUITests/WatchSmartStackJourney/test6TheEndedTimetableReachesTheComplication
step 10-watch-missing-in-complication WatchComplicationWatch "${watch}" \
  WatchUITests/WatchSmartStackJourney/test7MissingSettingsReachTheComplication

echo "== Step 11: evidence"
sleep 5
makkah="$(grep -ho 'WATCHCOMPLICATION sent makkah: [0-9a-f]*' "${results}/4-phone-send-makkah.log" \
  | awk '{ print $4 }' | tail -n 1)"
group="$(xcrun simctl get_app_container "${watch}" "${watch_id}" groups \
  | awk -v id="${group_id}" '$1 == id { print $2 }')"
plist="${group}/Library/Preferences/${group_id}.plist"
python3 - "${plist}" "${closed}" "${makkah}" > "${results}/timeline-log.txt" <<'EOF'
import json, plistlib, sys
from datetime import datetime, timezone
path, closed, makkah = sys.argv[1], float(sys.argv[2]), sys.argv[3]
# JSONEncoder writes dates as seconds since 2001-01-01.
reference = 978307200
def iso(seconds):
    return datetime.fromtimestamp(seconds + reference, timezone.utc).isoformat()
with open(path, "rb") as f:
    prefs = plistlib.load(f)
print(f"App Group keys: {sorted(prefs)}")
records = json.loads(prefs["timelineLog.v1"]) if "timelineLog.v1" in prefs else []
print(f"Timeline records: {len(records)}; the companion closed at {iso(closed - reference)}")
after_close = [r for r in records if r["requestedAt"] + reference >= closed]
checks = {
    f"a timeline from Makkah's inputs ({makkah}) after the companion closed":
        any(r["inputs"] == makkah and r["states"].startswith("next×") for r in after_close),
    "a timeline with the ended-timetable state":
        any("timetableEnded×" in r["states"] for r in after_close),
    "a timeline with the setup state and no inputs":
        any(r["inputs"] == "none" and r["states"] == "setup×1" for r in after_close),
}
for record in records:
    after = " (after the companion closed)" if record["requestedAt"] + reference >= closed else ""
    for key in ("requestedAt", "firstEntry", "lastEntry", "validUntil"):
        if key in record:
            record[key] = iso(record[key])
    print(json.dumps(record, sort_keys=True) + after)
for name, passed in checks.items():
    print(("PASS " if passed else "FAIL ") + name)
EOF
cat "${results}/timeline-log.txt"
predicate='subsystem == "io.github.salah-kit.WatchComplication"'
xcrun simctl spawn "${watch}" log show --start "${started}" \
  --predicate "${predicate}" --style compact > "${results}/watch-log.txt" 2>/dev/null || true
xcrun simctl spawn "${phone}" log show --start "${started}" \
  --predicate "${predicate}" --style compact > "${results}/phone-log.txt" 2>/dev/null || true
echo "-- watch log"
cat "${results}/watch-log.txt"
echo "-- iPhone log"
cat "${results}/phone-log.txt"
if grep -q '^FAIL ' "${results}/timeline-log.txt"; then
  echo "error: the complication extension's log lacks a required timeline" >&2
  exit 1
fi
echo "== Paired journey passed; results in ${results}"
