PRIORITY_ORDER = {"high": 0, "medium": 1, "low": 2}


def filter_tasks(tasks: list[dict], status: str | None = None) -> list[dict]:
    if status is None:
        return list(tasks)
    return [t for t in tasks if t.get("status") == status]


def sort_tasks(tasks: list[dict], sort_by: str = "priority") -> list[dict]:
    if sort_by == "priority":
        return sorted(tasks, key=lambda t: PRIORITY_ORDER.get(t.get("priority", "low"), 3))
    if sort_by == "due_date":
        return sorted(tasks, key=lambda t: t.get("due_date", ""))
    return list(tasks)
