"""Regression tests for the CI command watchdog (no Simulator required)."""
import pathlib
import signal
import subprocess
import sys
import unittest

WATCHDOG = str(pathlib.Path(__file__).with_name("run_with_timeout.py"))


class WatchdogTests(unittest.TestCase):
    def run_command(self, seconds, source):
        return subprocess.run(
            [sys.executable, WATCHDOG, str(seconds), sys.executable, "-c", source],
            capture_output=True, text=True, timeout=10,
        )

    def test_success(self):
        result = self.run_command(2, "print('child output')")
        self.assertEqual(result.returncode, 0)
        self.assertIn("child output", result.stdout)

    def test_failure_is_preserved(self):
        self.assertEqual(self.run_command(2, "raise SystemExit(7)").returncode, 7)

    def test_timeout_stops_descendants_holding_output_open(self):
        result = self.run_command(
            0.2,
            "import subprocess,time; subprocess.Popen(['sleep','60']); time.sleep(60)",
        )
        self.assertEqual(result.returncode, 124)
        self.assertIn("[timeout]", result.stdout)

    def test_invalid_timeout(self):
        for seconds in (0, -1, "nan", "inf"):
            with self.subTest(seconds=seconds):
                self.assertEqual(self.run_command(seconds, "pass").returncode, 2)

    def test_signal_stops_child(self):
        with subprocess.Popen(
            [sys.executable, WATCHDOG, "60", sys.executable, "-c",
             "import time; print('ready', flush=True); time.sleep(60)"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        ) as process:
            self.assertEqual(process.stdout.readline().strip(), "ready")
            process.send_signal(signal.SIGTERM)
            process.communicate(timeout=10)
            self.assertEqual(process.returncode, 128 + signal.SIGTERM)


if __name__ == "__main__":
    unittest.main()
