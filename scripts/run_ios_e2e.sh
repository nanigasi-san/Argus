#!/usr/bin/env bash
# Run every portable E2E suite against a booted iOS Simulator.
set -euo pipefail
device_id="${1:?Usage: bash scripts/run_ios_e2e.sh <simulator-udid>}"
output_dir=build/e2e/ios
mkdir -p "$output_dir"
: > "$output_dir/results.txt"
test_roots=()
for root in integration_test e2e; do
  if [ -d "$root" ]; then test_roots+=("$root"); fi
done
test_files=()
if [ "${#test_roots[@]}" -gt 0 ]; then
  while IFS= read -r test_file; do
    test_files+=("$test_file")
  done < <(find "${test_roots[@]}" -type f -name '*_test.dart' | LC_ALL=C sort)
fi
if [ "${#test_files[@]}" -eq 0 ]; then
  echo 'No E2E test files found in integration_test/ or e2e/.' >&2
  exit 1
fi
printf '%s\n' "${test_files[@]}" > "$output_dir/suites.txt"
flutter --version > "$output_dir/flutter-version.txt"
xcodebuild -version > "$output_dir/xcode-version.txt"
xcrun simctl list devices available -j > "$output_dir/simulators.json"

capture_diagnostics() {
  xcrun simctl spawn "$device_id" log show --last 30m --style compact \
    --predicate 'process == "Runner"' > "$output_dir/simulator.log" 2>&1 || true
  xcrun simctl io "$device_id" screenshot "$output_dir/final-screen.png" 2>/dev/null || true
}
trap capture_diagnostics EXIT

result=0
for test_file in "${test_files[@]}"; do
  suite="${test_file%_test.dart}"
  suite="${suite//\//_}"
  # Virtual headings are injected in Dart; no magnetic sensor is required.
  # Native GPS remains a separate opt-in mode (SIMULATOR_GPS is not enabled).
  if flutter drive --driver=test_driver/ui_smoke_driver.dart \
      --target="$test_file" -d "$device_id" \
      2>&1 | tee "$output_dir/${suite}.log"; then
    echo "$suite: success" | tee -a "$output_dir/results.txt"
  else
    echo "$suite: failure" | tee -a "$output_dir/results.txt"
    result=1
  fi
done
exit "$result"
