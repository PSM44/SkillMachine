"""Tests for src.parser."""
import pathlib
import pytest
import yaml

from src.parser import load_tasks

_SAMPLE = str(pathlib.Path(__file__).parent.parent / "TASKS.sample.yaml")


class TestLoadValidYaml:
    def test_returns_list(self):
        tasks = load_tasks(_SAMPLE)
        assert isinstance(tasks, list)

    def test_every_task_has_required_fields(self):
        for task in load_tasks(_SAMPLE):
            for field in ("title", "priority", "due_date", "status"):
                assert field in task, f"Missing '{field}'"

    def test_sample_has_expected_count(self):
        assert len(load_tasks(_SAMPLE)) == 7


class TestLoadErrors:
    def test_missing_file_raises_file_not_found(self):
        with pytest.raises(FileNotFoundError):
            load_tasks("/no/such/path/xyz.yaml")

    def test_invalid_yaml_raises_yaml_error(self, tmp_path):
        bad = tmp_path / "bad.yaml"
        bad.write_text("tasks: [unclosed bracket", encoding="utf-8")
        with pytest.raises(yaml.YAMLError):
            load_tasks(str(bad))

    def test_missing_tasks_key_raises_yaml_error(self, tmp_path):
        f = tmp_path / "no_key.yaml"
        f.write_text("items: []\n", encoding="utf-8")
        with pytest.raises(yaml.YAMLError):
            load_tasks(str(f))

    def test_tasks_not_list_raises_yaml_error(self, tmp_path):
        f = tmp_path / "bad_type.yaml"
        f.write_text("tasks: not_a_list\n", encoding="utf-8")
        with pytest.raises(yaml.YAMLError):
            load_tasks(str(f))
