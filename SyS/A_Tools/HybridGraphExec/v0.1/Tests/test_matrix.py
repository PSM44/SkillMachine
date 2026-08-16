#!/usr/bin/env python3
"""Adversarial operational matrix T01-T15 for Hybrid Graph Execution v0.1."""
from __future__ import annotations

import json
import os
import shutil
import unittest
from importlib.machinery import SourceFileLoader
from pathlib import Path

MODULE_ROOT = Path(__file__).resolve().parents[1]
CORE = MODULE_ROOT / "Core"
RUNNER = SourceFileLoader("graph_runner", str(CORE / "graph_runner.py")).load_module()
SANDBOX = SourceFileLoader("graph_sandbox", str(CORE / "graph_sandbox.py")).load_module()
VALIDATOR = SourceFileLoader(
    "graph_deterministic_validator",
    str(MODULE_ROOT / "Validators" / "GraphDeterministicValidator.v0.1.py"),
).load_module()

HEAD = "83663e8544d98e2b133af7a3a0c1aff8f07f7c7d"
REPO = VALIDATOR.REPO_ROOT
INHERITED = (
    REPO / "SkillsLake/99.CANDIDATES/SKILL.TRANSCRIPT_CONSOLIDATION_EXECUTIVE_RECONSTRUCTION.CANDIDATE.md",
    REPO / "SyS/A_Tools/SessionClose/SESSION_CLOSE.MB-SM-073A.20260731_183856.txt",
)
MATRIX = []


def record(test_id: str, setup: str, expected: str, observed: str, passed: bool, evidence: str) -> None:
    MATRIX.append(
        {
            "TEST_ID": test_id,
            "INPUT/SETUP": setup,
            "EXPECTED": expected,
            "OBSERVED": observed,
            "PASS_FAIL": "PASS" if passed else "FAIL",
            "EVIDENCE": evidence,
        }
    )


class GraphMatrixTests(unittest.TestCase):
    def setUp(self):
        self.runs = []

    def tearDown(self):
        for run_id in self.runs:
            path = SANDBOX.run_dir(run_id, VALIDATOR.GRAPH_SANDBOX_ROOT)
            if path.exists():
                shutil.rmtree(path, ignore_errors=True)

    def _graph(self, run_id, nodes, **kwargs):
        self.runs.append(run_id)
        root = str(VALIDATOR.GRAPH_SANDBOX_ROOT)
        graph = RUNNER.default_graph(run_id, nodes, recorded_head=HEAD, sandbox_root=root, **kwargs)
        for node in graph["nodes"]:
            if not node.get("sandbox_path") or node["sandbox_path"] == "pending":
                node["sandbox_path"] = str(SANDBOX.branch_sandbox(run_id, node["branch_id"], Path(root)))
        return graph

    def _node(self, run_id, node_id, branch_id, **kwargs):
        root = VALIDATOR.GRAPH_SANDBOX_ROOT
        sandbox = str(SANDBOX.branch_sandbox(run_id, branch_id, root))
        baseline = kwargs.pop("baseline", {"class": "CANONICAL_HEAD", "head": HEAD})
        return RUNNER.default_node(
            node_id,
            branch_id,
            sandbox_path=sandbox,
            baseline=baseline,
            **kwargs,
        )

    def test_T01_protected_path_denial(self):
        run_id = "G1-T01"
        node = self._node(
            run_id,
            "n1",
            "b1",
            write_set=["out/a.txt", "secret/x.txt"],
            protected_paths=["secret"],
            fixture_ops=[{"op": "write", "path": "secret/x.txt", "content": "nope"}],
            status="PENDING",
        )
        graph = self._graph(run_id, [node])
        RUNNER.execute_node(graph, node)
        passed = node["proposal_status"] == "DENY_PROTECTED_PATH"
        record(
            "T01",
            "write secret/x.txt with protected_paths=secret",
            "DENY_PROTECTED_PATH",
            str(node["proposal_status"]),
            passed,
            json.dumps(node.get("evidence_refs")),
        )
        self.assertTrue(passed)

    def test_T02_write_set_denial(self):
        run_id = "G1-T02"
        node = self._node(
            run_id,
            "n1",
            "b1",
            write_set=["out/a.txt"],
            fixture_ops=[{"op": "write", "path": "out/b.txt", "content": "x"}],
        )
        graph = self._graph(run_id, [node])
        RUNNER.execute_node(graph, node)
        passed = node["proposal_status"] == "DENY_WRITE_SET"
        record("T02", "write out/b.txt with write_set=out/a.txt", "DENY_WRITE_SET", str(node["proposal_status"]), passed, str(node.get("evidence_refs")))
        self.assertTrue(passed)

    def test_T03_read_set_denial(self):
        run_id = "G1-T03"
        node = self._node(
            run_id,
            "n1",
            "b1",
            write_set=["out/a.txt"],
            read_set=["in/a.txt"],
            fixture_ops=[
                {"op": "write", "path": "out/a.txt", "content": "x"},
                {"op": "read", "path": "other/z.txt"},
            ],
        )
        graph = self._graph(run_id, [node])
        RUNNER.execute_node(graph, node)
        passed = node["proposal_status"] == "DENY_READ_SET"
        record("T03", "read other/z.txt with read_set=in/a.txt", "DENY_READ_SET", str(node["proposal_status"]), passed, str(node.get("evidence_refs")))
        self.assertTrue(passed)

    def test_T04_resource_lock_conflict(self):
        run_id = "G1-T04"
        a = self._node(run_id, "n1", "b1", write_set=["out/a.txt"], resource_locks=["db"], fixture_ops=[{"op": "write", "path": "out/a.txt", "content": "a"}, {"op": "lock", "name": "db"}])
        b = self._node(run_id, "n2", "b2", write_set=["out/b.txt"], resource_locks=["db"], fixture_ops=[{"op": "write", "path": "out/b.txt", "content": "b"}, {"op": "lock", "name": "db"}])
        graph = self._graph(run_id, [a, b])
        RUNNER.execute_node(graph, a)
        RUNNER.execute_node(graph, b)
        passed = a["status"] == "VALID" and b["proposal_status"] == "DENY_RESOURCE_LOCK"
        record("T04", "two branches lock db", "second DENY_RESOURCE_LOCK", "{0}/{1}".format(a["status"], b["proposal_status"]), passed, str(b.get("evidence_refs")))
        self.assertTrue(passed)

    def test_T05_physical_line_collision(self):
        run_id = "G1-T05"
        a = self._node(
            run_id,
            "n1",
            "b1",
            write_set=["src/file.txt"],
            fixture_ops=[{"op": "write", "path": "src/file.txt", "content": "aaaa", "start": 1, "end": 4}],
        )
        b = self._node(
            run_id,
            "n2",
            "b2",
            write_set=["src/file.txt"],
            fixture_ops=[{"op": "write", "path": "src/file.txt", "content": "bbbb", "start": 3, "end": 6}],
        )
        graph = self._graph(run_id, [a, b])
        RUNNER.execute_node(graph, a)
        RUNNER.execute_node(graph, b)
        passed = a["status"] == "VALID" and b["proposal_status"] == "DENY_LINE_COLLISION"
        record("T05", "overlapping line spans 1-4 and 3-6 on src/file.txt", "DENY_LINE_COLLISION", "{0}/{1}".format(a["status"], b["proposal_status"]), passed, str(b.get("evidence_refs")))
        self.assertTrue(passed)

    def test_T06_baseline_mismatch(self):
        run_id = "G1-T06"
        node = self._node(
            run_id,
            "n1",
            "b1",
            write_set=["out/a.txt"],
            baseline={"class": "CANONICAL_HEAD", "head": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"},
            fixture_ops=[{"op": "write", "path": "out/a.txt", "content": "x"}],
        )
        graph = self._graph(run_id, [node])
        RUNNER.execute_node(graph, node)
        passed = node["proposal_status"] == "DENY_BASELINE"
        record("T06", "node CANONICAL_HEAD != recorded_head", "DENY_BASELINE", str(node["proposal_status"]), passed, str(node.get("evidence_refs")))
        self.assertTrue(passed)

    def test_T07_max_iteration_violation(self):
        run_id = "G1-T07"
        node = self._node(
            run_id,
            "n1",
            "b1",
            write_set=["out/a.txt"],
            iteration=11,
            max_iterations=10,
            fixture_ops=[{"op": "write", "path": "out/a.txt", "content": "x"}],
        )
        graph = self._graph(run_id, [node])
        RUNNER.execute_node(graph, node)
        passed = node["proposal_status"] == "DENY_MAX_ITERATION"
        record("T07", "iteration=11 graph ceiling=10", "DENY_MAX_ITERATION", str(node["proposal_status"]), passed, str(node.get("evidence_refs")))
        self.assertTrue(passed)

    def test_T08_max_parallel_branch_violation(self):
        run_id = "G1-T08"
        a = self._node(run_id, "n1", "b1", write_set=["out/a.txt"], status="RUNNING")
        b = self._node(run_id, "n2", "b2", write_set=["out/b.txt"], status="RUNNING")
        graph = self._graph(run_id, [a, b], max_parallel_branches=1)
        result = VALIDATOR.validate_node(b, graph, [a, b])
        passed = result.code == "DENY_MAX_PARALLEL"
        record("T08", "two RUNNING nodes with max_parallel_branches=1", "DENY_MAX_PARALLEL", result.code, passed, ";".join(result.reasons))
        self.assertTrue(passed)

    def test_T09_cross_branch_sandbox_isolation(self):
        run_id = "G1-T09"
        a = self._node(run_id, "n1", "b1", write_set=["out/a.txt"], fixture_ops=[{"op": "write", "path": "out/a.txt", "content": "a"}])
        graph = self._graph(run_id, [a])
        RUNNER.execute_node(graph, a)
        sibling = Path(a["sandbox_path"])
        b = self._node(
            run_id,
            "n2",
            "b2",
            write_set=["out/b.txt"],
            fixture_ops=[{"op": "escape", "target": str(sibling / "out" / "hacked.txt")}],
        )
        graph["nodes"].append(b)
        RUNNER.execute_node(graph, b)
        isolated = Path(a["sandbox_path"]).resolve() != Path(b["sandbox_path"]).resolve()
        passed = isolated and b["proposal_status"] == "DENY_SANDBOX_ISOLATION" and not (sibling / "out" / "hacked.txt").exists()
        record("T09", "branch B escape-write into branch A sandbox", "DENY_SANDBOX_ISOLATION and distinct sandboxes", "{0} isolated={1}".format(b["proposal_status"], isolated), passed, b["sandbox_path"])
        self.assertTrue(passed)

    def test_T10_integration_sandbox(self):
        run_id = "G1-T10"
        a = self._node(run_id, "n1", "b1", write_set=["out/a.txt"], fixture_ops=[{"op": "write", "path": "out/a.txt", "content": "A"}])
        b = self._node(run_id, "n2", "b2", write_set=["out/b.txt"], fixture_ops=[{"op": "write", "path": "out/b.txt", "content": "B"}])
        graph = self._graph(run_id, [a, b], max_parallel_branches=2, target_valid_proposals=2)
        RUNNER.run_graph(graph)
        integ = SANDBOX.integration_sandbox(run_id, VALIDATOR.GRAPH_SANDBOX_ROOT)
        a_copy = integ / "b1" / "out" / "a.txt"
        b_copy = integ / "b2" / "out" / "b.txt"
        repo_pollution = (REPO / "out" / "a.txt").exists()
        passed = a_copy.is_file() and b_copy.is_file() and not repo_pollution
        record("T10", "two valid proposals then integrate", "integration sandbox holds both copies; repo untouched", "a={0} b={1} repo={2}".format(a_copy.is_file(), b_copy.is_file(), repo_pollution), passed, str(integ))
        self.assertTrue(passed)

    def test_T11_dirty_snapshot_overlay_baseline(self):
        run_id = "G1-T11"
        overlay_files = {"scratch/dirty.txt": "overlay-not-head"}
        digest = RUNNER.overlay_digest(overlay_files)
        good = self._node(
            run_id,
            "n1",
            "b1",
            write_set=["scratch/dirty.txt"],
            baseline={
                "class": "SNAPSHOT_OVERLAY",
                "canonical_head": HEAD,
                "overlay_id": "fixture-dirty-001",
                "overlay_digest": digest,
                "treat_as_canonical_head": False,
            },
            fixture_ops=[{"op": "write", "path": "scratch/dirty.txt", "content": "overlay-not-head"}],
        )
        bad = self._node(
            run_id,
            "n2",
            "b2",
            write_set=["scratch/dirty.txt"],
            baseline={
                "class": "SNAPSHOT_OVERLAY",
                "canonical_head": HEAD,
                "overlay_id": "fixture-dirty-001",
                "overlay_digest": digest,
                "treat_as_canonical_head": True,
            },
            fixture_ops=[{"op": "write", "path": "scratch/dirty.txt", "content": "overlay-not-head"}],
        )
        graph = self._graph(
            run_id,
            [good, bad],
            baseline={
                "class": "SNAPSHOT_OVERLAY",
                "canonical_head": HEAD,
                "overlay_id": "fixture-dirty-001",
                "overlay_digest": digest,
                "treat_as_canonical_head": False,
            },
        )
        RUNNER.execute_node(graph, good)
        RUNNER.execute_node(graph, bad)
        inherited_untouched = all(p.exists() for p in INHERITED)
        passed = (
            good["status"] == "VALID"
            and bad["proposal_status"] == "DENY_BASELINE"
            and inherited_untouched
            and good["baseline"]["overlay_id"] != HEAD
        )
        record(
            "T11",
            "SNAPSHOT_OVERLAY dirty fixture; do not use inherited DEFER/EXCLUDE",
            "overlay accepted when not treated as HEAD; treat_as_canonical_head denied",
            "{0}/{1}".format(good["status"], bad["proposal_status"]),
            passed,
            "digest=" + digest,
        )
        self.assertTrue(passed)

    def test_T12_single_canonical_applier(self):
        run_id = "G1-T12"
        node = self._node(
            run_id,
            "n1",
            "b1",
            write_set=["out/a.txt"],
            fixture_ops=[{"op": "write", "path": "out/a.txt", "content": "A"}],
            actor_role="CANONICAL_APPLIER",
            actor_id="intruder",
        )
        node["apply_requested"] = True
        graph = self._graph(run_id, [node], human_authority=True, canonical_applier_id="applier-1")
        result = VALIDATOR.validate_node(node, graph, [node])
        passed = result.code == "DENY_CANONICAL_APPLIER"
        record("T12", "apply_requested by actor_id=intruder designated=applier-1", "DENY_CANONICAL_APPLIER", result.code, passed, ";".join(result.reasons))
        self.assertTrue(passed)

    def test_T13_retry_taxonomy(self):
        mapping = {
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
        observed = {code: VALIDATOR.RETRY_FOR_CODE[code] for code in mapping}
        passed = observed == mapping
        record("T13", "retry taxonomy table", str(mapping), str(observed), passed, "RETRY_FOR_CODE")
        self.assertTrue(passed)

    def test_T14_human_authority_gate(self):
        run_id = "G1-T14"
        node = self._node(
            run_id,
            "n1",
            "b1",
            write_set=["out/a.txt"],
            actor_role="CANONICAL_APPLIER",
            actor_id="applier-1",
            fixture_ops=[{"op": "write", "path": "out/a.txt", "content": "A"}],
        )
        node["apply_requested"] = True
        node["canonical_apply_eligible"] = True
        graph = self._graph(run_id, [node], human_authority=False, canonical_applier_id="applier-1")
        result = VALIDATOR.validate_node(node, graph, [node])
        blocked = False
        try:
            RUNNER.materialise_candidate(graph, "applier-1")
        except RUNNER.CanonicalMutationForbidden:
            blocked = True
        apply_repo_blocked = False
        try:
            RUNNER.apply_to_repo(graph, "applier-1")
        except RUNNER.CanonicalMutationForbidden:
            apply_repo_blocked = True
        passed = result.code == "DENY_HUMAN_AUTHORITY" and blocked and apply_repo_blocked
        record(
            "T14",
            "designated applier without human_authority",
            "DENY_HUMAN_AUTHORITY and no repo apply",
            "{0} materialise_blocked={1} repo_blocked={2}".format(result.code, blocked, apply_repo_blocked),
            passed,
            ";".join(result.reasons),
        )
        self.assertTrue(passed)

    def test_T15_crash_recovery(self):
        run_id = "G1-T15"
        node = self._node(
            run_id,
            "n1",
            "b1",
            write_set=["out/a.txt"],
            fixture_ops=[{"op": "crash"}],
        )
        graph = self._graph(run_id, [node])
        RUNNER.execute_node(graph, node)
        crashed = node["status"] == "CRASHED"
        state_path = SANDBOX.run_dir(run_id, VALIDATOR.GRAPH_SANDBOX_ROOT) / "run_state.json"
        recovered = RUNNER.recover(run_id, str(VALIDATOR.GRAPH_SANDBOX_ROOT))
        rec_node = recovered["nodes"][0]
        rec_node["fixture_ops"] = [{"op": "write", "path": "out/a.txt", "content": "recovered"}]
        rec_node["status"] = "RETRY"
        rec_node["iteration"] = 2
        RUNNER.execute_node(recovered, rec_node)
        passed = crashed and state_path.is_file() and rec_node["status"] == "VALID" and rec_node["retry_class"] == "NONE"
        record(
            "T15",
            "fixture crash then recover run_state.json and retry write",
            "CRASHED contained, recoverable, retry VALID",
            "crash={0} state={1} final={2}".format(crashed, state_path.is_file(), rec_node["status"]),
            passed,
            str(state_path),
        )
        self.assertTrue(passed)

    def test_canonical_mutation_forbidden_to_repo(self):
        run_id = "G1-NOCANON"
        node = self._node(run_id, "n1", "b1", write_set=["out/a.txt"], fixture_ops=[{"op": "write", "path": "out/a.txt", "content": "A"}])
        graph = self._graph(run_id, [node], human_authority=True)
        RUNNER.execute_node(graph, node)
        RUNNER.integrate_valid(graph)
        cand = RUNNER.materialise_candidate(graph, "applier-1")
        self.assertTrue(str(cand).lower().startswith(str(VALIDATOR.GRAPH_SANDBOX_ROOT).lower()))
        self.assertFalse(VALIDATOR.is_path_under(cand, REPO))
        with self.assertRaises(RUNNER.CanonicalMutationForbidden):
            RUNNER.apply_to_repo(graph, "applier-1")


def write_matrix(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(MATRIX, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(GraphMatrixTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    out = VALIDATOR.GRAPH_SANDBOX_ROOT / "runs" / "_last_matrix.json"
    write_matrix(out)
    raise SystemExit(0 if result.wasSuccessful() else 1)
