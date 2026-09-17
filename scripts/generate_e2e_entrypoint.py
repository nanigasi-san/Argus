#!/usr/bin/env python3
"""Discover every E2E file and register it in a single Flutter application."""
import os
from pathlib import Path
import sys


def discover(root):
    return sorted(
        path.relative_to(root).as_posix()
        for directory in ("integration_test", "e2e")
        if (root / directory).is_dir()
        for path in (root / directory).rglob("*_test.dart")
        if path.is_file()
    )


def render(files, target, root):
    lines = ["// Generated; do not edit.",
             "import 'package:flutter_test/flutter_test.dart';",
             "import 'package:integration_test/integration_test.dart';"]
    for index, name in enumerate(files):
        relative = Path(os.path.relpath(root / name, target.parent)).as_posix()
        # Dart imports and test names are single-quoted string literals.
        escaped = relative.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$")
        lines.append(f"import '{escaped}' as suite_{index};")
    lines.append("void main() {")
    # Register the integration driver's completion hook at the root, not in
    # the first suite group (which would report success before later suites).
    lines.append("  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();")
    lines.append("  final counts = <String, int>{};")
    for index, name in enumerate(files):
        escaped = name.replace("'", "\\'").replace("$", "\\$")
        lines.extend([f"  group('{escaped}', () {{", "    var completed = 0;",
                      "    tearDown(() { completed += 1; });",
                      f"    tearDownAll(() {{ counts['{escaped}'] = completed; }});",
                      f"    suite_{index}.main();", "  });"])
    lines.extend(["  tearDownAll(() {", "    binding.reportData ??= <String, dynamic>{};",
                  "    binding.reportData!['e2eSuiteCounts'] = counts;", "  });"])
    lines.append("}")
    return "\n".join(lines) + "\n"


def main():
    root = Path.cwd()
    files = discover(root)
    if not files:
        raise SystemExit("No E2E test files found in integration_test/ or e2e/.")
    report = Path(sys.argv[1])
    report.mkdir(parents=True, exist_ok=True)
    target = root / "integration_test/ci_all_suites.dart"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(render(files, target, root), encoding="utf-8")
    (report / "suites.txt").write_text("\n".join(files) + "\n", encoding="utf-8")
    print(f"Registered all {len(files)} E2E files in {target.relative_to(root)}")
    print("\n".join(files))


if __name__ == "__main__":
    main()
