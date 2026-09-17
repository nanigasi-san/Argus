"""Shared Simulator selection and bounded startup for iOS CI."""
import json
from pathlib import Path
import subprocess
import time


def select_device():
    result = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "-j"],
                            check=True, capture_output=True, text=True, timeout=120)
    devices = json.loads(result.stdout)["devices"]
    return next(device["udid"] for runtime, entries in devices.items()
                if "iOS" in runtime for device in entries
                if "iPhone" in device.get("deviceTypeIdentifier", "")
                and device["isAvailable"])


def boot(device, report):
    started = time.monotonic()
    print(f"[simulator] Booting {device} after the build", flush=True)
    # Only an already-booted device may bypass boot; other errors must fail CI.
    result = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "-j"],
                            check=True, capture_output=True, text=True, timeout=120)
    devices = json.loads(result.stdout)["devices"]
    current = next(entry for entries in devices.values() for entry in entries
                   if entry["udid"] == device)
    if current["state"] != "Booted":
        subprocess.run(["xcrun", "simctl", "boot", device], check=True, timeout=60)
    # The Simulator GUI may boot its current device automatically. Open it only
    # after simctl boot, so it cannot race with our state check and boot command.
    subprocess.run(["open", "-a", "Simulator", "--args", "-CurrentDeviceUDID", device],
                   check=True, timeout=30)
    subprocess.run(["xcrun", "simctl", "bootstatus", device, "-b"],
                   check=True, timeout=420)
    elapsed = time.monotonic() - started
    Path(report, "simulator-boot.json").write_text(json.dumps({
        "device": device, "seconds": elapsed, "ready": True,
    }, indent=2) + "\n", encoding="utf-8")
    print(f"[simulator] Ready after {elapsed:.1f}s", flush=True)
    # Preserve the boot diagnostic without serializing it ahead of the build.
    try:
        subprocess.run(["xcrun", "simctl", "io", device, "screenshot",
                        str(Path(report, "boot-screen.png"))], check=True, timeout=30)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        print("::warning::Simulator boot screenshot unavailable; continuing tests", flush=True)
