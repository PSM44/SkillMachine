from __future__ import annotations

from src.scheduler import prepare_tasks


TASKS = [
    {"title": "Zeta", "priority": "low", "due_date": "2026-07-15", "status": "open"},
    {"title": "Alpha", "priority": "high", "due_date": "2026-07-05", "status": "done"},
    {"title": "Beta", "priority": "medium", "due_date": "2026-07-03", "status": "open"},
    {"title": "Gamma", "priority": "high", "due_date": "2026-06-28", "status": "blocked"},
]


def test_prepare_tasks_filters_open() -> None:
    filtered = prepare_tasks(TASKS, filter_status="open")

    assert [task["title"] for task in filtered] == ["Beta", "Zeta"]


def test_prepare_tasks_filters_done() -> None:
    filtered = prepare_tasks(TASKS, filter_status="done")

    assert [task["title"] for task in filtered] == ["Alpha"]


def test_prepare_tasks_filters_blocked() -> None:
    filtered = prepare_tasks(TASKS, filter_status="blocked")

    assert [task["title"] for task in filtered] == ["Gamma"]


def test_prepare_tasks_sorts_by_priority() -> None:
    sorted_tasks = prepare_tasks(TASKS, sort_by="priority")

    assert [task["title"] for task in sorted_tasks] == ["Gamma", "Alpha", "Beta", "Zeta"]


def test_prepare_tasks_sorts_by_due_date() -> None:
    sorted_tasks = prepare_tasks(TASKS, sort_by="due_date")

    assert [task["title"] for task in sorted_tasks] == ["Gamma", "Beta", "Alpha", "Zeta"]
