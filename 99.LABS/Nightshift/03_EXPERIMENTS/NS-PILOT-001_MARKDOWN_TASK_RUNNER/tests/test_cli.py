from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class CliContractTests(unittest.TestCase):
    def run_cli(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, "-m", "src.cli", *args],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_help_exits_zero_and_shows_usage(self) -> None:
        result = self.run_cli("--help")
        self.assertEqual(result.returncode, 0)
        self.assertIn("usage:", result.stdout.lower())
        self.assertIn("input_path", result.stdout)
        self.assertIn("output_path", result.stdout)

    def test_missing_args_exits_nonzero(self) -> None:
        result = self.run_cli()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("usage:", result.stderr.lower())

    def test_cli_writes_normalized_json_report(self) -> None:
        sample = ROOT / "TASKS.sample.md"
        with tempfile.TemporaryDirectory() as tmp_dir:
            output_path = Path(tmp_dir) / "cli-report.json"
            result = self.run_cli(str(sample), str(output_path))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(output_path.exists())
            data = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertIn("source", data)
            self.assertIn("summary", data)
            self.assertIn("tasks", data)


if __name__ == "__main__":
    unittest.main()


