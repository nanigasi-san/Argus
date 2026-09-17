#!/usr/bin/env bash
# Discover and run all portable Flutter E2E suites, retaining every result.
set -euo pipefail
device_id="${1:-emulator-5554}"
mkdir -p build/e2e
: > build/e2e/results.txt
python3 scripts/generate_e2e_entrypoint.py build/e2e
flutter --version > build/e2e/flutter-version.txt
adb -s "$device_id" shell getprop ro.build.version.sdk > build/e2e/android-api.txt
adb -s "$device_id" logcat -c

capture_diagnostics() {
  adb -s "$device_id" logcat -d > build/e2e/logcat.txt 2>&1 || true
  adb -s "$device_id" exec-out screencap -p > build/e2e/final-screen.png 2>/dev/null || true
}
trap capture_diagnostics EXIT

result=0
test_file=integration_test/ci_all_suites.dart
suite=all_suites
export E2E_REPORT_DIR=build/e2e
# The extended driver exports integration_test screenshots to the host.
if flutter drive --driver=test_driver/ui_smoke_driver.dart \
    --target="$test_file" -d "$device_id" \
    2>&1 | tee "build/e2e/${suite}.log"; then
  echo "$suite: success" | tee -a build/e2e/results.txt
else
  echo "$suite: failure" | tee -a build/e2e/results.txt
  result=1
fi
exit "$result"
