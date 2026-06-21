SEPARATOR = "-" * 40


def format_report(tasks: list[dict]) -> str:
    lines = ["TASK REPORT", SEPARATOR]

    for task in tasks:
        lines.append(f"TITLE: {task.get('title', '')}")
        lines.append(f"PRIORITY: {task.get('priority', '')}")
        lines.append(f"DUE: {task.get('due_date', '')}")
        lines.append(f"STATUS: {task.get('status', '')}")
        lines.append("")

    lines.append(SEPARATOR)

    total = len(tasks)
    open_count = sum(1 for t in tasks if t.get("status") == "open")
    done_count = sum(1 for t in tasks if t.get("status") == "done")
    blocked_count = sum(1 for t in tasks if t.get("status") == "blocked")
    lines.append(f"Total: {total} | Open: {open_count} | Done: {done_count} | Blocked: {blocked_count}")

    return "\n".join(lines)
