from __future__ import annotations

PRIORITY_ORDER = {"high": 0, "medium": 1, "low": 2}


def prepare_tasks(
    tasks: list[dict[str, str]],
    filter_status: str | None = None,
    sort_by: str = "priority",
) -> list[dict[str, str]]:
    filtered = list(tasks)
    if filter_status is not None:
        filtered = [task for task in filtered if task["status"] == filter_status]

    if sort_by == "due_date":
        return sorted(filtered, key=lambda task: (task["due_date"], task["title"]))

    return sorted(
        filtered,
        key=lambda task: (PRIORITY_ORDER[task["priority"]], task["due_date"], task["title"]),
    )
