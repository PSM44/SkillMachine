from __future__ import annotations

from pathlib import Path

import pytest

from src import parser


def test_load_tasks_returns_expected_list(tmp_path: Path) -> None:
    input_file = tmp_path / "tasks.yaml"
    input_file.write_text(
        "tasks:\n"
        '  - title: "Alpha"\n'
        '    priority: "high"\n'
        '    due_date: "2026-07-01"\n'
        '    status: "open"\n',
        encoding="utf-8",
    )

    tasks = parser.load_tasks(str(input_file))

    assert tasks == [
        {
            "title": "Alpha",
            "priority": "high",
            "due_date": "2026-07-01",
            "status": "open",
        }
    ]


def test_load_tasks_missing_file_raises_file_not_found() -> None:
    with pytest.raises(FileNotFoundError):
        parser.load_tasks("missing.yaml")


def test_load_tasks_invalid_yaml_raises_invalid_task_data(tmp_path: Path) -> None:
    input_file = tmp_path / "invalid.yaml"
    input_file.write_text("tasks: [\n", encoding="utf-8")

    with pytest.raises(parser.InvalidTaskDataError, match="Invalid YAML"):
        parser.load_tasks(str(input_file))


def test_load_tasks_invalid_schema_raises_invalid_task_data(tmp_path: Path) -> None:
    input_file = tmp_path / "schema.yaml"
    input_file.write_text("items: []\n", encoding="utf-8")

    with pytest.raises(parser.InvalidTaskDataError, match="exactly one key"):
        parser.load_tasks(str(input_file))


def test_load_tasks_invalid_enum_raises_invalid_task_data(tmp_path: Path) -> None:
    input_file = tmp_path / "enum.yaml"
    input_file.write_text(
        "tasks:\n"
        '  - title: "Alpha"\n'
        '    priority: "urgent"\n'
        '    due_date: "2026-07-01"\n'
        '    status: "open"\n',
        encoding="utf-8",
    )

    with pytest.raises(parser.InvalidTaskDataError, match="priority must be one of"):
        parser.load_tasks(str(input_file))


def test_load_tasks_invalid_date_raises_invalid_task_data(tmp_path: Path) -> None:
    input_file = tmp_path / "date.yaml"
    input_file.write_text(
        "tasks:\n"
        '  - title: "Alpha"\n'
        '    priority: "high"\n'
        '    due_date: "2026/07/01"\n'
        '    status: "open"\n',
        encoding="utf-8",
    )

    with pytest.raises(parser.InvalidTaskDataError, match="YYYY-MM-DD"):
        parser.load_tasks(str(input_file))
