#!/usr/bin/env python3
"""Run a command with progress messages and a process-group time limit."""
import argparse
import math
import os
import signal
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("seconds", type=float)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not math.isfinite(args.seconds) or args.seconds <= 0 or not args.command:
        parser.error("a positive timeout and command are required")
    process = subprocess.Popen(args.command, start_new_session=True)
    started = time.monotonic()

    def stop(signum, _frame=None):
        try:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pass
        except ProcessLookupError:
            pass
        finally:
            # Also stop descendants if their parent exited before they did.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
        return 124 if signum is None else 128 + signum

    def interrupted(signum, frame):
        sys.exit(stop(signum, frame))

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    while True:
        elapsed = time.monotonic() - started
        remaining = args.seconds - elapsed
        if remaining <= 0:
            print(f"[timeout] {args.command[0]} exceeded {args.seconds:g}s", flush=True)
            return stop(None)
        try:
            code = process.wait(timeout=min(30, remaining))
            return code if code >= 0 else 128 - code
        except subprocess.TimeoutExpired:
            print(f"[progress] {args.command[0]} running for {time.monotonic() - started:.0f}s", flush=True)


if __name__ == "__main__":
    sys.exit(main())
