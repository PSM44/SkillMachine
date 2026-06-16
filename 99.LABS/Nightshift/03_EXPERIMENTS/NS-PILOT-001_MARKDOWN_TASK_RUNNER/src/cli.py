"""CLI entrypoint: python -m src.cli <markdown_file> [output_file]"""

import sys
from .parser import parse_file
from .report import generate


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python -m src.cli <markdown_file> [output_file]", file=sys.stderr)
        sys.exit(1)
    path = sys.argv[1]
    items = parse_file(path)
    report = generate(items, source=path)
    if len(sys.argv) >= 3:
        with open(sys.argv[2], "w", encoding="utf-8") as fh:
            fh.write(report)
        print(f"Report written to {sys.argv[2]}")
    else:
        print(report)


if __name__ == "__main__":
    main()
