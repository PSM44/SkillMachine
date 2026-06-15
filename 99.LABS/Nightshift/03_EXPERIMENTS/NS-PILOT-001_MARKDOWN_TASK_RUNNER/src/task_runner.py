import argparse
import json
import re
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable, List


PENDING_PATTERN = re.compile(r"^\s*-\s\[\s\]\s+(.*)$")
DONE_PATTERN = re.compile(r"^\s*-\s\[[xX]\]\s+(.*)$")
BLOCKED_PATTERN = re.compile(r"^\s*-\s\[!\]\s+(.*)$")
ANY_CHECKLIST_PATTERN = re.compile(r"^\s*-\s\[[ xX!]\]\s+(.*)$")


@dataclass(frozen=True)
class TaskItem:
    line_number: int
    state: str
    text: str
    raw_line: str


def classify_line(line: str) -> str | None:
    if BLOCKED_PATTERN.match(line) or "BLOCKED" in line:
        return "blocked"
    if DONE_PATTERN.match(line):
        return "done"
    if PENDING_PATTERN.match(line):
        return "pending"
    return None


def normalize_text(line: str, state: str) -> str:
    pattern = {
        "pending": PENDING_PATTERN,
        "done": DONE_PATTERN,
        "blocked": BLOCKED_PATTERN,
    }.get(state)

    if pattern is not None:
        match = pattern.match(line)
        if match:
            return match.group(1).strip()
    match = ANY_CHECKLIST_PATTERN.match(line)
    if match:
        return match.group(1).strip()
    return line.strip()


def parse_tasks(markdown_text: str) -> List[TaskItem]:
    items: List[TaskItem] = []
    for line_number, raw_line in enumerate(markdown_text.splitlines(), start=1):
        state = classify_line(raw_line)
        if state is None:
            continue
        items.append(
            TaskItem(
                line_number=line_number,
                state=state,
                text=normalize_text(raw_line, state),
                raw_line=raw_line,
            )
        )
    return items


def build_report(source_path: str, items: Iterable[TaskItem]) -> dict:
    item_list = list(items)
    summary = {"pending": 0, "done": 0, "blocked": 0, "total": len(item_list)}
    for item in item_list:
        summary[item.state] += 1

    return {
        "source": source_path,
        "summary": summary,
        "tasks": [asdict(item) for item in item_list],
    }


def render_report(report: dict) -> str:
    return json.dumps(report, indent=2, sort_keys=True) + "\n"


def write_report(input_path: Path, output_path: Path) -> dict:
    markdown_text = input_path.read_text(encoding="utf-8")
    report = build_report(str(input_path), parse_tasks(markdown_text))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(render_report(report), encoding="utf-8", newline="\n")
    return report


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate a deterministic task report from markdown.")
    parser.add_argument("input_path", type=Path, help="Markdown checklist input file")
    parser.add_argument("output_path", type=Path, help="Normalized report output file")
    return parser


def main() -> int:
    args = build_arg_parser().parse_args()
    write_report(args.input_path, args.output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
