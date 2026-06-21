import pytest

from src.report import format_report

TASKS = [
    {"title": "Alpha task", "priority": "high", "due_date": "2026-07-01", "status": "open"},
    {"title": "Beta task",  "priority": "low",  "due_date": "2026-07-10", "status": "done"},
]


def test_report_contains_header():
    report = format_report(TASKS)
    assert "TASK REPORT" in report


def test_report_contains_title_field():
    report = format_report(TASKS)
    assert "TITLE: Alpha task" in report
    assert "TITLE: Beta task" in report


def test_report_contains_status_field():
    report = format_report(TASKS)
    assert "STATUS: open" in report
    assert "STATUS: done" in report


def test_report_contains_priority_and_due():
    report = format_report(TASKS)
    assert "PRIORITY: high" in report
    assert "DUE: 2026-07-01" in report


def test_report_summary_line_correct_counts():
    report = format_report(TASKS)
    assert "Total: 2" in report
    assert "Open: 1" in report
    assert "Done: 1" in report
    assert "Blocked: 0" in report


def test_report_empty_task_list():
    report = format_report([])
    assert "TASK REPORT" in report
    assert "Total: 0" in report
    assert "Open: 0" in report
    assert "Done: 0" in report
    assert "Blocked: 0" in report


def test_report_is_deterministic():
    r1 = format_report(TASKS)
    r2 = format_report(TASKS)
    assert r1 == r2
