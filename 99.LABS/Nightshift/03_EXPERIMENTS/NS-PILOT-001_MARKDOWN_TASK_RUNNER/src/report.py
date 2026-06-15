"""Deterministic report writer for NS-PILOT-001."""

from __future__ import annotations


def generate(items: dict, source: str = "") -> str:
    lines = ["# TASK REPORT", ""]
    if source:
        lines += [f"SOURCE: {source}", ""]
    for state in ("pending", "done", "blocked"):
        entries = sorted(items.get(state, []))
        lines.append(f"## {state.upper()} ({len(entries)})")
        for entry in entries:
            lines.append(f"  {entry}")
        lines.append("")
    return "\n".join(lines)
