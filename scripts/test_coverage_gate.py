#!/usr/bin/env python3
import tempfile
import unittest
from pathlib import Path
from coverage_gate import analyze


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


if __name__ == "__main__":
    unittest.main()
