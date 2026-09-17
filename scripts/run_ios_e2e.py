#!/usr/bin/env python3
"""Build all iOS E2E suites and attach using the current app's persisted VM URI."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
import ipaddress
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import time
from urllib.parse import urlsplit

import ios_simulator
from ios_build_process import build_app


TARGET = "integration_test/ci_all_suites.dart"
APP = Path("build/ios/iphonesimulator/Runner.app")
VM_MESSAGE = "The Dart VM service is listening on "


def vm_service_uri(output, pid, started):
    # `log show --style json` can prefix its JSON array with a filter description.
    array_start = output.find("[")
    if array_start < 0:
        raise ValueError("Simulator log show did not return a JSON array")
    events = json.loads(output[array_start:])
    if not isinstance(events, list):
        raise ValueError("Simulator log show did not return a JSON array")
    for event in reversed(events):
        if event.get("processID") != pid:
            continue
        timestamp = datetime.fromisoformat(event["timestamp"])
        if timestamp < started:
            continue
        message = event.get("eventMessage", "")
        if VM_MESSAGE not in message:
            continue
        uri = message.split(VM_MESSAGE, 1)[1].split()[0]
        parsed = urlsplit(uri)
        if (parsed.scheme != "http" or not parsed.port
                or not ipaddress.ip_address(parsed.hostname).is_loopback):
            raise ValueError(f"Unexpected Simulator VM Service URI: {uri}")
        return uri
    return None


def wait_for_vm_service(device, executable, pid, started, report, timeout=120):
    deadline = time.monotonic() + timeout
    predicate = (f"processImagePath ENDSWITH {json.dumps('/' + executable)} AND "
                 f"eventMessage CONTAINS {json.dumps(VM_MESSAGE)}")
    command = ["xcrun", "simctl", "spawn", device, "log", "show",
               "--start", started.strftime("%Y-%m-%d %H:%M:%S"),
               "--style", "json", "--info", "--debug", "--predicate", predicate]
    while time.monotonic() < deadline:
        try:
            logs = subprocess.run(command, check=True, capture_output=True, text=True,
                                  timeout=min(15, max(0.1, deadline - time.monotonic())))
        except subprocess.TimeoutExpired:
            print("[vm-service] Simulator log query timed out; reading saved logs again",
                  flush=True)
        else:
            (report / "vm-service-log.json").write_text(logs.stdout, encoding="utf-8")
            uri = vm_service_uri(logs.stdout, pid, started)
            if uri is not None:
                return uri
        print(f"[vm-service] Waiting for saved VM Service URI for PID {pid}", flush=True)
        time.sleep(min(2, max(0, deadline - time.monotonic())))
    raise TimeoutError(f"No saved VM Service URI for PID {pid} within {timeout}s")


def run_e2e(device, report, boot_simulator=False):
    # Build once; the generated target registers every discovered E2E file.
    print("[build] Building all iOS E2E suites", flush=True)
    started_build = time.monotonic()
    with ThreadPoolExecutor(max_workers=1) as pool:
        ready = None

        def start_boot():
            nonlocal ready
            ready = pool.submit(ios_simulator.boot, device, report)

        command = ["flutter", "build", "ios", "--simulator", "--debug", f"--target={TARGET}"]
        if boot_simulator:
            command.append("--verbose")  # Expose Xcode's post-preparation milestone.
        build_app(command, start_boot if boot_simulator else None)
        build_seconds = time.monotonic() - started_build
        if ready is not None:
            ready.result()  # Install and launch only after successful bootstatus.
    (report / "build-timing.json").write_text(json.dumps({
        "buildSeconds": build_seconds,
        "buildAndBootSeconds": time.monotonic() - started_build,
    }, indent=2) + "\n", encoding="utf-8")
    with (APP / "Info.plist").open("rb") as file:
        info = plistlib.load(file)
    bundle = info["CFBundleIdentifier"]
    executable = info["CFBundleExecutable"]
    (report / "bundle-id.txt").write_text(bundle, encoding="utf-8")
    subprocess.run(["xcrun", "simctl", "install", device, str(APP)],
                   check=True, timeout=120)

    # Match both the new PID and its launch time, never a previous app's URI.
    started = datetime.now().astimezone().replace(microsecond=0)
    print(f"[launch] Starting {bundle} paused", flush=True)
    launch = subprocess.run(
        ["xcrun", "simctl", "launch", "--terminate-running-process", device, bundle,
         "--enable-dart-profiling", "--disable-vm-service-publication", "--start-paused",
         "--enable-checked-mode", "--verify-entry-points"],
        check=True, capture_output=True, text=True, timeout=90,
    )
    print(launch.stdout, end="", flush=True)
    match = re.search(rf"^{re.escape(bundle)}: (\d+)\s*$", launch.stdout, re.MULTILINE)
    if match is None:
        raise ValueError(f"Cannot determine launched app PID: {launch.stdout!r}")
    pid = int(match.group(1))
    (report / "launch.json").write_text(json.dumps({
        "bundleId": bundle, "executable": executable, "pid": pid,
        "startedAt": started.isoformat(),
    }, indent=2) + "\n", encoding="utf-8")
    uri = wait_for_vm_service(device, executable, pid, started, report)
    (report / "vm-service-uri.txt").write_text(uri + "\n", encoding="utf-8")
    print(f"[driver] Connecting to saved VM Service URI for PID {pid}: {uri}", flush=True)
    # Leave the app running for the shell's final diagnostics and cleanup.
    return subprocess.run([
        "flutter", "drive", "--verbose", "--driver=test_driver/ui_smoke_driver.dart",
        f"--target={TARGET}", "-d", device, f"--use-existing-app={uri}",
        "--keep-app-running",
    ]).returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("device")
    parser.add_argument("report", type=Path)
    parser.add_argument("--boot-simulator", action="store_true")
    args = parser.parse_args()
    args.report.mkdir(parents=True, exist_ok=True)
    try:
        return run_e2e(args.device, args.report, args.boot_simulator)
    except subprocess.CalledProcessError as error:
        print(f"[error] Command failed: {error.cmd}\n{error.stderr or ''}", file=sys.stderr)
        return error.returncode
    except (TimeoutError, subprocess.TimeoutExpired, ValueError, OSError, KeyError) as error:
        print(f"[error] {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
