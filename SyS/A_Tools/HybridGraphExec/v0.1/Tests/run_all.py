#!/usr/bin/env python3
"""Run HybridGraphExec v0.1 tests."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent


def main() -> int:
    os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
    loader = unittest.TestLoader()
    suite = loader.discover(str(HERE), pattern="test_*.py")
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    print("TESTS_TOTAL={0}".format(result.testsRun))
    print("TESTS_FAILED={0}".format(len(result.failures) + len(result.errors)))
    print("TESTS_OK={0}".format(result.wasSuccessful()))
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(main())
