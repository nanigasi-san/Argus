import tempfile
from pathlib import Path
import unittest

from generate_e2e_entrypoint import discover, render


class EntrypointTests(unittest.TestCase):
    def test_recursive_discovery_and_registration(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ("integration_test/a_test.dart", "integration_test/nested/b_test.dart",
                         "e2e/nested/c_test.dart", "integration_test/support/helper.dart"):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
            files = discover(root)
            self.assertEqual(files, ["e2e/nested/c_test.dart", "integration_test/a_test.dart",
                                     "integration_test/nested/b_test.dart"])
            text = render(files, root / ".dart_tool/e2e/all_suites.dart", root)
            self.assertEqual(text.count(" as suite_"), 3)
            self.assertEqual(text.count(".main();"), 3)
            self.assertLess(text.index("ensureInitialized();"), text.index("group("))
            self.assertIn("e2eSuiteCounts", text)
            for name in files:
                self.assertIn(f"../../{name}", text)
                self.assertIn(f"group('{name}'", text)

    def test_empty(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(discover(Path(directory)), [])


if __name__ == "__main__":
    unittest.main()
