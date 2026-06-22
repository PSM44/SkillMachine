from __future__ import annotations

SEPARATOR = "=========="


def build_report(tasks: list[dict[str, str]]) -> str:
    lines = ["TASK REPORT", SEPARATOR]

    for task in tasks:
        lines.extend(
            [
                f"TITLE: {task['title']}",
                f"PRIORITY: {task['priority']}",
                f"DUE: {task['due_date']}",
                f"STATUS: {task['status']}",
                "",
            ]
        )

    lines.append(SEPARATOR)
    lines.append(_build_summary(tasks))
    return "\n".join(lines)


def _build_summary(tasks: list[dict[str, str]]) -> str:
    open_count = sum(1 for task in tasks if task["status"] == "open")
    done_count = sum(1 for task in tasks if task["status"] == "done")
    blocked_count = sum(1 for task in tasks if task["status"] == "blocked")
    return (
        f"Total: {len(tasks)} | Open: {open_count} | Done: {done_count} | "
        f"Blocked: {blocked_count}"
    )
