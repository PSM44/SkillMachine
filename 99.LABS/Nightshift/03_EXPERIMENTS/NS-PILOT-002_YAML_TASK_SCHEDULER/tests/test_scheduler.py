"""Tests for src.scheduler."""
import pytest
from src.scheduler import apply

_TASKS = [
    {"title": "T1", "priority": "low",    "due_date": "2026-08-01", "status": "open"},
    {"title": "T2", "priority": "high",   "due_date": "2026-07-01", "status": "blocked"},
    {"title": "T3", "priority": "medium", "due_date": "2026-07-15", "status": "done"},
    {"title": "T4", "priority": "high",   "due_date": "2026-07-05", "status": "open"},
    {"title": "T5", "priority": "medium", "due_date": "2026-07-20", "status": "open"},
]


class TestFilterStatus:
    def test_filter_open_keeps_only_open(self):
        result = apply(_TASKS, filter_status="open")
        assert all(t["status"] == "open" for t in result)

    def test_filter_done_keeps_only_done(self):
        result = apply(_TASKS, filter_status="done")
        assert all(t["status"] == "done" for t in result)
        assert len(result) == 1

    def test_filter_none_keeps_all(self):
        result = apply(_TASKS, filter_status=None)
        assert len(result) == len(_TASKS)

    def test_unknown_status_returns_empty(self):
        assert apply(_TASKS, filter_status="pending") == []


class TestSortOrder:
    def test_sort_priority_high_first(self):
        result = apply(_TASKS, sort_by="priority")
        ranks = [{"high": 0, "medium": 1, "low": 2}[t["priority"]] for t in result]
        assert ranks == sorted(ranks)

    def test_sort_due_date_ascending(self):
        result = apply(_TASKS, sort_by="due_date")
        dates = [t["due_date"] for t in result]
        assert dates == sorted(dates)


class TestFilterAndSort:
    def test_open_tasks_sorted_by_due_date(self):
        result = apply(_TASKS, filter_status="open", sort_by="due_date")
        assert all(t["status"] == "open" for t in result)
        dates = [t["due_date"] for t in result]
        assert dates == sorted(dates)
