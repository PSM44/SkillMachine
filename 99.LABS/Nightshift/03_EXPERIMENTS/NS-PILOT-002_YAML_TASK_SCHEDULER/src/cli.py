"""Command-line entry point for the YAML task scheduler."""
from __future__ import annotations

import argparse
import sys

import yaml

from src.parser import load_tasks
from src.scheduler import apply as apply_filters
from src.report import build as build_report


def _make_arg_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Read a YAML task file and print a filtered, sorted task report.",
    )
    p.add_argument(
        "--input",
        required=True,
        metavar="PATH",
        help="Path to the YAML input file (required).",
    )
    p.add_argument(
        "--filter-status",
        metavar="STR",
        choices=("open", "done", "blocked"),
        default=None,
        help="Only include tasks with this status: open | done | blocked.",
    )
    p.add_argument(
        "--sort-by",
        metavar="FIELD",
        choices=("priority", "due_date"),
        default="priority",
        help="Sort tasks by: priority (default) | due_date.",
    )
    p.add_argument(
        "--output",
        metavar="PATH",
        default=None,
        help="Write the report to this file instead of stdout.",
    )
    return p


def run(argv: list[str] | None = None) -> int:
    """Parse *argv*, run the pipeline, and return an exit code."""
    args = _make_arg_parser().parse_args(argv)

    try:
        tasks = load_tasks(args.input)
    except FileNotFoundError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    except yaml.YAMLError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2

    filtered = apply_filters(
        tasks,
        filter_status=args.filter_status,
        sort_by=args.sort_by,
    )
    report = build_report(filtered)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as fh:
            fh.write(report)
            fh.write("\n")
    else:
        print(report)

    return 0


if __name__ == "__main__":
    sys.exit(run())
