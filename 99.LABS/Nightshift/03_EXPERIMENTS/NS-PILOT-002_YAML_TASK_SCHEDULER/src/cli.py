from __future__ import annotations

import argparse
import sys

if __package__ in {None, ""}:
    import pathlib

    current_dir = pathlib.Path(__file__).resolve().parent
    if str(current_dir) not in sys.path:
        sys.path.insert(0, str(current_dir))
    import parser as task_parser
    import report as task_report
    import scheduler as task_scheduler
else:
    from . import parser as task_parser
    from . import report as task_report
    from . import scheduler as task_scheduler


def build_argument_parser() -> argparse.ArgumentParser:
    argument_parser = argparse.ArgumentParser(
        description="Read a YAML task file and generate a formatted task report."
    )
    argument_parser.add_argument(
        "--input",
        required=True,
        help="Path to the YAML input file.",
    )
    argument_parser.add_argument(
        "--filter-status",
        choices=["open", "done", "blocked"],
        help="Filter tasks by status value.",
    )
    argument_parser.add_argument(
        "--sort-by",
        choices=["priority", "due_date"],
        default="priority",
        help="Sort output by field.",
    )
    argument_parser.add_argument(
        "--output",
        help="Write report to this file instead of stdout.",
    )
    return argument_parser


def main(argv: list[str] | None = None) -> int:
    args = build_argument_parser().parse_args(argv)

    try:
        tasks = task_parser.load_tasks(args.input)
    except FileNotFoundError:
        print(f"Error: input file not found: {args.input}", file=sys.stderr)
        return 1
    except task_parser.InvalidTaskDataError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 2

    prepared_tasks = task_scheduler.prepare_tasks(
        tasks,
        filter_status=args.filter_status,
        sort_by=args.sort_by,
    )
    report_text = task_report.build_report(prepared_tasks)

    if args.output:
        with open(args.output, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(report_text)
    else:
        print(report_text)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
