from __future__ import annotations

from src.report import build_report


def test_build_report_contains_exact_header_and_fields() -> None:
    report = build_report(
        [
            {
                "title": "Alpha",
                "priority": "high",
                "due_date": "2026-07-01",
                "status": "open",
            }
        ]
    )

    lines = report.splitlines()
    assert lines[0] == "TASK REPORT"
    assert "TITLE: Alpha" in report
    assert "PRIORITY: high" in report
    assert "DUE: 2026-07-01" in report
    assert "STATUS: open" in report


def test_build_report_summary_counts_are_correct() -> None:
    report = build_report(
        [
            {"title": "A", "priority": "high", "due_date": "2026-07-01", "status": "open"},
            {"title": "B", "priority": "medium", "due_date": "2026-07-02", "status": "done"},
            {"title": "C", "priority": "low", "due_date": "2026-07-03", "status": "blocked"},
        ]
    )

    assert report.endswith("Total: 3 | Open: 1 | Done: 1 | Blocked: 1")


def test_build_report_empty_tasks_is_valid() -> None:
    report = build_report([])

    assert report == "TASK REPORT\n==========\n==========\nTotal: 0 | Open: 0 | Done: 0 | Blocked: 0"


def test_build_report_is_deterministic() -> None:
    tasks = [
        {"title": "A", "priority": "high", "due_date": "2026-07-01", "status": "open"},
        {"title": "B", "priority": "medium", "due_date": "2026-07-02", "status": "done"},
    ]

    assert build_report(tasks) == build_report(tasks)
