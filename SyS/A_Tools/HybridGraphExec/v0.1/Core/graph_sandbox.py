"""Sandbox allocation and isolation for Hybrid Graph Execution v0.1."""
from __future__ import annotations

import json
import os
import shutil
from pathlib import Path
from typing import Any

from importlib.machinery import SourceFileLoader

_VALIDATOR_PATH = Path(__file__).resolve().parent.parent / "Validators" / "GraphDeterministicValidator.v0.1.py"
_validator = SourceFileLoader("graph_deterministic_validator", str(_VALIDATOR_PATH)).load_module()

GRAPH_SANDBOX_ROOT = _validator.GRAPH_SANDBOX_ROOT
REPO_ROOT = _validator.REPO_ROOT
AI_EXCHANGE_TEMP = _validator.AI_EXCHANGE_TEMP


class SandboxIsolationError(RuntimeError):
    pass


def ensure_graph_root(root: Path | None = None) -> Path:
    target = Path(root or GRAPH_SANDBOX_ROOT).resolve()
    if _validator.is_path_under(target, REPO_ROOT):
        raise SandboxIsolationError("graph sandbox root cannot be inside the repo")
    if _validator.is_path_under(target, AI_EXCHANGE_TEMP):
        raise SandboxIsolationError("graph sandbox root cannot be the flat AI-exchange temp")
    target.mkdir(parents=True, exist_ok=True)
    return target


def run_dir(run_id: str, root: Path | None = None) -> Path:
    safe = "".join(ch if ch.isalnum() or ch in ("-", "_") else "_" for ch in run_id)
    return ensure_graph_root(root) / "runs" / safe


def branch_sandbox(run_id: str, branch_id: str, root: Path | None = None) -> Path:
    safe_branch = "".join(ch if ch.isalnum() or ch in ("-", "_") else "_" for ch in branch_id)
    path = run_dir(run_id, root) / "branches" / safe_branch / "sandbox"
    path.mkdir(parents=True, exist_ok=True)
    return path.resolve()


def integration_sandbox(run_id: str, root: Path | None = None) -> Path:
    path = run_dir(run_id, root) / "integration" / "sandbox"
    path.mkdir(parents=True, exist_ok=True)
    return path.resolve()


def canonical_candidate_dir(run_id: str, root: Path | None = None) -> Path:
    path = run_dir(run_id, root) / "canonical_candidate"
    path.mkdir(parents=True, exist_ok=True)
    return path.resolve()


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def assert_inside_sandbox(target: Path, sandbox: Path) -> Path:
    resolved = target.resolve()
    if not _validator.is_path_under(resolved, sandbox.resolve()):
        raise SandboxIsolationError("path escapes sandbox: {0}".format(resolved))
    if _validator.is_path_under(resolved, REPO_ROOT):
        raise SandboxIsolationError("path is inside canonical repo: {0}".format(resolved))
    if _validator.is_path_under(resolved, AI_EXCHANGE_TEMP):
        raise SandboxIsolationError("path is inside AI-exchange temp: {0}".format(resolved))
    return resolved


def apply_fixture_ops(sandbox: Path, ops: list[dict[str, Any]]) -> dict[str, Any]:
    """Deterministic fixture worker. Writes only inside sandbox. Never touches canon."""
    sandbox = sandbox.resolve()
    sandbox.mkdir(parents=True, exist_ok=True)
    observed_reads: list[str] = []
    observed_writes: list[str] = []
    observed_locks: list[str] = []
    observed_spans: list[dict[str, Any]] = []
    for op in ops or []:
        kind = str(op.get("op") or "").lower()
        if kind == "lock":
            observed_locks.append(str(op.get("name") or ""))
            continue
        if kind == "crash":
            raise RuntimeError("FIXTURE_CRASH")
        if kind == "escape":
            escape_target = Path(str(op.get("target") or ""))
            assert_inside_sandbox(escape_target, sandbox)
            continue
        rel = _validator.normalize_rel(str(op.get("path") or ""))
        if not rel:
            continue
        target = assert_inside_sandbox(sandbox / rel.replace("/", os.sep), sandbox)
        if kind == "read":
            if target.exists():
                target.read_text(encoding="utf-8")
            observed_reads.append(rel)
        elif kind == "write":
            target.parent.mkdir(parents=True, exist_ok=True)
            content = str(op.get("content") or "")
            target.write_text(content, encoding="utf-8")
            observed_writes.append(rel)
            if op.get("start") is not None and op.get("end") is not None:
                observed_spans.append(
                    {"path": rel, "start": int(op.get("start")), "end": int(op.get("end"))}
                )
        else:
            raise SandboxIsolationError("unsupported fixture op: " + kind)
    return {
        "observed_reads": observed_reads,
        "observed_writes": observed_writes,
        "observed_locks": observed_locks,
        "observed_line_spans": observed_spans,
    }
