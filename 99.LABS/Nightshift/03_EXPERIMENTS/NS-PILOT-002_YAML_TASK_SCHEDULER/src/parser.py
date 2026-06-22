"""Read and validate a YAML task file, returning a list of task dicts."""
from __future__ import annotations

import yaml


_REQUIRED_FIELDS = ("title", "priority", "due_date", "status")


def _validate_task(task: object, index: int) -> dict:
    if not isinstance(task, dict):
        raise yaml.YAMLError(f"Task[{index}] must be a mapping, got {type(task).__name__}")
    missing = [f for f in _REQUIRED_FIELDS if f not in task]
    if missing:
        raise yaml.YAMLError(f"Task[{index}] missing required fields: {missing}")
    return task


def load_tasks(path: str) -> list[dict]:
    """Load tasks from *path*.

    Raises:
        FileNotFoundError: when *path* does not exist.
        yaml.YAMLError: when the file content is not valid YAML or the schema
            does not match the expected structure.
    """
    try:
        with open(path, encoding="utf-8") as fh:
            data = yaml.safe_load(fh)
    except FileNotFoundError:
        raise
    except yaml.YAMLError as exc:
        raise yaml.YAMLError(f"Cannot parse '{path}': {exc}") from exc

    if not isinstance(data, dict):
        raise yaml.YAMLError(f"Expected a YAML mapping at root, got {type(data).__name__}")

    raw_tasks = data.get("tasks")
    if raw_tasks is None:
        raise yaml.YAMLError("Root key 'tasks' not found")
    if not isinstance(raw_tasks, list):
        raise yaml.YAMLError(f"'tasks' must be a list, got {type(raw_tasks).__name__}")

    return [_validate_task(t, i) for i, t in enumerate(raw_tasks)]
