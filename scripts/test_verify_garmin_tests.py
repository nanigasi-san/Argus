"""Regression coverage for the watch CI's fail-closed result gate."""
from pathlib import Path
import tempfile
import unittest

from verify_garmin_tests import discover_tests, verify


class GarminResultsTests(unittest.TestCase):
    def test_success_allows_sdk_exit_one_only_with_complete_summary(self):
        for code in (0, 1):
            self.assertEqual(verify("PASSED (passed=26, failed=0, errors=0)\n", code, 26),
                             {"passed": 26, "failed": 0, "errors": 0})

    def test_failed_incomplete_empty_and_ambiguous_results_are_rejected(self):
        for log in ("", "Unable to connect to simulator", "PASS",
                    "PASSED (passed=0, failed=0, errors=0)",
                    "PASSED (passed=25, failed=0, errors=0)",
                    "FAILED (passed=25, failed=1, errors=0)",
                    "FAILED (passed=25, failed=0, errors=1)",
                    "PASSED (passed=26, failed=0, errors=0)\n" * 2):
            with self.subTest(log=log), self.assertRaises(ValueError):
                verify(log, 1, 26)

    def test_timeout_or_process_failure_overrides_even_a_success_summary(self):
        for code in (2, 124, 137, -15):
            with self.subTest(code=code), self.assertRaises(ValueError):
                verify("PASSED (passed=26, failed=0, errors=0)", code, 26)

    def test_recursive_discovery_ignores_comments_and_strings(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            (project / "tests/nested").mkdir(parents=True)
            (project / "tests/nested/tests.mc").write_text(
                '// (:test) function comment() {}\n'
                '/* (:test) function block() {} */\n'
                'var s = "(:test) function string() {}";\n'
                '(:test)\nfunction actual(logger) { return true; }', encoding="utf-8")
            self.assertEqual(len(discover_tests(project)), 1)
            self.assertTrue(discover_tests(project)[0].endswith(":actual"))

    def test_empty_suite_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                discover_tests(Path(directory))


if __name__ == "__main__":
    unittest.main()
