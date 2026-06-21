import os
import subprocess
import sys
import pytest

PILOT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SAMPLE_YAML = os.path.join(PILOT_ROOT, "TASKS.sample.yaml")
REPO_ROOT = os.path.abspath(os.path.join(PILOT_ROOT, "..", "..", "..", ".."))


def run_cli(*args):
    cmd = [sys.executable, "-m", "src.cli"] + list(args)
    return subprocess.run(cmd, capture_output=True, text=True, cwd=PILOT_ROOT)


def test_cli_happy_path_exit_zero():
    result = run_cli("--input", SAMPLE_YAML)
    assert result.returncode == 0


def test_cli_output_contains_task_report():
    result = run_cli("--input", SAMPLE_YAML)
    assert "TASK REPORT" in result.stdout


def test_cli_output_contains_summary_line():
    result = run_cli("--input", SAMPLE_YAML)
    assert "Total:" in result.stdout
    assert "Open:" in result.stdout


def test_cli_missing_file_exits_1():
    result = run_cli("--input", "definitely_nonexistent_xyz.yaml")
    assert result.returncode == 1


def test_cli_invalid_yaml_exits_2(tmp_path):
    bad = tmp_path / "bad.yaml"
    bad.write_text("tasks: [invalid: yaml: content", encoding="utf-8")
    result = run_cli("--input", str(bad))
    assert result.returncode == 2


def test_cli_filter_status_reduces_output():
    result_all = run_cli("--input", SAMPLE_YAML)
    result_open = run_cli("--input", SAMPLE_YAML, "--filter-status", "open")
    assert result_open.returncode == 0
    assert result_open.stdout.count("STATUS:") < result_all.stdout.count("STATUS:")


def test_cli_sort_by_due_date_exits_zero():
    result = run_cli("--input", SAMPLE_YAML, "--sort-by", "due_date")
    assert result.returncode == 0


def test_cli_filter_and_sort_combined():
    result = run_cli("--input", SAMPLE_YAML, "--filter-status", "open", "--sort-by", "due_date")
    assert result.returncode == 0
    assert "STATUS: open" in result.stdout


def test_cli_help_exits_zero():
    result = run_cli("--help")
    assert result.returncode == 0
    assert "--input" in result.stdout


def test_cli_output_to_file(tmp_path):
    out_file = str(tmp_path / "report.txt")
    result = run_cli("--input", SAMPLE_YAML, "--output", out_file)
    assert result.returncode == 0
    with open(out_file, encoding="utf-8") as f:
        content = f.read()
    assert "TASK REPORT" in content
    assert "Total:" in content
