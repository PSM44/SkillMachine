import pytest

from src.scheduler import filter_tasks, sort_tasks

TASKS = [
    {"title": "A", "priority": "low",    "due_date": "2026-07-15", "status": "open"},
    {"title": "B", "priority": "high",   "due_date": "2026-06-28", "status": "blocked"},
    {"title": "C", "priority": "medium", "due_date": "2026-07-03", "status": "done"},
    {"title": "D", "priority": "high",   "due_date": "2026-07-01", "status": "open"},
    {"title": "E", "priority": "medium", "due_date": "2026-07-08", "status": "open"},
]


def test_filter_open_returns_only_open():
    result = filter_tasks(TASKS, status="open")
    assert all(t["status"] == "open" for t in result)
    assert len(result) == 3


def test_filter_done_returns_only_done():
    result = filter_tasks(TASKS, status="done")
    assert all(t["status"] == "done" for t in result)
    assert len(result) == 1


def test_filter_blocked_returns_only_blocked():
    result = filter_tasks(TASKS, status="blocked")
    assert all(t["status"] == "blocked" for t in result)
    assert len(result) == 1


def test_filter_none_returns_all():
    result = filter_tasks(TASKS, status=None)
    assert len(result) == len(TASKS)


def test_sort_by_priority_order():
    result = sort_tasks(TASKS, sort_by="priority")
    priorities = [t["priority"] for t in result]
    order = {"high": 0, "medium": 1, "low": 2}
    assert all(order[priorities[i]] <= order[priorities[i+1]] for i in range(len(priorities)-1))


def test_sort_by_due_date_ascending():
    result = sort_tasks(TASKS, sort_by="due_date")
    dates = [t["due_date"] for t in result]
    assert dates == sorted(dates)


def test_filter_and_sort_combined():
    filtered = filter_tasks(TASKS, status="open")
    sorted_result = sort_tasks(filtered, sort_by="due_date")
    assert all(t["status"] == "open" for t in sorted_result)
    dates = [t["due_date"] for t in sorted_result]
    assert dates == sorted(dates)


def test_filter_nonexistent_status_returns_empty():
    result = filter_tasks(TASKS, status="pending")
    assert result == []
