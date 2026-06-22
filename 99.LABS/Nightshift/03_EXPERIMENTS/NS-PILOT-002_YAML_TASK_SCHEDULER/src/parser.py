from __future__ import annotations

from datetime import datetime
from typing import Any

import yaml

VALID_PRIORITIES = {"high", "medium", "low"}
VALID_STATUSES = {"open", "done", "blocked"}
REQUIRED_FIELDS = ("title", "priority", "due_date", "status")


class InvalidTaskDataError(ValueError):
    """Raised when the task YAML structure or values are invalid."""


def load_tasks(input_path: str) -> list[dict[str, str]]:
    with open(input_path, "r", encoding="utf-8") as handle:
        try:
            payload = yaml.safe_load(handle)
        except yaml.YAMLError as error:
            raise InvalidTaskDataError(f"Invalid YAML: {error}") from error

    return _validate_payload(payload)


def _validate_payload(payload: Any) -> list[dict[str, str]]:
    if not isinstance(payload, dict):
        raise InvalidTaskDataError("Input must be a YAML mapping with root key 'tasks'.")

    if set(payload.keys()) != {"tasks"}:
        raise InvalidTaskDataError("Root mapping must contain exactly one key: 'tasks'.")

    tasks = payload["tasks"]
    if not isinstance(tasks, list):
        raise InvalidTaskDataError("'tasks' must be a list.")

    return [_validate_task(task, index) for index, task in enumerate(tasks, start=1)]


def _validate_task(task: Any, index: int) -> dict[str, str]:
    if not isinstance(task, dict):
        raise InvalidTaskDataError(f"Task {index} must be a mapping.")

    if set(task.keys()) != set(REQUIRED_FIELDS):
        raise InvalidTaskDataError(
            f"Task {index} must contain exactly these fields: {', '.join(REQUIRED_FIELDS)}."
        )

    normalized: dict[str, str] = {}
    for field in REQUIRED_FIELDS:
        value = task[field]
        if not isinstance(value, str):
            raise InvalidTaskDataError(f"Task {index} field '{field}' must be a string.")
        normalized[field] = value

    if normalized["priority"] not in VALID_PRIORITIES:
        raise InvalidTaskDataError(
            f"Task {index} priority must be one of: high, medium, low."
        )

    if normalized["status"] not in VALID_STATUSES:
        raise InvalidTaskDataError(
            f"Task {index} status must be one of: open, done, blocked."
        )

    try:
        datetime.strptime(normalized["due_date"], "%Y-%m-%d")
    except ValueError as error:
        raise InvalidTaskDataError(
            f"Task {index} due_date must be ISO format YYYY-MM-DD."
        ) from error

    return normalized
