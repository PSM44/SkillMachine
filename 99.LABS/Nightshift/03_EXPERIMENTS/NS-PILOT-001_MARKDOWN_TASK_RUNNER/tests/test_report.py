import unittest
from src.report import generate


class TestGenerate(unittest.TestCase):
    def setUp(self):
        self.items = {
            "pending": ["- [ ] B task", "- [ ] A task"],
            "done": ["- [x] Done"],
            "blocked": ["- [!] Blocker"],
        }
        self.report = generate(self.items, source="test.md")

    def test_header(self):
        self.assertIn("# TASK REPORT", self.report)

    def test_source(self):
        self.assertIn("SOURCE: test.md", self.report)

    def test_sections_present(self):
        self.assertIn("## PENDING", self.report)
        self.assertIn("## DONE", self.report)
        self.assertIn("## BLOCKED", self.report)

    def test_counts_in_header(self):
        self.assertIn("## PENDING (2)", self.report)
        self.assertIn("## DONE (1)", self.report)
        self.assertIn("## BLOCKED (1)", self.report)

    def test_sorted_pending(self):
        lines = self.report.splitlines()
        pending_idx = next(i for i, l in enumerate(lines) if "## PENDING" in l)
        a_idx = next(i for i, l in enumerate(lines) if "A task" in l)
        b_idx = next(i for i, l in enumerate(lines) if "B task" in l)
        self.assertLess(a_idx, b_idx)
        self.assertGreater(a_idx, pending_idx)

    def test_deterministic(self):
        r1 = generate(self.items, source="test.md")
        r2 = generate(self.items, source="test.md")
        self.assertEqual(r1, r2)


if __name__ == "__main__":
    unittest.main()
