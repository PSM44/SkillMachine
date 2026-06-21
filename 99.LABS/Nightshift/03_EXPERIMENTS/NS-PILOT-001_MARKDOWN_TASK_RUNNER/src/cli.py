"""Unified CLI entrypoint for the Nightshift markdown task runner.

This module intentionally delegates to src.task_runner so both entrypoints
share the same argparse contract, --help behavior, validation, and output format.
"""

from __future__ import annotations

from .task_runner import main


if __name__ == "__main__":
    raise SystemExit(main())
