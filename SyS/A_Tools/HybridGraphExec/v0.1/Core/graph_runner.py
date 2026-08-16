"""Hybrid Deterministic Graph Execution v0.1 runner.

Lifecycle stops before unauthorised canonical application.
Canonical mutation of the SkillsMachine repo is forbidden.
"""
from __future__ import annotations

import copy
import hashlib
import json
from importlib.machinery import SourceFileLoader
from pathlib import Path
from typing import Any, Callable

_CORE = Path(__file__).resolve().parent
_VALIDATOR_PATH = _CORE.parent / "Validators" / "GraphDeterministicValidator.v0.1.py"
_validator = SourceFileLoader("graph_deterministic_validator", str(_VALIDATOR_PATH)).load_module()
_sandbox = SourceFileLoader("graph_sandbox", str(_CORE / "graph_sandbox.py")).load_module()

GRAPH_MAX_ITERATIONS = _validator.GRAPH_MAX_ITERATIONS


class CanonicalMutationForbidden(RuntimeError):
    pass


def _load_state(path: Path) -> dict[str, Any] | None:
    if path.is_file():
        return _sandbox.read_json(path)
    return None


def _digest_overlay(files: dict[str, str]) -> str:
    h = hashlib.sha256()
    for key in sorted(files):
        h.update(key.encode("utf-8"))
        h.update(b"\0")
        h.update(files[key].encode("utf-8"))
    return h.hexdigest()


def default_node(
    node_id: str,
    branch_id: str,
    *,
    sandbox_path: str,
    baseline: dict[str, Any],
    write_set: list[str],
    read_set: list[str] | None = None,
    protected_paths: list[str] | None = None,
    resource_locks: list[str] | None = None,
    parent_node_ids: list[str] | None = None,
    fixture_ops: list[dict[str, Any]] | None = None,
    actor_role: str = "PROPOSER",
    actor_id: str = "worker-a",
    iteration: int = 1,
    max_iterations: int = 10,
    status: str = "PENDING",
) -> dict[str, Any]:
    return {
        "schema_version": "0.1",
        "node_id": node_id,
        "branch_id": branch_id,
        "baseline": copy.deepcopy(baseline),
        "parent_node_ids": list(parent_node_ids or []),
        "read_set": list(read_set or []),
        "write_set": list(write_set),
        "protected_paths": list(protected_paths or []),
        "resource_locks": list(resource_locks or []),
        "sandbox_path": sandbox_path,
        "iteration": iteration,
        "max_iterations": max_iterations,
        "local_bounded_loop_max_iterations": 6,
        "status": status,
        "retry_class": "NONE",
        "proposal_status": None,
        "evidence_refs": [],
        "canonical_apply_eligible": False,
        "actor_role": actor_role,
        "actor_id": actor_id,
        "apply_requested": False,
        "observed_reads": [],
        "observed_writes": [],
        "observed_locks": [],
        "observed_line_spans": [],
        "fixture_ops": list(fixture_ops or []),
    }


def default_graph(
    run_id: str,
    nodes: list[dict[str, Any]],
    *,
    recorded_head: str,
    sandbox_root: str | None = None,
    baseline: dict[str, Any] | None = None,
    max_parallel_branches: int = 2,
    target_valid_proposals: int = 2,
    max_valid_proposals: int = 3,
    canonical_applier_id: str | None = "applier-1",
    human_authority: bool = False,
) -> dict[str, Any]:
    bl = baseline or {"class": "CANONICAL_HEAD", "head": recorded_head, "treat_as_canonical_head": False}
    return {
        "schema_version": "0.1",
        "run_id": run_id,
        "architecture": _validator.ARCHITECTURE,
        "graph_max_iterations": GRAPH_MAX_ITERATIONS,
        "max_parallel_branches": max_parallel_branches,
        "target_valid_proposals": target_valid_proposals,
        "max_valid_proposals": max_valid_proposals,
        "sandbox_root": str(sandbox_root or _validator.GRAPH_SANDBOX_ROOT),
        "recorded_head": recorded_head,
        "baseline": bl,
        "canonical_applier_id": canonical_applier_id,
        "human_authority": human_authority,
        "worker_is_proposer": True,
        "canonical_mutation_forbidden": True,
        "nodes": nodes,
    }


def _parents_ok(node: dict[str, Any], by_id: dict[str, dict[str, Any]]) -> bool:
    for pid in node.get("parent_node_ids") or []:
        parent = by_id.get(pid)
        if parent is None or parent.get("status") not in ("VALID", "INTEGRATED", "APPLY_CANDIDATE"):
            return False
    return True


def _ready_nodes(graph: dict[str, Any]) -> list[dict[str, Any]]:
    by_id = {n["node_id"]: n for n in graph["nodes"]}
    ready = []
    for node in graph["nodes"]:
        if node.get("status") in ("PENDING", "RETRY"):
            if _parents_ok(node, by_id):
                ready.append(node)
    return ready


def persist(graph: dict[str, Any], extra: dict[str, Any] | None = None) -> Path:
    root = Path(graph["sandbox_root"])
    state_path = _sandbox.run_dir(graph["run_id"], root) / "run_state.json"
    payload = {"graph": graph, "extra": extra or {}}
    _sandbox.write_json(state_path, payload)
    _sandbox.write_json(_sandbox.run_dir(graph["run_id"], root) / "graph.json", graph)
    return state_path


def recover(run_id: str, sandbox_root: str | None = None) -> dict[str, Any]:
    root = Path(sandbox_root or _validator.GRAPH_SANDBOX_ROOT)
    state_path = _sandbox.run_dir(run_id, root) / "run_state.json"
    payload = _load_state(state_path)
    if payload is None:
        raise FileNotFoundError("no recoverable run_state for " + run_id)
    graph = payload["graph"]
    for node in graph["nodes"]:
        if node.get("status") == "RUNNING":
            node["status"] = "CRASHED"
            node["retry_class"] = "TRANSIENT"
            node["proposal_status"] = "CRASH_CONTAINED"
    persist(graph, {"recovered": True})
    return graph


def execute_node(graph: dict[str, Any], node: dict[str, Any]) -> dict[str, Any]:
    root = Path(graph["sandbox_root"])
    sandbox = _sandbox.branch_sandbox(graph["run_id"], node["branch_id"], root)
    node["sandbox_path"] = str(sandbox)
    node["status"] = "RUNNING"
    persist(graph)
    try:
        observed = _sandbox.apply_fixture_ops(sandbox, list(node.get("fixture_ops") or []))
    except _sandbox.SandboxIsolationError as exc:
        node["status"] = "REJECTED"
        node["retry_class"] = "ISOLATION"
        node["proposal_status"] = "DENY_SANDBOX_ISOLATION"
        node["evidence_refs"] = [str(exc)]
        persist(graph)
        return node
    except RuntimeError as exc:
        node["status"] = "CRASHED"
        node["retry_class"] = "TRANSIENT"
        node["proposal_status"] = "CRASH_CONTAINED"
        node["evidence_refs"] = [str(exc)]
        persist(graph)
        return node
    node["observed_reads"] = observed["observed_reads"]
    node["observed_writes"] = observed["observed_writes"]
    node["observed_locks"] = observed["observed_locks"] or list(node.get("resource_locks") or [])
    node["observed_line_spans"] = observed["observed_line_spans"]
    result = _validator.validate_node(node, graph, list(graph["nodes"]))
    if result.accepted:
        node["status"] = "VALID"
        node["retry_class"] = "NONE"
        node["proposal_status"] = "VALID"
    else:
        node["status"] = "REJECTED"
        node["retry_class"] = result.retry_class
        node["proposal_status"] = result.code
        node["evidence_refs"] = list(result.reasons)
        if result.retry_class == "TRANSIENT":
            node["status"] = "RETRY"
        if result.retry_class in ("BOUNDARY", "AUTHORITY") and "cross" in " ".join(result.reasons).lower():
            node["status"] = "ESCALATED"
    evidence = _sandbox.run_dir(graph["run_id"], root) / "branches" / node["branch_id"] / "evidence.json"
    _sandbox.write_json(evidence, {"node": node, "validation": result.to_dict()})
    persist(graph)
    return node


def integrate_valid(graph: dict[str, Any]) -> Path | None:
    valid = [n for n in graph["nodes"] if n.get("status") == "VALID"]
    target = int(graph.get("target_valid_proposals") or 2)
    maximum = int(graph.get("max_valid_proposals") or 3)
    if len(valid) > maximum:
        for extra in valid[maximum:]:
            extra["status"] = "REJECTED"
            extra["retry_class"] = "PARALLEL"
            extra["proposal_status"] = "OVER_MAX_VALID_PROPOSALS"
        valid = valid[:maximum]
    if len(valid) < target:
        return None
    root = Path(graph["sandbox_root"])
    integ = _sandbox.integration_sandbox(graph["run_id"], root)
    for node in valid:
        src = Path(node["sandbox_path"])
        dest = integ / node["branch_id"]
        dest.mkdir(parents=True, exist_ok=True)
        if src.is_dir():
            for item in src.rglob("*"):
                if item.is_file():
                    rel = item.relative_to(src)
                    target_file = dest / rel
                    target_file.parent.mkdir(parents=True, exist_ok=True)
                    target_file.write_bytes(item.read_bytes())
        node["status"] = "INTEGRATED"
        node["evidence_refs"] = node.get("evidence_refs") or []
        node["evidence_refs"].append(str(dest))
    persist(graph, {"integration_sandbox": str(integ)})
    return integ


def materialise_candidate(graph: dict[str, Any], actor_id: str) -> Path:
    gate = _validator.validate_apply_gate(graph, actor_id)
    if not gate.accepted:
        raise CanonicalMutationForbidden(gate.code + ": " + "; ".join(gate.reasons))
    root = Path(graph["sandbox_root"])
    if _validator.is_path_under(root, _validator.REPO_ROOT):
        raise CanonicalMutationForbidden("canonical repo mutation forbidden")
    integ = _sandbox.integration_sandbox(graph["run_id"], root)
    cand = _sandbox.canonical_candidate_dir(graph["run_id"], root)
    if integ.is_dir():
        for item in integ.rglob("*"):
            if item.is_file():
                rel = item.relative_to(integ)
                target = cand / rel
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(item.read_bytes())
    for node in graph["nodes"]:
        if node.get("status") == "INTEGRATED":
            node["status"] = "APPLY_CANDIDATE"
            node["canonical_apply_eligible"] = True
    persist(graph, {"canonical_candidate": str(cand), "applied_to_repo": False})
    return cand


def apply_to_repo(graph: dict[str, Any], actor_id: str) -> None:
    raise CanonicalMutationForbidden(
        "v0.1 stops before canonical application; actor={0} run={1}".format(actor_id, graph.get("run_id"))
    )


def run_graph(graph: dict[str, Any], *, recover_crashed: bool = True) -> dict[str, Any]:
    schema = _validator.schema_errors_run(graph)
    if schema:
        raise ValueError("invalid graph: " + "; ".join(schema))
    root = Path(graph["sandbox_root"])
    _sandbox.ensure_graph_root(root)
    persist(graph, {"phase": "baseline"})
    cycles = 0
    while cycles < GRAPH_MAX_ITERATIONS:
        cycles += 1
        if recover_crashed:
            for node in graph["nodes"]:
                if node.get("status") == "CRASHED":
                    node["status"] = "RETRY"
                    node["iteration"] = int(node.get("iteration") or 1) + 1
        ready = _ready_nodes(graph)
        if not ready:
            break
        limit = int(graph["max_parallel_branches"])
        batch = ready[:limit]
        valid_count = len([n for n in graph["nodes"] if n.get("status") in ("VALID", "INTEGRATED", "APPLY_CANDIDATE")])
        if valid_count >= int(graph["target_valid_proposals"]):
            break
        for node in batch:
            if valid_count >= int(graph["max_valid_proposals"]):
                break
            execute_node(graph, node)
            if node.get("status") == "VALID":
                valid_count += 1
                if valid_count >= int(graph["target_valid_proposals"]):
                    break
        persist(graph, {"phase": "cycle", "cycle": cycles})
    integrate_valid(graph)
    persist(graph, {"phase": "complete", "cycles": cycles})
    return graph


def overlay_digest(files: dict[str, str]) -> str:
    return _digest_overlay(files)
