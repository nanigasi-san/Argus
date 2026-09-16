#!/usr/bin/env bash
# Discover and run all portable Flutter E2E suites, retaining every result.
set -euo pipefail
device_id="${1:-emulator-5554}"
mkdir -p build/e2e
: > build/e2e/results.txt
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
printf '%s\n' "${test_files[@]}" > build/e2e/suites.txt
flutter --version > build/e2e/flutter-version.txt
adb -s "$device_id" shell getprop ro.build.version.sdk > build/e2e/android-api.txt
adb -s "$device_id" logcat -c

capture_diagnostics() {
  adb -s "$device_id" logcat -d > build/e2e/logcat.txt 2>&1 || true
  adb -s "$device_id" exec-out screencap -p > build/e2e/final-screen.png 2>/dev/null || true
}
trap capture_diagnostics EXIT

result=0
for test_file in "${test_files[@]}"; do
  suite="${test_file%_test.dart}"
  suite="${suite//\//_}"
  # The extended driver exports integration_test screenshots to the host.
  if flutter drive --driver=test_driver/ui_smoke_driver.dart \
      --target="$test_file" -d "$device_id" \
      2>&1 | tee "build/e2e/${suite}.log"; then
    echo "$suite: success" | tee -a build/e2e/results.txt
  else
    echo "$suite: failure" | tee -a build/e2e/results.txt
    result=1
  fi
done
exit "$result"
