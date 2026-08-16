#!/usr/bin/env python3
"""Contract tests for GRAPH.NODE.CONTRACT.v0.1."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

MODULE_ROOT = Path(__file__).resolve().parents[1]
SCHEMA_PATH = MODULE_ROOT / "Schemas" / "GRAPH.NODE.CONTRACT.v0.1.schema.json"
CONTRACT_PATH = MODULE_ROOT / "Contracts" / "GRAPH.EXECUTION.CONTRACT.v0.1.txt"
WORKER_PATH = MODULE_ROOT / "Workers" / "skillsmachine-sandbox-worker.mdc"
VALIDATOR_PATH = MODULE_ROOT / "Validators" / "GraphDeterministicValidator.v0.1.py"


class TestGraphContract(unittest.TestCase):
    def test_bootstrap_files_exist(self):
        self.assertTrue(SCHEMA_PATH.is_file(), SCHEMA_PATH)
        self.assertTrue(VALIDATOR_PATH.is_file(), VALIDATOR_PATH)
        self.assertTrue(WORKER_PATH.is_file(), WORKER_PATH)
        self.assertTrue(CONTRACT_PATH.is_file(), CONTRACT_PATH)

    def test_schema_has_node_and_run_defs(self):
        schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
        defs = schema["$defs"]
        node_required = set(defs["node"]["required"])
        for key in (
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
            "status",
            "retry_class",
            "canonical_apply_eligible",
        ):
            self.assertIn(key, node_required)
        run_required = set(defs["run"]["required"])
        for key in (
            "run_id",
            "architecture",
            "graph_max_iterations",
            "max_parallel_branches",
            "canonical_applier_id",
            "human_authority",
            "nodes",
        ):
            self.assertIn(key, run_required)

    def test_worker_contract_enforces_proposer_boundary(self):
        text = WORKER_PATH.read_text(encoding="utf-8")
        for token in (
            "WORKER_IS_PROPOSER=YES",
            "CANONICAL_MUTATION=FORBIDDEN",
            "SANDBOX_BOUNDARY=MANDATORY",
            "DECLARED_READ_WRITE_BOUNDARIES=MANDATORY",
            "LOCAL_BOUNDED_LOOP_MAX_ITERATIONS=6",
            "ESCALATE_CROSS_BOUNDARY_REQUIREMENTS=YES",
        ):
            self.assertIn(token, text)

    def test_no_new_skill_or_grc_claim(self):
        text = CONTRACT_PATH.read_text(encoding="utf-8")
        self.assertIn("NEW_SKILL_CREATED=NO", text)
        self.assertIn("NEW_GRC_CREATED=NO", text)
        self.assertIn("OPTION_B_HYBRID_DETERMINISTIC_GRAPH_PLUS_AI_WORKERS", text)


if __name__ == "__main__":
    unittest.main()
