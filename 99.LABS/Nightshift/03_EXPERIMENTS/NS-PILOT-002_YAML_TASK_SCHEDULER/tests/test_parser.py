import os
import textwrap
import pytest
import yaml

from src.parser import load_tasks


SAMPLE_YAML = os.path.join(os.path.dirname(__file__), "..", "TASKS.sample.yaml")


def test_load_valid_yaml_returns_list():
    tasks = load_tasks(SAMPLE_YAML)
    assert isinstance(tasks, list)
    assert len(tasks) > 0


def test_load_valid_yaml_task_has_required_fields():
    tasks = load_tasks(SAMPLE_YAML)
    for task in tasks:
        assert "title" in task
        assert "priority" in task
        assert "due_date" in task
        assert "status" in task


def test_load_missing_file_raises_file_not_found():
    with pytest.raises(FileNotFoundError):
        load_tasks("nonexistent_file_xyz.yaml")


def test_load_invalid_yaml_raises_yaml_error(tmp_path):
    bad = tmp_path / "bad.yaml"
    bad.write_text("tasks: [invalid: yaml: content", encoding="utf-8")
    with pytest.raises(yaml.YAMLError):
        load_tasks(str(bad))


def test_load_yaml_missing_tasks_key_raises_yaml_error(tmp_path):
    bad = tmp_path / "notasks.yaml"
    bad.write_text("items:\n  - title: foo\n", encoding="utf-8")
    with pytest.raises(yaml.YAMLError):
        load_tasks(str(bad))


def test_load_yaml_task_count_matches_sample():
    tasks = load_tasks(SAMPLE_YAML)
    assert len(tasks) == 7
