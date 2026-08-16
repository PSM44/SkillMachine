#!/usr/bin/env python3
"""GraphDeterministicValidator.v0.1

Physical/resource/authority-gate checks only.
Semantic proposal quality is out of scope.
Workers are proposers. This validator never mutates canonical files.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any

SCHEMA_VERSION = "0.1"
GRAPH_MAX_ITERATIONS = 10
BOUNDED_LOOP_MAX = 6
DEFAULT_TARGET_VALID_PROPOSALS = 2
DEFAULT_MAX_VALID_PROPOSALS = 3
ARCHITECTURE = "OPTION_B_HYBRID_DETERMINISTIC_GRAPH_PLUS_AI_WORKERS"

REPO_ROOT = Path(r"C:\01. GitHub\Skills").resolve()
GRAPH_SANDBOX_ROOT = Path(r"C:\Users\aazcl\Downloads\T.AI.SkillsMachineGrafos").resolve()
AI_EXCHANGE_TEMP = Path(r"C:\Users\aazcl\Downloads\T.AI.SkillMachine").resolve()

ACTIVE_LOCK_STATUSES = frozenset({"READY", "RUNNING", "VALID", "PROPOSED", "APPLY_CANDIDATE"})
PARALLEL_STATUSES = frozenset({"READY", "RUNNING"})
COLLISION_STATUSES = frozenset({"VALID", "PROPOSED", "APPLY_CANDIDATE", "RUNNING"})

NODE_REQUIRED = (
    "schema_version",
    "node_id",
    "branch_id",
    "baseline",
    "parent_node_ids",
    "read_set",
    "write_set",
    "protected_paths",
    "resource_locks",
    "sandbox_path",
    "iteration",
    "max_iterations",
    "local_bounded_loop_max_iterations",
    "status",
    "retry_class",
    "canonical_apply_eligible",
    "actor_role",
    "actor_id",
    "apply_requested",
    "observed_reads",
    "observed_writes",
    "observed_line_spans",
)
RUN_REQUIRED = (
    "schema_version",
    "run_id",
    "architecture",
    "graph_max_iterations",
    "max_parallel_branches",
    "target_valid_proposals",
    "max_valid_proposals",
    "sandbox_root",
    "recorded_head",
    "baseline",
    "canonical_applier_id",
    "human_authority",
    "worker_is_proposer",
    "canonical_mutation_forbidden",
    "nodes",
)

RETRY_FOR_CODE = {
    "ACCEPT": "NONE",
    "DENY_SCHEMA": "BOUNDARY",
    "DENY_PROTECTED_PATH": "BOUNDARY",
    "DENY_WRITE_SET": "BOUNDARY",
    "DENY_READ_SET": "BOUNDARY",
    "DENY_RESOURCE_LOCK": "CONFLICT",
    "DENY_LINE_COLLISION": "CONFLICT",
    "DENY_BASELINE": "BASELINE",
    "DENY_MAX_ITERATION": "ITERATION",
    "DENY_MAX_PARALLEL": "PARALLEL",
    "DENY_SANDBOX_ISOLATION": "ISOLATION",
    "DENY_CANONICAL_APPLIER": "AUTHORITY",
    "DENY_HUMAN_AUTHORITY": "AUTHORITY",
    "DENY_CRASH_CONTAINED": "TRANSIENT",
}


class ValidationResult:
    def __init__(self, accepted: bool, code: str, reasons: list[str] | None = None):
        self.accepted = accepted
        self.code = code
        self.reasons = list(reasons or [])
        self.retry_class = RETRY_FOR_CODE.get(code, "BOUNDARY")

    def to_dict(self) -> dict[str, Any]:
        return {
            "accepted": self.accepted,
            "code": self.code,
            "retry_class": self.retry_class,
            "reasons": self.reasons,
        }


def _fail(code: str, *reasons: str) -> ValidationResult:
    return ValidationResult(False, code, list(reasons))


def _ok(note: str = "") -> ValidationResult:
    reasons = [note] if note else []
    return ValidationResult(True, "ACCEPT", reasons)


def normalize_rel(path_value: str) -> str:
    raw = str(path_value).replace("\\", "/").strip()
    while raw.startswith("./"):
        raw = raw[2:]
    return raw


def is_rel_under(child: str, parent: str) -> bool:
    c = normalize_rel(child).lower()
    p = normalize_rel(parent).lower().rstrip("/")
    if c == p:
        return True
    return c.startswith(p + "/")


def is_path_under(child: Path, parent: Path) -> bool:
    try:
        child.resolve().relative_to(parent.resolve())
        return True
    except (OSError, ValueError):
        return False


def _as_list(value: Any) -> list[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def _observed_rel(entry: str, sandbox: Path) -> str:
    raw = str(entry)
    p = Path(raw)
    if p.is_absolute():
        try:
            return normalize_rel(str(p.resolve().relative_to(sandbox.resolve())))
        except ValueError:
            return normalize_rel(raw)
    return normalize_rel(raw)


def schema_errors_node(node: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if not isinstance(node, dict):
        return ["node is not an object"]
    for key in NODE_REQUIRED:
        if key not in node:
            errors.append("missing:" + key)
    if node.get("schema_version") != SCHEMA_VERSION:
        errors.append("schema_version must be 0.1")
    if node.get("local_bounded_loop_max_iterations") != BOUNDED_LOOP_MAX:
        errors.append("local_bounded_loop_max_iterations must be 6")
    baseline = node.get("baseline")
    if not isinstance(baseline, dict) or baseline.get("class") not in (
        "CANONICAL_HEAD",
        "SNAPSHOT_OVERLAY",
        "SANDBOX_FIXTURE",
    ):
        errors.append("baseline.class invalid")
    return errors


def schema_errors_run(graph: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if not isinstance(graph, dict):
        return ["run is not an object"]
    for key in RUN_REQUIRED:
        if key not in graph:
            errors.append("missing:" + key)
    if graph.get("schema_version") != SCHEMA_VERSION:
        errors.append("schema_version must be 0.1")
    if graph.get("architecture") != ARCHITECTURE:
        errors.append("architecture mismatch")
    if graph.get("graph_max_iterations") != GRAPH_MAX_ITERATIONS:
        errors.append("graph_max_iterations must be 10")
    if graph.get("worker_is_proposer") is not True:
        errors.append("worker_is_proposer must be true")
    if graph.get("canonical_mutation_forbidden") is not True:
        errors.append("canonical_mutation_forbidden must be true")
    tmax = graph.get("target_valid_proposals")
    mmax = graph.get("max_valid_proposals")
    if isinstance(tmax, int) and isinstance(mmax, int) and tmax > mmax:
        errors.append("target_valid_proposals exceeds max_valid_proposals")
    nodes = graph.get("nodes")
    if not isinstance(nodes, list):
        errors.append("nodes must be an array")
    else:
        for idx, node in enumerate(nodes):
            for err in schema_errors_node(node):
                errors.append("node[{0}].{1}".format(idx, err))
    return errors


def _baseline_errors(node: dict[str, Any], graph: dict[str, Any]) -> list[str]:
    reasons: list[str] = []
    nb = node.get("baseline") or {}
    gb = graph.get("baseline") or {}
    nclass = nb.get("class")
    if nclass == "SNAPSHOT_OVERLAY" and nb.get("treat_as_canonical_head") is True:
        reasons.append("SNAPSHOT_OVERLAY must not be treated as CANONICAL_HEAD")
    if nclass == "CANONICAL_HEAD":
        declared = nb.get("head") or nb.get("canonical_head")
        recorded = graph.get("recorded_head")
        if recorded and declared and str(declared) != str(recorded):
            reasons.append("CANONICAL_HEAD mismatch vs recorded_head")
        if gb.get("class") == "SNAPSHOT_OVERLAY" and nclass == "CANONICAL_HEAD":
            reasons.append("node claims CANONICAL_HEAD while graph baseline is SNAPSHOT_OVERLAY")
    if nclass == "SNAPSHOT_OVERLAY":
        if not nb.get("overlay_id"):
            reasons.append("SNAPSHOT_OVERLAY requires overlay_id")
        canonical = nb.get("canonical_head") or gb.get("canonical_head") or graph.get("recorded_head")
        if canonical and graph.get("recorded_head") and str(canonical) != str(graph.get("recorded_head")):
            reasons.append("overlay canonical_head mismatch vs recorded_head")
    return reasons


def _sandbox_errors(node: dict[str, Any], graph: dict[str, Any]) -> list[str]:
    reasons: list[str] = []
    sandbox_root = Path(str(graph.get("sandbox_root") or GRAPH_SANDBOX_ROOT))
    try:
        sandbox = Path(str(node.get("sandbox_path") or "")).resolve()
    except OSError:
        return ["sandbox_path unresolvable"]
    if not str(node.get("sandbox_path") or "").strip():
        return ["sandbox_path empty"]
    if is_path_under(sandbox, REPO_ROOT):
        reasons.append("sandbox_path under canonical repo root")
    if is_path_under(sandbox, AI_EXCHANGE_TEMP):
        reasons.append("sandbox_path under flat AI-exchange temp")
    if not is_path_under(sandbox, sandbox_root):
        reasons.append("sandbox_path not under graph sandbox_root")
    for entry in _as_list(node.get("observed_writes")):
        raw = str(entry)
        p = Path(raw)
        if p.is_absolute() and not is_path_under(p, sandbox):
            reasons.append("observed write escapes sandbox: " + raw)
        rel = _observed_rel(raw, sandbox)
        if ".." in rel.split("/"):
            reasons.append("observed write path escape: " + rel)
    return reasons


def _set_errors(node: dict[str, Any], graph: dict[str, Any], kind: str) -> list[str]:
    sandbox = Path(str(node.get("sandbox_path") or ".")).resolve()
    declared = [normalize_rel(x) for x in _as_list(node.get(kind + "_set"))]
    observed_key = "observed_writes" if kind == "write" else "observed_reads"
    reasons: list[str] = []
    for entry in _as_list(node.get(observed_key)):
        rel = _observed_rel(str(entry), sandbox)
        if not any(is_rel_under(rel, d) for d in declared):
            reasons.append("{0} not in {1}_set: {2}".format(kind, kind, rel))
    return reasons


def _protected_errors(node: dict[str, Any]) -> list[str]:
    sandbox = Path(str(node.get("sandbox_path") or ".")).resolve()
    protected = [normalize_rel(x) for x in _as_list(node.get("protected_paths"))]
    reasons: list[str] = []
    for entry in _as_list(node.get("observed_writes")) + _as_list(node.get("observed_reads")):
        rel = _observed_rel(str(entry), sandbox)
        for p in protected:
            if is_rel_under(rel, p):
                reasons.append("protected-path access: " + rel)
    return reasons


def _lock_errors(node: dict[str, Any], peers: list[dict[str, Any]]) -> list[str]:
    mine = set(_as_list(node.get("observed_locks") or node.get("resource_locks")))
    if node.get("status") not in ACTIVE_LOCK_STATUSES and not mine:
        mine = set(_as_list(node.get("resource_locks")))
    reasons: list[str] = []
    nid = node.get("node_id")
    for peer in peers:
        if peer is node or peer.get("node_id") == nid:
            continue
        if peer.get("status") not in ACTIVE_LOCK_STATUSES:
            continue
        theirs = set(_as_list(peer.get("observed_locks") or peer.get("resource_locks")))
        clash = mine.intersection(theirs)
        if clash:
            reasons.append(
                "resource-lock conflict with {0}: {1}".format(peer.get("node_id"), ",".join(sorted(clash)))
            )
    return reasons


def _span_overlap(a: dict[str, Any], b: dict[str, Any]) -> bool:
    if normalize_rel(str(a.get("path"))) != normalize_rel(str(b.get("path"))):
        return False
    try:
        a0, a1 = int(a.get("start")), int(a.get("end"))
        b0, b1 = int(b.get("start")), int(b.get("end"))
    except (TypeError, ValueError):
        return False
    if a1 < a0:
        a0, a1 = a1, a0
    if b1 < b0:
        b0, b1 = b1, b0
    return not (a1 < b0 or b1 < a0)


def _collision_errors(node: dict[str, Any], peers: list[dict[str, Any]]) -> list[str]:
    mine = [s for s in _as_list(node.get("observed_line_spans")) if isinstance(s, dict)]
    reasons: list[str] = []
    nid = node.get("node_id")
    for peer in peers:
        if peer.get("node_id") == nid:
            continue
        if peer.get("status") not in COLLISION_STATUSES:
            continue
        for a in mine:
            for b in _as_list(peer.get("observed_line_spans")):
                if isinstance(b, dict) and _span_overlap(a, b):
                    reasons.append(
                        "line collision with {0} on {1}".format(peer.get("node_id"), a.get("path"))
                    )
    return reasons


def _iteration_errors(node: dict[str, Any], graph: dict[str, Any]) -> list[str]:
    reasons: list[str] = []
    try:
        iteration = int(node.get("iteration"))
        node_max = int(node.get("max_iterations"))
    except (TypeError, ValueError):
        return ["iteration fields not integers"]
    graph_max = int(graph.get("graph_max_iterations") or GRAPH_MAX_ITERATIONS)
    ceiling = min(node_max, graph_max, GRAPH_MAX_ITERATIONS)
    if iteration > ceiling:
        reasons.append("iteration {0} exceeds ceiling {1}".format(iteration, ceiling))
    return reasons


def _parallel_errors(node: dict[str, Any], graph: dict[str, Any], peers: list[dict[str, Any]]) -> list[str]:
    try:
        limit = int(graph.get("max_parallel_branches"))
    except (TypeError, ValueError):
        return ["max_parallel_branches invalid"]
    running = [p for p in peers if p.get("status") in PARALLEL_STATUSES]
    if node.get("status") in PARALLEL_STATUSES and all(p.get("node_id") != node.get("node_id") for p in running):
        running.append(node)
    # unique by node_id
    seen = set()
    uniq = []
    for p in running:
        nid = p.get("node_id")
        if nid in seen:
            continue
        seen.add(nid)
        uniq.append(p)
    if len(uniq) > limit:
        return ["parallel branches {0} exceed limit {1}".format(len(uniq), limit)]
    return []


def _authority_errors(node: dict[str, Any], graph: dict[str, Any], peers: list[dict[str, Any]]) -> list[str]:
    reasons: list[str] = []
    role = node.get("actor_role")
    if role == "PROPOSER" and node.get("canonical_apply_eligible") is True:
        reasons.append("proposer cannot be canonical-apply eligible")
    if role == "PROPOSER" and node.get("apply_requested") is True:
        reasons.append("proposer cannot request canonical apply")
    if node.get("apply_requested") is True or node.get("canonical_apply_eligible") is True:
        if graph.get("human_authority") is not True:
            reasons.append("canonical apply requires human_authority")
        applier = graph.get("canonical_applier_id")
        if not applier:
            reasons.append("canonical apply requires canonical_applier_id")
        elif node.get("actor_role") == "CANONICAL_APPLIER" and node.get("actor_id") != applier:
            reasons.append("actor_id is not the single canonical applier")
    appliers = []
    for p in peers + [node]:
        if p.get("actor_role") == "CANONICAL_APPLIER":
            appliers.append(p.get("actor_id"))
    distinct = {a for a in appliers if a}
    designated = graph.get("canonical_applier_id")
    if designated and any(a != designated for a in distinct):
        reasons.append("non-designated canonical applier present")
    if len(distinct) > 1:
        reasons.append("multiple canonical appliers")
    return reasons


def validate_node(
    node: dict[str, Any],
    graph: dict[str, Any],
    peers: list[dict[str, Any]] | None = None,
) -> ValidationResult:
    schema = schema_errors_node(node)
    if schema:
        return _fail("DENY_SCHEMA", *schema)
    peer_list = list(peers if peers is not None else graph.get("nodes") or [])

    protected = _protected_errors(node)
    if protected:
        return _fail("DENY_PROTECTED_PATH", *protected)

    writes = _set_errors(node, graph, "write")
    if writes:
        return _fail("DENY_WRITE_SET", *writes)

    reads = _set_errors(node, graph, "read")
    if reads:
        return _fail("DENY_READ_SET", *reads)

    locks = _lock_errors(node, peer_list)
    if locks:
        return _fail("DENY_RESOURCE_LOCK", *locks)

    collisions = _collision_errors(node, peer_list)
    if collisions:
        return _fail("DENY_LINE_COLLISION", *collisions)

    baseline = _baseline_errors(node, graph)
    if baseline:
        return _fail("DENY_BASELINE", *baseline)

    iteration = _iteration_errors(node, graph)
    if iteration:
        return _fail("DENY_MAX_ITERATION", *iteration)

    parallel = _parallel_errors(node, graph, peer_list)
    if parallel:
        return _fail("DENY_MAX_PARALLEL", *parallel)

    isolation = _sandbox_errors(node, graph)
    if isolation:
        return _fail("DENY_SANDBOX_ISOLATION", *isolation)

    authority = _authority_errors(node, graph, peer_list)
    if authority:
        applier_hit = any(
            ("applier" in r.lower()) or ("proposer cannot" in r.lower()) or ("multiple canonical" in r.lower())
            for r in authority
        )
        human_hit = any("human_authority" in r for r in authority)
        code = "DENY_CANONICAL_APPLIER" if applier_hit else "DENY_HUMAN_AUTHORITY"
        if human_hit and not applier_hit:
            code = "DENY_HUMAN_AUTHORITY"
        return _fail(code, *authority)

    return _ok("node accepted")


def validate_graph(graph: dict[str, Any]) -> ValidationResult:
    schema = schema_errors_run(graph)
    if schema:
        return _fail("DENY_SCHEMA", *schema)
    nodes = list(graph.get("nodes") or [])
    for node in nodes:
        result = validate_node(node, graph, nodes)
        if not result.accepted and node.get("status") in ("RUNNING", "VALID", "APPLY_CANDIDATE", "READY"):
            return result
    return _ok("graph accepted")


def validate_apply_gate(graph: dict[str, Any], actor_id: str) -> ValidationResult:
    if graph.get("human_authority") is not True:
        return _fail("DENY_HUMAN_AUTHORITY", "human_authority=false")
    designated = graph.get("canonical_applier_id")
    if not designated or actor_id != designated:
        return _fail("DENY_CANONICAL_APPLIER", "actor is not the single canonical applier")
    if is_path_under(Path(str(graph.get("sandbox_root"))), REPO_ROOT):
        return _fail("DENY_SANDBOX_ISOLATION", "apply sandbox_root under repo is forbidden in v0.1 tests")
    return _ok("apply gate open for candidate materialisation in sandbox only")


def load_json(path: str) -> dict[str, Any]:
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError("JSON root must be an object")
    return data


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Hybrid graph deterministic validator v0.1")
    parser.add_argument("--graph", required=True, help="Path to graph run JSON")
    parser.add_argument("--node-id", default="", help="Optional node_id to validate alone")
    parser.add_argument("--json-out", default="", help="Optional result JSON path")
    args = parser.parse_args(argv)
    graph = load_json(args.graph)
    if args.node_id:
        node = next((n for n in graph.get("nodes") or [] if n.get("node_id") == args.node_id), None)
        if node is None:
            result = _fail("DENY_SCHEMA", "node_id not found")
        else:
            result = validate_node(node, graph, list(graph.get("nodes") or []))
    else:
        result = validate_graph(graph)
    payload = result.to_dict()
    text = json.dumps(payload, indent=2)
    if args.json_out:
        out = Path(args.json_out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(text + os.linesep, encoding="utf-8")
    sys.stdout.write(text + "\n")
    return 0 if result.accepted else 2


if __name__ == "__main__":
    sys.exit(main())
