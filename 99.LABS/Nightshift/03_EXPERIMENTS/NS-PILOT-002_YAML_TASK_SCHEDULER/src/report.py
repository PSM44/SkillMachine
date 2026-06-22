"""Format a task list as a plain-text report."""
from __future__ import annotations

_SEP = "=" * 40


def _count(tasks: list[dict], status: str) -> int:
    return sum(1 for t in tasks if t.get("status") == status)


def build(tasks: list[dict]) -> str:
    """Return a deterministic plain-text report string for *tasks*.

    Output structure::

        TASK REPORT
        ========================================
        TITLE: <title>
        PRIORITY: <priority>
        DUE: <due_date>
        STATUS: <status>

        ... (one blank line between tasks) ...

        ========================================
        Total: N | Open: N | Done: N | Blocked: N
    """
    lines: list[str] = ["TASK REPORT", _SEP]

    for task in tasks:
        lines += [
            f"TITLE: {task.get('title', '')}",
            f"PRIORITY: {task.get('priority', '')}",
            f"DUE: {task.get('due_date', '')}",
            f"STATUS: {task.get('status', '')}",
            "",
        ]

    lines.append(_SEP)
    lines.append(
        f"Total: {len(tasks)}"
        f" | Open: {_count(tasks, 'open')}"
        f" | Done: {_count(tasks, 'done')}"
        f" | Blocked: {_count(tasks, 'blocked')}"
    )

    return "\n".join(lines)
