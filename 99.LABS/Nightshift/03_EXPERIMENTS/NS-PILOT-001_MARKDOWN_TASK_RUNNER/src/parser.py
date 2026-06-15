"""Markdown checklist parser for NS-PILOT-001."""

import re

DONE_RE = re.compile(r"^- \[[xX]\] ")
BLOCKED_RE = re.compile(r"^- \[!\] |BLOCKED")
PENDING_RE = re.compile(r"^- \[ \] ")


def classify_line(line: str) -> str | None:
    """Return 'done', 'blocked', or 'pending' for a checklist line, else None."""
    if DONE_RE.match(line):
        return "done"
    if BLOCKED_RE.search(line):
        return "blocked"
    if PENDING_RE.match(line):
        return "pending"
    return None


def parse(text: str) -> dict:
    """Parse markdown text and return counts and items by state."""
    items: dict[str, list[str]] = {"pending": [], "done": [], "blocked": []}
    for line in text.splitlines():
        state = classify_line(line.strip())
        if state:
            items[state].append(line.strip())
    return items


def parse_file(path: str) -> dict:
    with open(path, encoding="utf-8") as fh:
        return parse(fh.read())
