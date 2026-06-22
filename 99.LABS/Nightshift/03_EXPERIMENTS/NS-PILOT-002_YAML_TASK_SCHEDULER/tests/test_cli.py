from __future__ import annotations

import subprocess
import sys
from pathlib import Path


PILOT_ROOT = Path(__file__).resolve().parents[1]
CLI_PATH = PILOT_ROOT / "src" / "cli.py"


def run_cli(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(CLI_PATH), *args],
        cwd=PILOT_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )


def test_cli_success_with_sample_file() -> None:
    result = run_cli("--input", "TASKS.sample.yaml")

    assert result.returncode == 0
    assert "TASK REPORT" in result.stdout
    assert "Total: 7 | Open: 4 | Done: 2 | Blocked: 1" in result.stdout


def test_cli_missing_input_returns_exit_code_1() -> None:
    result = run_cli("--input", "missing.yaml")

    assert result.returncode == 1
    assert "input file not found" in result.stderr


def test_cli_invalid_yaml_returns_exit_code_2(tmp_path: Path) -> None:
    bad_file = tmp_path / "invalid.yaml"
    bad_file.write_text("tasks: [\n", encoding="utf-8")

    result = run_cli("--input", str(bad_file))

    assert result.returncode == 2
    assert "Invalid YAML" in result.stderr


def test_cli_output_writes_file(tmp_path: Path) -> None:
    output_path = tmp_path / "report.txt"

    result = run_cli("--input", "TASKS.sample.yaml", "--output", str(output_path))

    assert result.returncode == 0
    assert output_path.read_text(encoding="utf-8").startswith("TASK REPORT\n")


def test_cli_help_lists_required_flags() -> None:
    result = run_cli("--help")

    assert result.returncode == 0
    assert "--input" in result.stdout
    assert "--filter-status" in result.stdout
    assert "--sort-by" in result.stdout
    assert "--output" in result.stdout


def test_cli_filter_status_open_filters_output() -> None:
    result = run_cli("--input", "TASKS.sample.yaml", "--filter-status", "open")

    assert result.returncode == 0
    assert "STATUS: blocked" not in result.stdout
    assert "STATUS: done" not in result.stdout
    assert "Total: 4 | Open: 4 | Done: 0 | Blocked: 0" in result.stdout
