#!/usr/bin/env bash
# Run inside the pinned Linux Connect IQ environment used by Garmin Tests.
set -euo pipefail

device=${1:-fr55}
project=garmin/argus-data-field
output=build/garmin-tests
mkdir -p "$output"
key_dir=$(mktemp -d)
simulator_pid=
display_pid=
cleanup() {
  if [[ -n "$simulator_pid" ]]; then kill "$simulator_pid" 2>/dev/null || true; fi
  if [[ -n "$display_pid" ]]; then kill "$display_pid" 2>/dev/null || true; fi
  rm -f "$key_dir/key.pem" "$key_dir/key.der"
  rmdir "$key_dir"
}
trap cleanup EXIT

# This throwaway key is for simulator builds only and is never uploaded.
openssl genrsa -out "$key_dir/key.pem" 4096
openssl pkcs8 -topk8 -inform PEM -outform DER \
  -in "$key_dir/key.pem" -out "$key_dir/key.der" -nocrypt
cat /connectiq/bin/version.txt | tee "$output/sdk-version.txt"
printf '%s\n' "$device" > "$output/device.txt"

timeout 180 monkeyc -f "$project/monkey.jungle" -d "$device" \
  -y "$key_dir/key.der" -o "$output/ARGUS.prg" -l 0 \
  2>&1 | tee "$output/build.log"
timeout 180 monkeyc -f "$project/monkey.jungle" -d "$device" \
  -y "$key_dir/key.der" -o "$output/ARGUS-tests.prg" -l 0 --unit-test \
  2>&1 | tee "$output/test-build.log"

export DISPLAY=:99
Xvfb "$DISPLAY" -screen 0 1280x1024x24 > "$output/display.log" 2>&1 &
display_pid=$!
timeout 30 bash -c 'until [[ -S /tmp/.X11-unix/X99 ]]; do sleep 1; done'
simulator > "$output/simulator.log" 2>&1 &
simulator_pid=$!
# The simulator listens on the local Connect IQ transport port.
timeout 60 bash -c 'until (echo > /dev/tcp/127.0.0.1/1234) 2>/dev/null; do sleep 1; done'

# SDK monkeydo can return 1 even after PASSED. Preserve its status and require
# the host verifier to check the full summary and every discovered test count.
set +e
timeout 300 monkeydo "$output/ARGUS-tests.prg" "$device" -t \
  > "$output/tests.log" 2>&1
status=$?
set -e
printf '%s\n' "$status" > "$output/exit-code.txt"
cat "$output/tests.log"
if (( status > 1 )); then exit "$status"; fi
