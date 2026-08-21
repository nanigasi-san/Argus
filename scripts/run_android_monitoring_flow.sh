#!/usr/bin/env bash

set -euo pipefail

flutter build apk --debug --no-pub \
  --target=integration_test/monitoring_review_geojson_test.dart
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell pm grant \
  com.argus.orienteering \
  android.permission.ACCESS_COARSE_LOCATION
adb shell pm grant \
  com.argus.orienteering \
  android.permission.ACCESS_FINE_LOCATION
adb shell pm grant \
  com.argus.orienteering \
  android.permission.ACCESS_BACKGROUND_LOCATION

while true; do
  adb emu geo fix 139.767125 35.681236
  sleep 2
done &
location_injector_pid=$!

cleanup() {
  kill "$location_injector_pid" 2>/dev/null || true
  wait "$location_injector_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

flutter drive --no-pub \
  --use-application-binary=build/app/outputs/flutter-apk/app-debug.apk \
  --driver=test_driver/ui_smoke_driver.dart \
  --target=integration_test/monitoring_review_geojson_test.dart
