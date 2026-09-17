"""Regression tests for concurrent preparation and complete native test results."""
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import threading
import unittest
from unittest.mock import patch

import ios_simulator
import run_ios_build as native
import run_ios_e2e as e2e


class SimulatorTests(unittest.TestCase):
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
        self.assertEqual(commands[-2], (["xcrun", "simctl", "bootstatus", "device", "-b"],
                                       {"check": True, "timeout": 420}))

    def test_already_booted_device_still_requires_readiness(self):
        commands = self.run_boot(state="Booted")
        self.assertFalse(any(command[:3] == ["xcrun", "simctl", "boot"]
                             for command, _ in commands))
        self.assertIn("bootstatus", commands[-2][0])

    def test_boot_errors_are_not_ignored(self):
        with self.assertRaises(subprocess.CalledProcessError):
            self.run_boot(boot_failure=True)


class ConcurrentPreparationTests(unittest.TestCase):
    def test_e2e_build_overlaps_boot_but_install_waits_until_ready(self):
        boot_started = threading.Event()
        build_finished = threading.Event()
        boot_finished = threading.Event()
        commands = []

        def boot(*args):
            boot_started.set()
            self.assertTrue(build_finished.wait(2), "Build did not overlap Simulator boot")
            boot_finished.set()

        def execute(command, **kwargs):
            commands.append(command)
            if command[:2] == ["flutter", "build"]:
                self.assertTrue(boot_started.wait(2))
                self.assertFalse(boot_finished.is_set())
                build_finished.set()
            if command[:3] == ["xcrun", "simctl", "install"]:
                self.assertTrue(boot_finished.is_set())
            return subprocess.CompletedProcess(command, 0, "com.argus: 123\n")

        def build(command, on_xcode_build=None):
            on_xcode_build()
            execute(command)

        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory)
            app = report / "Runner.app"
            app.mkdir()
            with (app / "Info.plist").open("wb") as file:
                plistlib.dump({"CFBundleIdentifier": "com.argus", "CFBundleExecutable": "Runner"}, file)
            with patch.object(e2e, "APP", app), \
                    patch.object(e2e.ios_simulator, "boot", side_effect=boot), \
                    patch.object(e2e, "build_app", side_effect=build), \
                    patch.object(e2e.subprocess, "run", side_effect=execute), \
                    patch.object(e2e, "wait_for_vm_service", return_value="http://127.0.0.1:123/a/"):
                self.assertEqual(e2e.run_e2e("device", report, boot_simulator=True), 0)
        self.assertEqual(sum(command[:2] == ["flutter", "build"] for command in commands), 1)

    def test_e2e_does_not_install_or_run_tests_after_boot_failure(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(e2e.ios_simulator, "boot", side_effect=TimeoutError("boot failed")), \
                patch.object(e2e, "build_app", side_effect=lambda command, callback: callback()), \
                patch.object(e2e.subprocess, "run") as run:
            with self.assertRaises(TimeoutError):
                e2e.run_e2e("device", Path(directory), boot_simulator=True)
        run.assert_not_called()


class NativeTests(unittest.TestCase):
    def run_native(self, summary=None, failing_action=None, boot_error=None):
        if summary is None:
            summary = {"totalTestCount": 4, "passedTests": 4, "failedTests": 0, "skippedTests": 0}
        commands = []
        boot_started = threading.Event()
        build_finished = threading.Event()
        boot_finished = threading.Event()

        def boot(*args):
            boot_started.set()
            # Error paths need not complete a build, and must still return promptly.
            if boot_error:
                raise boot_error
            if failing_action is None:
                self.assertTrue(build_finished.wait(2))
            boot_finished.set()

        def execute(command, **kwargs):
            commands.append(command)
            if command[:2] == ["flutter", "build"]:
                self.assertFalse(boot_started.is_set(), "Flutter preparation must precede boot")
            if failing_action and failing_action in command:
                raise subprocess.CalledProcessError(7, command)
            if "build-for-testing" in command:
                self.assertTrue(boot_started.wait(2))
                build_finished.set()
            if "test-without-building" in command:
                self.assertTrue(boot_finished.is_set())
            return subprocess.CompletedProcess(command, 0, json.dumps(summary))

        def build(command, callback):
            callback()
            execute(command)

        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory)
            with patch.object(native, "REPORT", report), \
                    patch.object(native, "DERIVED_DATA", report / "DerivedData"), \
                    patch.object(native.ios_simulator, "select_device", return_value="device"), \
                    patch.object(native.ios_simulator, "boot", side_effect=boot), \
                    patch.object(native, "build_app", side_effect=build), \
                    patch.object(native.subprocess, "run", side_effect=execute):
                native.run_build()
            self.assertEqual(json.loads((report / "test-results.json").read_text()), summary)
        return commands

    def test_builds_normal_app_and_all_native_tests_once_and_executes_same_products(self):
        commands = self.run_native()
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

    def test_native_build_and_test_failures_propagate(self):
        for action in ("--config-only", "build-for-testing", "test-without-building"):
            with self.subTest(action=action), self.assertRaises(subprocess.CalledProcessError) as error:
                self.run_native(failing_action=action)
            self.assertEqual(error.exception.returncode, 7)

    def test_native_boot_failure_prevents_test_execution(self):
        with self.assertRaises(TimeoutError):
            self.run_native(boot_error=TimeoutError("boot failed"))

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


class BuildProgressTests(unittest.TestCase):
    def test_boot_waits_for_build_description_after_the_earlier_flutter_progress(self):
        import io
        output = "Running Xcode build...\nBuild description signature: abc\ndone\n"
        starts = []
        with patch.object(e2e.subprocess, "Popen") as popen:
            process = popen.return_value.__enter__.return_value
            process.stdout = io.StringIO(output)
            process.wait.return_value = 0
            e2e.build_app(["build"], lambda: starts.append(process.stdout.tell()))
        self.assertEqual(starts, [len("Running Xcode build...\nBuild description signature:")])

    def test_starts_boot_at_partial_progress_before_compilation_finishes(self):
        import sys
        with tempfile.TemporaryDirectory() as directory:
            signal_file = Path(directory, "boot-started")
            script = (
                "import sys, time; from pathlib import Path; "
                "print('Running Xcode build...'); sys.stdout.flush(); "
                "assert not Path(sys.argv[1]).exists(), 'Boot started before Xcode preparation'\n"
                "sys.stdout.write('Build description signature:'); sys.stdout.flush(); "
                "deadline=time.monotonic()+3\n"
                "while not Path(sys.argv[1]).exists() and time.monotonic()<deadline: time.sleep(.01)\n"
                "assert Path(sys.argv[1]).exists(), 'Boot callback waited for newline/build exit'\n"
                "print('done')\n"
            )
            calls = []

            def start_boot():
                calls.append(True)
                signal_file.touch()

            e2e.build_app([sys.executable, "-c", script, str(signal_file)], start_boot)
            self.assertEqual(calls, [True])

    def test_missing_progress_still_starts_boot_after_success(self):
        import sys
        calls = []
        e2e.build_app([sys.executable, "-c", "print('new log format')"], lambda: calls.append(True))
        self.assertEqual(calls, [True])

    def test_build_failure_preserves_exit_status_and_never_starts_fallback_boot(self):
        import sys
        calls = []
        with self.assertRaises(subprocess.CalledProcessError) as error:
            e2e.build_app([sys.executable, "-c", "import sys; sys.exit(7)"], lambda: calls.append(True))
        self.assertEqual(error.exception.returncode, 7)
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
