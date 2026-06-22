"""Filter and sort a task list according to user-supplied criteria."""
from __future__ import annotations

_PRIORITY_RANK: dict[str, int] = {"high": 0, "medium": 1, "low": 2}
_UNKNOWN_PRIORITY_RANK = 99


def _priority_key(task: dict) -> int:
    return _PRIORITY_RANK.get(task.get("priority", ""), _UNKNOWN_PRIORITY_RANK)


def _due_date_key(task: dict) -> str:
    return task.get("due_date", "")


def apply(
    tasks: list[dict],
    *,
    filter_status: str | None = None,
    sort_by: str = "priority",
) -> list[dict]:
    """Return a new list that is optionally filtered and sorted.

    Args:
        tasks: source task list (not mutated).
        filter_status: keep only tasks whose ``status`` equals this value.
            Pass ``None`` to keep all tasks.
        sort_by: ``"priority"`` (high → medium → low) or ``"due_date"``
            (ascending ISO-8601 string comparison).

    Returns:
        A new list of task dicts in the requested order.
    """
    result = [t for t in tasks if filter_status is None or t.get("status") == filter_status]

    key_fn = _priority_key if sort_by != "due_date" else _due_date_key
    return sorted(result, key=key_fn)
