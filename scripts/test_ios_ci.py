"""Regression tests for sequential preparation and complete native test results."""
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import ios_simulator
import run_ios_build as native
import run_ios_e2e as e2e


class SimulatorTests(unittest.TestCase):
    def test_selects_only_available_iphones_from_ios_runtimes(self):
        devices = {"devices": {
            "tvOS-26": [{"udid": "tv", "isAvailable": True,
                          "deviceTypeIdentifier": "Apple-TV"}],
            "iOS-26": [
                {"udid": "unavailable", "isAvailable": False,
                 "deviceTypeIdentifier": "iPhone-17-Pro"},
                {"udid": "tablet", "isAvailable": True, "deviceTypeIdentifier": "iPad-Pro"},
                {"udid": "phone", "isAvailable": True, "deviceTypeIdentifier": "iPhone-17-Pro"},
            ],
        }}
        with patch.object(ios_simulator.subprocess, "run", return_value=
                          subprocess.CompletedProcess([], 0, json.dumps(devices))) as run:
            self.assertEqual(ios_simulator.select_device(), "phone")
        self.assertEqual(run.call_count, 1)
        self.assertEqual(run.call_args.kwargs["timeout"], 300)

    def run_boot(self, state="Shutdown", boot_failure=False):
        devices = {"devices": {"iOS-26": [{"udid": "device", "state": state}]}}
        commands = []

        def execute(command, **kwargs):
            commands.append((command, kwargs))
            if command[:3] == ["xcrun", "simctl", "boot"] and boot_failure:
                raise subprocess.CalledProcessError(1, command)
            return subprocess.CompletedProcess(command, 0, json.dumps(devices))

        with tempfile.TemporaryDirectory() as directory, \
                patch.object(ios_simulator.subprocess, "run", side_effect=execute):
            ios_simulator.boot("device", Path(directory))
            self.assertTrue(json.loads(Path(directory, "simulator-boot.json").read_text())["ready"])
        return commands

    def test_cold_boot_requires_bounded_readiness(self):
        commands = self.run_boot()
        self.assertTrue(any(command[:3] == ["xcrun", "simctl", "boot"]
                            for command, _ in commands))
        boot_index = next(index for index, (command, _) in enumerate(commands)
                          if command[:3] == ["xcrun", "simctl", "boot"])
        gui_index = next(index for index, (command, _) in enumerate(commands)
                         if command[0] == "open")
        self.assertLess(boot_index, gui_index, "Simulator GUI must not race simctl boot")
        readiness_index = next(index for index, (command, _) in enumerate(commands)
                               if "bootstatus" in command)
        self.assertLess(readiness_index, gui_index, "Device startup must finish before GUI launch")
        self.assertEqual(commands[readiness_index],
                         (["xcrun", "simctl", "bootstatus", "device", "-b"],
                          {"check": True, "timeout": 420}))
        self.assertEqual(commands[gui_index][1], {"check": True, "timeout": 120})

    def test_already_booted_device_still_requires_readiness(self):
        commands = self.run_boot(state="Booted")
        self.assertFalse(any(command[:3] == ["xcrun", "simctl", "boot"]
                             for command, _ in commands))
        self.assertTrue(any("bootstatus" in command for command, _ in commands))

    def test_boot_errors_are_not_ignored(self):
        with self.assertRaises(subprocess.CalledProcessError):
            self.run_boot(boot_failure=True)


class SequentialPreparationTests(unittest.TestCase):
    def run_e2e(self, failure=None, boot_simulator=True):
        events = []

        def boot(*args):
            events.append("boot")
            if failure == "boot":
                raise TimeoutError("boot failed")

        def execute(command, **kwargs):
            if command[:2] == ["flutter", "build"]:
                action = "build"
            elif command[:3] == ["xcrun", "simctl", "install"]:
                action = "install"
            elif command[:3] == ["xcrun", "simctl", "launch"]:
                action = "launch"
            else:
                action = "drive"
            events.append(action)
            if failure == action:
                raise subprocess.CalledProcessError(7, command)
            return subprocess.CompletedProcess(command, 0, "com.argus: 123\n")

        def vm_uri(*args):
            events.append("uri")
            if failure == "uri":
                raise TimeoutError("VM Service unavailable")
            return "http://127.0.0.1:123/a/"

        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory)
            app = report / "Runner.app"
            app.mkdir()
            with (app / "Info.plist").open("wb") as file:
                plistlib.dump({"CFBundleIdentifier": "com.argus", "CFBundleExecutable": "Runner"}, file)
            with patch.object(e2e, "APP", app), \
                    patch.object(e2e.ios_simulator, "boot", side_effect=boot), \
                    patch.object(e2e.subprocess, "run", side_effect=execute), \
                    patch.object(e2e, "wait_for_vm_service", side_effect=vm_uri):
                if failure:
                    with self.assertRaises((subprocess.CalledProcessError, TimeoutError)):
                        e2e.run_e2e("device", report, boot_simulator=boot_simulator)
                else:
                    self.assertEqual(e2e.run_e2e("device", report, boot_simulator=boot_simulator), 0)
        return events

    def test_e2e_completes_build_then_boot_then_install_launch_uri_and_drive(self):
        self.assertEqual(self.run_e2e(), ["build", "boot", "install", "launch", "uri", "drive"])

    def test_e2e_failure_at_each_step_prevents_every_later_step(self):
        steps = ["build", "boot", "install", "launch", "uri", "drive"]
        for index, step in enumerate(steps):
            with self.subTest(step=step):
                self.assertEqual(self.run_e2e(failure=step), steps[:index + 1])

    def test_local_e2e_keeps_already_running_device(self):
        self.assertEqual(self.run_e2e(boot_simulator=False),
                         ["build", "install", "launch", "uri", "drive"])


class NativeTests(unittest.TestCase):
    def run_native(self, summary=None, failing_action=None):
        if summary is None:
            summary = {"totalTestCount": 4, "passedTests": 4, "failedTests": 0, "skippedTests": 0}
        commands = []
        events = []

        def boot(*args):
            events.append("boot")
            if failing_action == "boot":
                raise TimeoutError("boot failed")

        def execute(command, **kwargs):
            commands.append(command)
            if command[:2] == ["flutter", "build"]:
                action = "--config-only"
            elif command[0] == "xcodebuild":
                action = command[1]
            else:
                action = "summary"
            events.append(action)
            if failing_action == action:
                raise subprocess.CalledProcessError(7, command)
            return subprocess.CompletedProcess(command, 0, json.dumps(summary))

        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory)
            with patch.object(native, "REPORT", report), \
                    patch.object(native, "DERIVED_DATA", report / "DerivedData"), \
                    patch.object(native.ios_simulator, "select_device", return_value="device"), \
                    patch.object(native.ios_simulator, "boot", side_effect=boot), \
                    patch.object(native.subprocess, "run", side_effect=execute):
                if failing_action:
                    with self.assertRaises((subprocess.CalledProcessError, TimeoutError)):
                        native.run_build()
                else:
                    native.run_build()
                    self.assertEqual(json.loads((report / "test-results.json").read_text()), summary)
        return commands, events

    def test_builds_normal_app_and_all_native_tests_once_and_executes_same_products(self):
        commands, events = self.run_native()
        self.assertEqual(events, ["--config-only", "build-for-testing", "boot",
                                  "test-without-building", "summary"])
        self.assertIn("--config-only", commands[0])
        self.assertIn("--target=lib/main.dart", commands[0])
        self.assertEqual(commands[1][:2], ["xcodebuild", "build-for-testing"])
        self.assertEqual(commands[2][:2], ["xcodebuild", "test-without-building"])
        self.assertIn("generic/platform=iOS Simulator", commands[1])
        for command in commands[1:3]:
            self.assertFalse(any(arg.startswith(("-only-testing", "-skip-testing")) for arg in command))
        self.assertEqual(commands[1][commands[1].index("-derivedDataPath") + 1],
                         commands[2][commands[2].index("-derivedDataPath") + 1])
        self.assertEqual(commands[2][commands[2].index("-parallel-testing-enabled") + 1], "NO")

    def test_native_failure_at_each_step_prevents_every_later_step(self):
        steps = ["--config-only", "build-for-testing", "boot", "test-without-building", "summary"]
        for index, step in enumerate(steps):
            with self.subTest(step=step):
                _, events = self.run_native(failing_action=step)
                self.assertEqual(events, steps[:index + 1])

    def test_empty_skipped_failed_or_incomplete_results_fail(self):
        summaries = [
            {"totalTestCount": 0, "passedTests": 0, "failedTests": 0, "skippedTests": 0},
            {"totalTestCount": 4, "passedTests": 3, "failedTests": 0, "skippedTests": 1},
            {"totalTestCount": 4, "passedTests": 3, "failedTests": 1, "skippedTests": 0},
            {"totalTestCount": 4, "passedTests": 3, "failedTests": 0, "skippedTests": 0},
        ]
        for summary in summaries:
            with self.subTest(summary=summary), self.assertRaises(ValueError):
                self.run_native(summary=summary)


if __name__ == "__main__":
    unittest.main()
