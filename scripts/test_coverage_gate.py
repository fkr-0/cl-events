#!/usr/bin/env python3
import tempfile
import unittest
from pathlib import Path
from coverage_gate import analyze, main
from unittest.mock import patch
import json


class CoverageGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.src = self.root / "src/events"
        self.src.mkdir(parents=True)
        for name in ("packages.lisp", "api.lisp", "async.lisp", "loop.lisp"):
            (self.src / name).write_text(";;; fixture\n")
        self.lcov = self.root / "in.lcov"

    def fixture(self, names=("async.lisp", "loop.lisp")):
        self.lcov.write_text("".join(
            f"SF:{self.src / name}\nDA:1,1\nDA:2,0\nend_of_record\n"
            for name in names))

    def test_excludes_declaration_only(self):
        self.fixture()
        self.assertEqual(analyze(self.lcov, self.src)[:2], (2, 4))

    def test_missing_file_fails_closed(self):
        self.fixture(("async.lisp",))
        with self.assertRaisesRegex(ValueError, "missing"):
            analyze(self.lcov, self.src)

    def test_duplicate_file_fails_closed(self):
        self.fixture(("async.lisp", "async.lisp", "loop.lisp"))
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            analyze(self.lcov, self.src)

    def test_missing_da_count_fails_closed(self):
        self.fixture()
        self.lcov.write_text(self.lcov.read_text().replace('DA:2,0', 'DA:2,', 1))
        with self.assertRaises(ValueError):
            analyze(self.lcov, self.src)

    def test_negative_da_count_fails_closed(self):
        self.fixture()
        self.lcov.write_text(self.lcov.read_text().replace('DA:2,0', 'DA:2,-1', 1))
        with self.assertRaises(ValueError):
            analyze(self.lcov, self.src)

    def test_failure_removes_previous_passing_endpoint(self):
        self.fixture()
        output = self.root / 'coverage'
        output.mkdir()
        endpoint = output / 'endpoint.json'
        endpoint.write_text('{"message":"100%"}')
        with patch('sys.argv', ['coverage_gate.py', '--lcov', str(self.lcov),
                                '--source', str(self.src), '--out', str(output),
                                '--threshold', '90']):
            self.assertEqual(main(), 1)
        self.assertFalse(endpoint.exists())
        self.assertFalse(json.loads((output / 'summary.json').read_text())['passed'])


if __name__ == "__main__":
    unittest.main()
