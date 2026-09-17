#!/usr/bin/env python3
"""Build the normal app and all native tests once, then run the built tests."""
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess
import sys
import time

import ios_simulator
from ios_build_process import build_app


REPORT = Path("build/ios-native-tests")
DERIVED_DATA = REPORT / "DerivedData"


def run_build():
    REPORT.mkdir(parents=True, exist_ok=True)
    device = ios_simulator.select_device()
    started = time.monotonic()
    arguments = ["-workspace", "ios/Runner.xcworkspace", "-scheme", "Runner",
                 "-configuration", "Debug", "-sdk", "iphonesimulator",
                 "-derivedDataPath", str(DERIVED_DATA), "CODE_SIGNING_ALLOWED=NO",
                 "COMPILER_INDEX_STORE_ENABLE=NO"]
    # Finish Flutter's Xcode/Simulator probes before starting a cold boot.
    subprocess.run(["flutter", "build", "ios", "--simulator", "--debug",
                    "--config-only", "--target=lib/main.dart"], check=True)
    with ThreadPoolExecutor(max_workers=1) as pool:
        ready = None

        def start_boot():
            nonlocal ready
            ready = pool.submit(ios_simulator.boot, device, REPORT)
        # Flutter prepares plugins, CocoaPods and the normal Dart entry point;
        # Xcode then builds Runner and every test bundle in one output tree.
        build_app(["xcodebuild", "build-for-testing", *arguments,
                   "-destination", "generic/platform=iOS Simulator"], start_boot)
        build_seconds = time.monotonic() - started
        ready.result()  # A successful build never bypasses failed Simulator startup.
    tests_started = time.monotonic()
    # These short XCTest cases do not benefit from launching a cloned Simulator.
    # No test filters or test retries: run the entire scheme on the ready device.
    subprocess.run(["xcodebuild", "test-without-building", *arguments,
                    "-destination", f"platform=iOS Simulator,id={device}",
                    "-parallel-testing-enabled", "NO", "-resultBundlePath",
                    str(REPORT / "Tests.xcresult")], check=True)
    summary = subprocess.run([
        "xcrun", "xcresulttool", "get", "test-results", "summary", "--path",
        str(REPORT / "Tests.xcresult"),
    ], check=True, capture_output=True, text=True, timeout=30)
    result = json.loads(summary.stdout)
    (REPORT / "test-results.json").write_text(summary.stdout, encoding="utf-8")
    if (result["totalTestCount"] <= 0 or result["failedTests"] != 0
            or result["skippedTests"] != 0
            or result["passedTests"] != result["totalTestCount"]):
        raise ValueError("Native XCTest did not execute every test successfully")
    (REPORT / "timings.json").write_text(json.dumps({
        "device": device, "buildSeconds": build_seconds,
        "testsSeconds": time.monotonic() - tests_started,
        "totalSeconds": time.monotonic() - started,
    }, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    try:
        run_build()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired,
            ValueError, OSError, KeyError, StopIteration) as error:
        print(f"[error] {error}", file=sys.stderr)
        sys.exit(error.returncode if isinstance(error, subprocess.CalledProcessError) else 1)
