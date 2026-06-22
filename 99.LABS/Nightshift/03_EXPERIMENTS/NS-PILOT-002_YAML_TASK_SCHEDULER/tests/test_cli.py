"""Tests for src.cli (via subprocess for exit-code accuracy)."""
import pathlib
import subprocess
import sys

import pytest

_ROOT = pathlib.Path(__file__).parent.parent
_SAMPLE = str(_ROOT / "TASKS.sample.yaml")


def _cli(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "-m", "src.cli", *args],
        cwd=str(_ROOT),
        capture_output=True,
        text=True,
    )


class TestHappyPath:
    def test_basic_run_exit_zero(self):
        assert _cli("--input", _SAMPLE).returncode == 0

    def test_output_has_task_report_header(self):
        assert "TASK REPORT" in _cli("--input", _SAMPLE).stdout

    def test_output_has_summary_line(self):
        out = _cli("--input", _SAMPLE).stdout
        assert "Total:" in out and "Open:" in out

    def test_filter_status_exit_zero(self):
        assert _cli("--input", _SAMPLE, "--filter-status", "open").returncode == 0

    def test_sort_by_due_date_exit_zero(self):
        assert _cli("--input", _SAMPLE, "--sort-by", "due_date").returncode == 0

    def test_filter_and_sort_exit_zero(self):
        r = _cli("--input", _SAMPLE, "--filter-status", "done", "--sort-by", "due_date")
        assert r.returncode == 0

    def test_help_exit_zero(self):
        r = _cli("--help")
        assert r.returncode == 0
        assert "--input" in r.stdout

    def test_output_to_file(self, tmp_path):
        dest = str(tmp_path / "out.txt")
        assert _cli("--input", _SAMPLE, "--output", dest).returncode == 0
        content = pathlib.Path(dest).read_text(encoding="utf-8")
        assert "TASK REPORT" in content


class TestErrorCodes:
    def test_missing_file_exits_1(self):
        assert _cli("--input", "no_such_file.yaml").returncode == 1

    def test_invalid_yaml_exits_2(self, tmp_path):
        bad = tmp_path / "bad.yaml"
        bad.write_text("tasks: [unclosed", encoding="utf-8")
        assert _cli("--input", str(bad)).returncode == 2
