#!/usr/bin/env bash
# Run every portable E2E suite against a booted iOS Simulator.
set -euo pipefail
device_id="${1:?Usage: bash scripts/run_ios_e2e.sh <simulator-udid>}"
output_dir=build/e2e/ios
suite_timeout="${E2E_IOS_SUITE_TIMEOUT_SECONDS:-900}"
bounded() { python3 scripts/run_with_timeout.py "$@"; }
mkdir -p "$output_dir"
: > "$output_dir/results.txt"
python3 scripts/generate_e2e_entrypoint.py "$output_dir"
flutter --version > "$output_dir/flutter-version.txt"
xcodebuild -version > "$output_dir/xcode-version.txt"
xcrun simctl list devices available -j > "$output_dir/simulators.json"

capture_diagnostics() {
  bounded 30 xcrun simctl spawn "$device_id" log show --last 30m --style compact \
    --predicate 'process == "Runner" OR process == "installd"' > "$output_dir/simulator.log" 2>&1 || true
  bounded 15 xcrun simctl io "$device_id" screenshot "$output_dir/final-screen.png" 2>/dev/null || true
  ps -axo pid,ppid,state,etime,comm > "$output_dir/processes.txt"
}
trap capture_diagnostics EXIT

result=0
test_file=integration_test/ci_all_suites.dart
suite=all_suites
export E2E_REPORT_DIR="$output_dir"
# Virtual headings are injected in Dart; no magnetic sensor is required.
# Native GPS remains a separate opt-in mode (SIMULATOR_GPS is not enabled).
echo "[$(date -u '+%FT%TZ')] Starting $test_file (timeout ${suite_timeout}s)"
if bounded "$suite_timeout" flutter drive --verbose --driver=test_driver/ui_smoke_driver.dart \
    --target="$test_file" -d "$device_id" \
    2>&1 | tee "$output_dir/${suite}.log"; then
  echo "$suite: success" | tee -a "$output_dir/results.txt"
else
  status=$?
  echo "$suite: failure (exit $status)" | tee -a "$output_dir/results.txt"
  bounded 15 xcrun simctl io "$device_id" screenshot "$output_dir/${suite}-failure.png" 2>/dev/null || true
  result=1
fi
exit "$result"
