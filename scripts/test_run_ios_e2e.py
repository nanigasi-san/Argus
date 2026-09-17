"""Regression tests for persisted iOS VM URI discovery and driver failures."""
from datetime import datetime
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import run_ios_e2e as runner


STARTED = datetime.fromisoformat("2026-09-17T07:09:14+00:00")
URI = "http://127.0.0.1:51210/current-token=/"


def event(pid=19704, timestamp="2026-09-17 07:09:29.760000+0000", uri=URI):
    return {"processID": pid, "timestamp": timestamp,
            "eventMessage": "flutter: " + runner.VM_MESSAGE + uri}


class SavedUriTests(unittest.TestCase):
    def test_recovers_notification_emitted_before_live_reader_attached(self):
        output = "Filtering the log data using predicate\n" + json.dumps([event()])
        self.assertEqual(runner.vm_service_uri(output, 19704, STARTED), URI)

    def test_ignores_other_processes_and_older_launches(self):
        logs = [event(pid=11426), event(timestamp="2026-09-17 07:00:00+0000")]
        self.assertIsNone(runner.vm_service_uri(json.dumps(logs), 19704, STARTED))
        logs.append(event())
        self.assertEqual(runner.vm_service_uri(json.dumps(logs), 19704, STARTED), URI)

    def test_rejects_invalid_or_remote_service_uris(self):
        for uri in ("https://127.0.0.1:51210/", "http://192.0.2.1:51210/",
                    "http://127.0.0.1/no-port", "http://127.0.0.1:bad/"):
            with self.subTest(uri=uri), self.assertRaises(ValueError):
                runner.vm_service_uri(json.dumps([event(uri=uri)]), 19704, STARTED)

    def test_does_not_treat_malformed_output_as_an_empty_log(self):
        with self.assertRaises(ValueError):
            runner.vm_service_uri("Failed to read logs", 19704, STARTED)

    def test_polls_saved_logs_until_current_process_notification_is_persisted(self):
        responses = [subprocess.CompletedProcess([], 0, json.dumps([event(pid=9)])),
                     subprocess.CompletedProcess([], 0, json.dumps([event()]))]
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(runner.subprocess, "run", side_effect=responses) as run, \
                patch.object(runner.time, "sleep"):
            report = Path(directory)
            self.assertEqual(runner.wait_for_vm_service(
                "simulator", "Runner", 19704, STARTED, report), URI)
            self.assertEqual(run.call_count, 2)
            command = run.call_args.args[0]
            self.assertIn("show", command)
            self.assertNotIn("stream", command)
            self.assertIn("2026-09-17 07:09:14", command)
            self.assertIn(URI, (report / "vm-service-log.json").read_text())

    def test_query_timeout_can_recover_from_saved_notification(self):
        responses = [subprocess.TimeoutExpired(["log", "show"], 15),
                     subprocess.CompletedProcess([], 0, json.dumps([event()]))]
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(runner.subprocess, "run", side_effect=responses), \
                patch.object(runner.time, "sleep"):
            self.assertEqual(runner.wait_for_vm_service(
                "simulator", "Runner", 19704, STARTED, Path(directory)), URI)

    def test_missing_notification_has_a_deadline(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(runner.time, "monotonic", side_effect=[0, 0, 0, 1, 2]), \
                patch.object(runner.time, "sleep"), \
                patch.object(runner.subprocess, "run", return_value=
                             subprocess.CompletedProcess([], 0, "[]")):
            with self.assertRaisesRegex(TimeoutError, "PID 19704"):
                runner.wait_for_vm_service("simulator", "Runner", 19704,
                                           STARTED, Path(directory), timeout=2)


class RunnerTests(unittest.TestCase):
    def run_e2e(self, directory, driver_status=0, launch_output="com.argus.test: 19704\n",
                discovery_error=None, commands=None):
        report = Path(directory)
        app = report / "Runner.app"
        app.mkdir()
        with (app / "Info.plist").open("wb") as file:
            plistlib.dump({"CFBundleIdentifier": "com.argus.test",
                          "CFBundleExecutable": "Runner"}, file)
        if commands is None:
            commands = []

        def execute(command, **kwargs):
            commands.append(command)
            if command[:2] == ["flutter", "drive"]:
                return subprocess.CompletedProcess(command, driver_status)
            return subprocess.CompletedProcess(command, 0, launch_output)

        with patch.object(runner, "APP", app), \
                patch.object(runner.subprocess, "run", side_effect=execute), \
                patch.object(runner, "wait_for_vm_service", return_value=URI,
                             side_effect=discovery_error) as wait:
            result = runner.run_e2e("simulator", report)
            self.assertEqual(wait.call_args.args[2], 19704)
            self.assertEqual(json.loads((report / "launch.json").read_text())["pid"], 19704)
        return result, commands

    def test_builds_all_suites_once_and_attaches_to_existing_app(self):
        with tempfile.TemporaryDirectory() as directory:
            result, commands = self.run_e2e(directory)
            self.assertEqual(result, 0)
            self.assertEqual(sum(command[:2] == ["flutter", "build"]
                                 for command in commands), 1)
            self.assertIn("--target=integration_test/ci_all_suites.dart", commands[0])
            self.assertIn("--start-paused", commands[2])
            self.assertIn("--terminate-running-process", commands[2])
            self.assertIn(f"--use-existing-app={URI}", commands[-1])
            self.assertIn("--driver=test_driver/ui_smoke_driver.dart", commands[-1])

    def test_preserves_driver_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(self.run_e2e(directory, driver_status=7)[0], 7)

    def test_never_runs_driver_when_discovery_fails(self):
        commands = []
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(TimeoutError):
                self.run_e2e(directory, discovery_error=TimeoutError("missing URI"),
                             commands=commands)
        self.assertFalse(any(command[:2] == ["flutter", "drive"] for command in commands))

    def test_never_runs_driver_when_launch_pid_is_unknown(self):
        commands = []
        with tempfile.TemporaryDirectory() as directory, \
                self.assertRaisesRegex(ValueError, "launched app PID"):
            self.run_e2e(directory, launch_output="Launch succeeded without a PID",
                         commands=commands)
        self.assertFalse(any(command[:2] == ["flutter", "drive"] for command in commands))

    def test_build_failure_stops_before_install_or_driver(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(runner.subprocess, "run", side_effect=
                             subprocess.CalledProcessError(3, ["flutter", "build"])) as run:
            with self.assertRaises(subprocess.CalledProcessError):
                runner.run_e2e("simulator", Path(directory))
            self.assertEqual(run.call_count, 1)


if __name__ == "__main__":
    unittest.main()
