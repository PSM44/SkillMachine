import argparse
import sys

import yaml

from src.parser import load_tasks
from src.scheduler import filter_tasks, sort_tasks
from src.report import format_report


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="yaml-task-scheduler",
        description="Read a YAML task file and output a formatted, filtered, sorted report.",
    )
    p.add_argument("--input", required=True, metavar="PATH", help="Path to YAML input file")
    p.add_argument(
        "--filter-status",
        metavar="STR",
        choices=["open", "done", "blocked"],
        help="Filter tasks by status (open|done|blocked)",
    )
    p.add_argument(
        "--sort-by",
        metavar="FIELD",
        choices=["priority", "due_date"],
        default="priority",
        help="Sort tasks by field (priority|due_date). Default: priority",
    )
    p.add_argument("--output", metavar="PATH", help="Write report to file (default: stdout)")
    return p


def main(argv=None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        tasks = load_tasks(args.input)
    except FileNotFoundError:
        print(f"Error: file not found: '{args.input}'", file=sys.stderr)
        return 1
    except yaml.YAMLError as e:
        print(f"Error: invalid YAML: {e}", file=sys.stderr)
        return 2

    filtered = filter_tasks(tasks, status=args.filter_status)
    sorted_tasks = sort_tasks(filtered, sort_by=args.sort_by)
    report = format_report(sorted_tasks)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(report + "\n")
    else:
        print(report)

    return 0


if __name__ == "__main__":
    sys.exit(main())
