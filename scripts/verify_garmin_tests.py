#!/usr/bin/env python3
"""Require all discovered Monkey C tests to pass, even if monkeydo exits 1."""
import json
from pathlib import Path
import re


def discover_tests(project):
    tests = []
    for folder in ("source", "tests"):
        for path in sorted((project / folder).rglob("*.mc")):
            source = path.read_text(encoding="utf-8")
            source = re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/',
                            lambda match: '""' if match[0].startswith('"') else '',
                            source, flags=re.DOTALL)
            names = re.findall(r"\(:test\)\s*function\s+(\w+)\s*\(", source)
            if len(names) != source.count("(:test)"):
                raise ValueError(f"Unsupported test declaration in {path}")
            tests.extend(f"{path.as_posix()}:{name}" for name in names)
    if not tests:
        raise ValueError("No Monkey C tests discovered")
    return tests


def verify(log, exit_code, expected):
    if exit_code not in (0, 1):
        raise ValueError(f"monkeydo failed or timed out: exit {exit_code}")
    summaries = re.findall(
        r"^(PASSED|FAILED) \(passed=(\d+), failed=(\d+), errors=(\d+)\)\s*$",
        log, flags=re.MULTILINE)
    if len(summaries) != 1:
        raise ValueError("Missing or ambiguous Monkey C result summary")
    status, passed, failed, errors = summaries[0]
    if (status != "PASSED" or int(passed) != expected or expected == 0
            or int(failed) or int(errors)):
        raise ValueError(f"Incomplete or failed suite: {summaries[0]}, expected {expected}")
    return {"passed": int(passed), "failed": int(failed), "errors": int(errors)}


def main():
    output = Path("build/garmin-tests")
    tests = discover_tests(Path("garmin/argus-data-field"))
    (output / "tests-discovered.txt").write_text("\n".join(tests) + "\n", encoding="utf-8")
    result = verify((output / "tests.log").read_text(encoding="utf-8"),
                    int((output / "exit-code.txt").read_text()), len(tests))
    result["tests"] = tests
    (output / "test-results.json").write_text(json.dumps(result, indent=2) + "\n",
                                              encoding="utf-8")
    print(f"All {result['passed']} Monkey C tests passed")


if __name__ == "__main__":
    main()
