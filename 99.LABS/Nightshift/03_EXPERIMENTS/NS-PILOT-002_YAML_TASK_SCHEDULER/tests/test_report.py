"""Tests for src.report."""
from src.report import build

_TASKS = [
    {"title": "Alpha", "priority": "high",   "due_date": "2026-07-01", "status": "open"},
    {"title": "Beta",  "priority": "medium", "due_date": "2026-07-10", "status": "done"},
    {"title": "Gamma", "priority": "low",    "due_date": "2026-07-20", "status": "blocked"},
]


def test_header_present():
    assert "TASK REPORT" in build(_TASKS)


def test_task_fields_present():
    report = build(_TASKS)
    assert "TITLE: Alpha" in report
    assert "PRIORITY: high" in report
    assert "DUE: 2026-07-01" in report
    assert "STATUS: open" in report


def test_summary_counts_correct():
    report = build(_TASKS)
    assert "Total: 3" in report
    assert "Open: 1" in report
    assert "Done: 1" in report
    assert "Blocked: 1" in report


def test_empty_task_list_summary_zeros():
    report = build([])
    assert "Total: 0" in report
    assert "Open: 0" in report
    assert "Done: 0" in report
    assert "Blocked: 0" in report


def test_report_is_deterministic():
    assert build(_TASKS) == build(_TASKS)
