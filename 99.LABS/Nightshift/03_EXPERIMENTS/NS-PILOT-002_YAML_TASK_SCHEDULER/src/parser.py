import yaml


REQUIRED_FIELDS = {"title", "priority", "due_date", "status"}
VALID_PRIORITIES = {"high", "medium", "low"}
VALID_STATUSES = {"open", "done", "blocked"}


class InvalidTaskStructureError(Exception):
    pass


def load_tasks(path: str) -> list[dict]:
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = yaml.safe_load(f)
    except FileNotFoundError:
        raise
    except yaml.YAMLError as e:
        raise yaml.YAMLError(f"Invalid YAML in '{path}': {e}") from e

    if not isinstance(data, dict) or "tasks" not in data:
        raise yaml.YAMLError(f"File '{path}' must contain a 'tasks' key at root level")

    tasks = data["tasks"]
    if not isinstance(tasks, list):
        raise yaml.YAMLError(f"'tasks' must be a list")

    for i, task in enumerate(tasks):
        if not isinstance(task, dict):
            raise yaml.YAMLError(f"Task at index {i} must be a mapping")
        missing = REQUIRED_FIELDS - task.keys()
        if missing:
            raise yaml.YAMLError(f"Task at index {i} missing fields: {missing}")

    return tasks
